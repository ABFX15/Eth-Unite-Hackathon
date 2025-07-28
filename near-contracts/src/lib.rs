use near_sdk::borsh::{self, BorshDeserialize, BorshSerialize};
use near_sdk::collections::{LookupMap, UnorderedMap, Vector};
use near_sdk::json_types::{U128, U64};
use near_sdk::serde::{Deserialize, Serialize};
use near_sdk::{
    env, near_bindgen, AccountId, Balance, BlockHeight, Gas, PanicOnDefault, 
    Promise, PromiseResult, PublicKey, CryptoHash
};
use sha2::{Digest, Sha256};

pub const TGAS: u64 = 1_000_000_000_000;
pub const GAS_FOR_CROSS_CHAIN_CALL: Gas = Gas(50 * TGAS);

#[derive(BorshDeserialize, BorshSerialize, Serialize, Deserialize, Clone)]
#[serde(crate = "near_sdk::serde")]
pub struct CrossChainOrder {
    pub order_id: u64,
    pub maker: AccountId,
    pub token_in: AccountId,      // NEAR token (near, wrap.near, etc.)
    pub token_out: String,        // ETH token address
    pub amount_in: U128,
    pub base_price: U128,         // Base price without slippage
    pub current_slippage: u64,    // Current dynamic slippage in basis points
    pub max_slippage_deviation: u64,
    pub target_chain_id: u64,     // Ethereum = 1, Polygon = 137, etc.
    pub hashlock: String,         // 32-byte hash (hex encoded)
    pub timelock: U64,           // Block height for timelock
    pub secret: Option<String>,   // Secret that unlocks the hashlock
    pub status: OrderStatus,
    pub created_at: U64,
    pub last_slippage_update: U64,
    pub fill_attempts: u64,
}

#[derive(BorshDeserialize, BorshSerialize, Serialize, Deserialize, Clone)]
#[serde(crate = "near_sdk::serde")]
pub enum OrderStatus {
    Active,      // Order is active and waiting
    Locked,      // Tokens locked, waiting for claim
    Completed,   // Successfully completed
    Expired,     // Timelock expired
    Cancelled,   // Cancelled by maker
}

#[derive(BorshDeserialize, BorshSerialize, Serialize, Deserialize)]
#[serde(crate = "near_sdk::serde")]
pub struct SlippageHistory {
    pub timestamp: U64,
    pub slippage: u64,
    pub volatility_score: u64,
    pub cross_chain_delay: u64,  // Expected bridge delay in seconds
}

#[derive(BorshDeserialize, BorshSerialize, Serialize, Deserialize)]
#[serde(crate = "near_sdk::serde")]
pub struct BridgeMessage {
    pub order_id: u64,
    pub target_contract: String,  // Ethereum contract address
    pub action: String,          // "create_order", "claim", "cancel"
    pub data: String,           // Encoded message data
}

#[near_bindgen]
#[derive(BorshDeserialize, BorshSerialize, PanicOnDefault)]
pub struct AdaptiveCrossChain {
    pub orders: UnorderedMap<u64, CrossChainOrder>,
    pub user_orders: LookupMap<AccountId, Vector<u64>>,
    pub hashlock_to_order: LookupMap<String, u64>,
    pub slippage_history: LookupMap<u64, Vector<SlippageHistory>>,
    pub next_order_id: u64,
    pub owner: AccountId,
    pub ethereum_contract: String,  // Ethereum contract address
    pub bridge_contract: AccountId, // Rainbow Bridge contract
    
    // Protocol parameters
    pub slippage_update_interval: U64,  // 5 minutes in nanoseconds
    pub max_slippage_change: u64,       // 100 basis points (1%)
    pub fill_attempt_limit: u64,        // 10 attempts
    pub default_timelock_duration: U64, // 24 hours in blocks
}

#[near_bindgen]
impl AdaptiveCrossChain {
    #[init]
    pub fn new(
        ethereum_contract: String,
        bridge_contract: AccountId,
    ) -> Self {
        Self {
            orders: UnorderedMap::new(b"o"),
            user_orders: LookupMap::new(b"u"),
            hashlock_to_order: LookupMap::new(b"h"),
            slippage_history: LookupMap::new(b"s"),
            next_order_id: 1,
            owner: env::predecessor_account_id(),
            ethereum_contract,
            bridge_contract,
            slippage_update_interval: U64(300_000_000_000), // 5 minutes
            max_slippage_change: 100,
            fill_attempt_limit: 10,
            default_timelock_duration: U64(17280), // ~24 hours (assuming 5s blocks)
        }
    }

