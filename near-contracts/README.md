# NEAR Cross-Chain Adaptive Orders

This directory contains the NEAR Protocol implementation for cross-chain adaptive slippage orders between NEAR and Ethereum.

## 🎯 Overview

The NEAR side of the cross-chain protocol enables:

- **Adaptive Slippage**: Dynamic slippage calculation for cross-chain swaps
- **Atomic Swaps**: Hashlock/timelock mechanics for secure cross-chain execution
- **Bridge Integration**: Seamless communication with Ethereum via Rainbow Bridge
- **MEV Protection**: Enhanced protection against cross-chain MEV attacks

## 🏗️ Architecture

```
NEAR Contract (Rust)                 Ethereum Contract (Solidity)
┌─────────────────┐                 ┌─────────────────────┐
│ Adaptive Cross  │◄────Bridge────►│ CrossChainBridge    │
│ Chain Orders    │                 │ + AdaptiveLimitOrder│
└─────────────────┘                 └─────────────────────┘
        │                                       │
        ▼                                       ▼
   NEAR Tokens                              ETH Tokens
```

## 🔧 Key Features

### Cross-Chain Slippage Calculation

- **Base slippage**: 0.5% starting point
- **Chain premium**: 0.25% (ETH) to 1% (other chains)
- **Bridge delay premium**: 0.25% for timing risk
- **Amount scaling**: +0.5% for orders >1000 NEAR

### Atomic Swap Security

- SHA256 hashlock verification
- Configurable timelock (default: 24 hours)
- Automatic refund on expiration
- Bridge message synchronization

### Cross-Chain Communication

- Rainbow Bridge integration
- Real-time slippage updates
- Order status synchronization
- Event-driven architecture

## 🚀 Quick Start

### Prerequisites

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Add WASM target
rustup target add wasm32-unknown-unknown

# Install NEAR CLI
npm install -g near-cli
```

### Build & Deploy

1. **Build the contract:**

```bash
./build.sh
```

2. **Deploy to testnet:**

```bash
# Configure your contract name and Ethereum address
vim deploy.sh  # Edit CONTRACT_NAME and ETHEREUM_CONTRACT

./deploy.sh
```

3. **Test deployment:**

```bash
near view adaptive-crosschain-dev get_order_count
```

## 📝 Usage Examples

### Create Cross-Chain Order (NEAR → ETH)

```bash
# Create order: Swap 100 NEAR for USDC on Ethereum
near call adaptive-crosschain-dev create_cross_chain_order \
'{
    "token_out": "0xA0b86a33E6417c22ccF7f61D9c5c3E8d2dF4e7C5",
    "base_price": "3000000000000000000000",
    "max_slippage_deviation": 500,
    "target_chain_id": 1,
    "secret": "my_secret_phrase_123"
}' \
--accountId your-account.testnet \
--amount 100
```

### Update Order Slippage

```bash
near call adaptive-crosschain-dev update_order_slippage \
'{"order_id": 1}' \
--accountId your-account.testnet
```

### Claim Order (ETH side provides secret)

```bash
near call adaptive-crosschain-dev claim_with_secret \
'{
    "hashlock": "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3",
    "secret": "my_secret_phrase_123"
}' \
--accountId claimer-account.testnet
```

## 🔍 Contract Interface

### Main Functions

#### `create_cross_chain_order`

Creates a new cross-chain order with adaptive slippage.

**Parameters:**

- `token_out`: Ethereum token address to receive
- `base_price`: Base exchange rate (18 decimals)
- `max_slippage_deviation`: Maximum slippage change (basis points)
- `target_chain_id`: Target blockchain (1 = Ethereum)
- `secret`: Secret phrase for hashlock

#### `update_order_slippage`

Updates order slippage based on current market conditions.

**Parameters:**

- `order_id`: ID of the order to update

#### `claim_with_secret`

Claims locked tokens by providing the secret.

**Parameters:**

- `hashlock`: Hash identifying the order
- `secret`: Secret phrase that matches the hashlock

### View Functions

#### `get_order`

Returns order details by ID.

#### `get_user_orders`

Returns list of order IDs for a user.

#### `get_order_count`

Returns total number of orders created.

## 🧪 Testing

### Unit Tests

```bash
cargo test
```

### Integration Tests

```bash
# Test order creation
near call $CONTRACT create_cross_chain_order '...' --accountId test.near --amount 10

# Test slippage update
near call $CONTRACT update_order_slippage '{"order_id": 1}' --accountId test.near

# View order status
near view $CONTRACT get_order '{"order_id": 1}'
```

## 🏆 1inch Fusion+ Hackathon Integration

This implementation is designed for the **1inch Cross-chain Swap (Fusion+)** track:

### ✅ Requirements Met

- [x] **Hashlock/Timelock**: SHA256 hashlock with configurable timelock
- [x] **Bidirectional Swaps**: NEAR ↔ ETH in both directions
- [x] **Onchain Execution**: Real token transfers on mainnet/testnet
- [x] **Non-EVM Implementation**: Pure Rust NEAR contract

### 🎯 Stretch Goals

- [x] **Partial Fills**: Configurable slippage allows partial execution
- [x] **Relayer**: Bridge messaging for automated execution
- [ ] **UI**: Frontend integration (see `/frontend` directory)

### 🚀 Competitive Advantages

1. **First Adaptive Slippage for Cross-Chain**: Dynamic slippage based on bridge delays and volatility
2. **MEV Protection**: Cross-chain MEV is more valuable - we protect against it
3. **User Experience**: "Set and forget" orders that adapt to market conditions
4. **Technical Innovation**: Novel slippage calculation incorporating cross-chain factors

## 🔧 Configuration

### Environment Variables

```bash
export CONTRACT_NAME="your-contract.testnet"
export ETHEREUM_CONTRACT="0x..." # Your Ethereum contract address
export BRIDGE_CONTRACT="factory.bridge.near"
```

### Contract Parameters

- `slippage_update_interval`: 5 minutes
- `max_slippage_change`: 100 basis points (1%)
- `fill_attempt_limit`: 10 retries
- `default_timelock_duration`: 24 hours

## 🔒 Security

### Audit Checklist

- [x] Reentrancy protection on token transfers
- [x] Timelock validation for expired orders
- [x] Hashlock verification with SHA256
- [x] Access control for bridge messages
- [x] Integer overflow protection (Rust built-in)

### Bridge Security

- Rainbow Bridge provides cryptographic proof of Ethereum state
- Multi-signature validation for cross-chain messages
- Configurable timelock for emergency stops

## 📚 Resources

- [NEAR Documentation](https://docs.near.org/)
- [Rainbow Bridge](https://rainbow.bridge.near.org/)
- [1inch Limit Order Protocol](https://github.com/1inch/limit-order-protocol)
- [Cross-Chain Bridge Security](https://blog.near.org/rainbow-bridge-architecture/)

## 🆘 Troubleshooting

### Common Issues

**Build Errors:**

```bash
# Clean and rebuild
rm -rf target/
cargo clean
./build.sh
```

**Deployment Failures:**

```bash
# Check account balance
near state your-account.testnet

# Verify contract size (<4MB)
ls -lh res/adaptive_cross_chain.wasm
```

**Cross-Chain Issues:**

```bash
# Check bridge status
near view factory.bridge.near get_bridge_token_factory_info

# Verify Ethereum contract deployment
# (Use your preferred Ethereum explorer)
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes (`cargo test`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.