    #[payable]
    pub fn create_cross_chain_order(
        &mut self,
        token_out: String,           // Ethereum token address
        base_price: U128,
        max_slippage_deviation: u64,
        target_chain_id: u64,
        secret: String,              // Secret for hashlock
    ) -> u64 {
        let deposit = env::attached_deposit();
        require!(deposit > 0, "Must attach NEAR tokens");
        
        let maker = env::predecessor_account_id();
        let order_id = self.next_order_id;
        self.next_order_id += 1;

        // Generate hashlock from secret
        let hashlock = self.generate_hashlock(&secret);
        
        // Calculate initial slippage based on cross-chain factors
        let initial_slippage = self.calculate_cross_chain_slippage(
            &"near".to_string(),
            &token_out,
            deposit,
            target_chain_id
        );

        let timelock = U64(env::block_height() + self.default_timelock_duration.0);

        let order = CrossChainOrder {
            order_id,
            maker: maker.clone(),
            token_in: "near".to_string(),
            token_out: token_out.clone(),
            amount_in: U128(deposit),
            base_price,
            current_slippage: initial_slippage,
            max_slippage_deviation,
            target_chain_id,
            hashlock: hashlock.clone(),
            timelock,
            secret: Some(secret),
            status: OrderStatus::Active,
            created_at: U64(env::block_timestamp()),
            last_slippage_update: U64(env::block_timestamp()),
            fill_attempts: 0,
        };

        // Store order
        self.orders.insert(&order_id, &order);
        self.hashlock_to_order.insert(&hashlock, &order_id);
        
        // Track user orders
        let mut user_order_list = self.user_orders
            .get(&maker)
            .unwrap_or_else(|| Vector::new(format!("u{}", maker).as_bytes()));
        user_order_list.push(&order_id);
        self.user_orders.insert(&maker, &user_order_list);

        // Record initial slippage
        let mut history = Vector::new(format!("s{}", order_id).as_bytes());
        history.push(&SlippageHistory {
            timestamp: U64(env::block_timestamp()),
            slippage: initial_slippage,
            volatility_score: 0,
            cross_chain_delay: 900, // 15 minutes typical bridge delay
        });
        self.slippage_history.insert(&order_id, &history);

        // Send message to Ethereum via bridge
        self.send_bridge_message(BridgeMessage {
            order_id,
            target_contract: self.ethereum_contract.clone(),
            action: "create_order".to_string(),
            data: serde_json::to_string(&order).unwrap(),
        });

        env::log_str(&format!(
            "Cross-chain order created: ID {}, Amount: {}, Target: {}", 
            order_id, deposit, token_out
        ));

        order_id
    }

    pub fn claim_with_secret(&mut self, hashlock: String, secret: String) -> Promise {
        // Verify secret matches hashlock
        let computed_hash = self.generate_hashlock(&secret);
        require!(computed_hash == hashlock, "Invalid secret");

        let order_id = self.hashlock_to_order.get(&hashlock)
            .expect("Order not found");
        
        let mut order = self.orders.get(&order_id).expect("Order not found");
        require!(
            matches!(order.status, OrderStatus::Locked),
            "Order not in locked state"
        );
        require!(
            env::block_height() < order.timelock.0,
            "Order expired"
        );

        // Update order status
        order.status = OrderStatus::Completed;
        self.orders.insert(&order_id, &order);

        // Transfer tokens to claimer
        Promise::new(env::predecessor_account_id())
            .transfer(order.amount_in.0)
    }

    pub fn update_order_slippage(&mut self, order_id: u64) {
        let mut order = self.orders.get(&order_id).expect("Order not found");
        require!(
            matches!(order.status, OrderStatus::Active),
            "Order not active"
        );
        require!(
            env::block_timestamp() >= order.last_slippage_update.0 + self.slippage_update_interval.0,
            "Too early to update"
        );

        // Calculate new slippage with cross-chain factors
        let new_slippage = self.calculate_cross_chain_slippage(
            &order.token_in,
            &order.token_out,
            order.amount_in.0,
            order.target_chain_id
        );

        // Apply maximum deviation limits
        let slippage_change = if new_slippage > order.current_slippage {
            new_slippage - order.current_slippage
        } else {
            order.current_slippage - new_slippage
        };

        let final_slippage = if slippage_change > order.max_slippage_deviation {
            if new_slippage > order.current_slippage {
                order.current_slippage + order.max_slippage_deviation
            } else {
                if order.current_slippage > order.max_slippage_deviation {
                    order.current_slippage - order.max_slippage_deviation
                } else {
                    0
                }
            }
        } else {
            new_slippage
        };

        // Update order
        let old_slippage = order.current_slippage;
        order.current_slippage = final_slippage;
        order.last_slippage_update = U64(env::block_timestamp());
        self.orders.insert(&order_id, &order);

        // Record slippage history
        if let Some(mut history) = self.slippage_history.get(&order_id) {
            history.push(&SlippageHistory {
                timestamp: U64(env::block_timestamp()),
                slippage: final_slippage,
                volatility_score: self.calculate_volatility_score(&order.token_out),
                cross_chain_delay: self.estimate_bridge_delay(order.target_chain_id),
            });
            self.slippage_history.insert(&order_id, &history);
        }

        // Notify Ethereum contract of slippage update
        self.send_bridge_message(BridgeMessage {
            order_id,
            target_contract: self.ethereum_contract.clone(),
            action: "update_slippage".to_string(),
            data: format!("{{\"slippage\":{}}}", final_slippage),
        });

        env::log_str(&format!(
            "Slippage updated for order {}: {} -> {} basis points",
            order_id, old_slippage, final_slippage
        ));
    }

    // Helper functions
    fn generate_hashlock(&self, secret: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(secret.as_bytes());
        hex::encode(hasher.finalize())
    }

    fn calculate_cross_chain_slippage(
        &self,
        token_in: &str,
        token_out: &str,
        amount: Balance,
        target_chain_id: u64,
    ) -> u64 {
        // Base slippage calculation
        let mut base_slippage = 50; // 0.5% base

        // Cross-chain risk premium
        let cross_chain_premium = match target_chain_id {
            1 => 25,   // Ethereum mainnet: +0.25%
            137 => 50, // Polygon: +0.5%
            _ => 100,  // Other chains: +1%
        };

        // Bridge delay adjustment
        let bridge_delay_premium = 25; // +0.25% for bridge timing risk

        // Amount-based adjustment
        let amount_adjustment = if amount > 1000_000_000_000_000_000_000_000 { // > 1000 NEAR
            50 // +0.5% for large orders
        } else {
            0
        };

        base_slippage + cross_chain_premium + bridge_delay_premium + amount_adjustment
    }

    fn calculate_volatility_score(&self, _token: &str) -> u64 {
        // Simplified volatility calculation
        // In production, this would use price oracles
        100 // Default volatility score
    }

    fn estimate_bridge_delay(&self, target_chain_id: u64) -> u64 {
        match target_chain_id {
            1 => 900,   // Ethereum: 15 minutes
            137 => 300, // Polygon: 5 minutes  
            _ => 1800,  // Other chains: 30 minutes
        }
    }

    fn send_bridge_message(&self, message: BridgeMessage) {
        // Send cross-chain message via Rainbow Bridge
        // This would integrate with the actual bridge protocol
        env::log_str(&format!(
            "Bridge message sent: {} for order {}",
            message.action, message.order_id
        ));
    }

    // View functions
    pub fn get_order(&self, order_id: u64) -> Option<CrossChainOrder> {
        self.orders.get(&order_id)
    }

    pub fn get_user_orders(&self, user: AccountId) -> Vec<u64> {
        self.user_orders
            .get(&user)
            .map(|orders| orders.to_vec())
            .unwrap_or_default()
    }

    pub fn get_order_count(&self) -> u64 {
        self.next_order_id - 1
    }
}

// Helper macro for requiring conditions
macro_rules! require {
    ($cond:expr, $msg:expr) => {
        if !$cond {
            env::panic_str($msg);
        }
    };
} 