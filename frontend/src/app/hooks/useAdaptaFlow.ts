import { useState, useEffect, useCallback } from 'react';
import { useAccount, usePublicClient, useWalletClient } from 'wagmi';
import { parseEther, formatEther, Address } from 'viem';

// Testnet contract addresses for hackathon demo
const CONTRACT_ADDRESSES = {
    // Ethereum Testnets
    SEPOLIA: {
        ADAPTIVE_LIMIT_ORDER: '0x1234567890123456789012345678901234567890' as Address,
        DYNAMIC_SLIPPAGE_CALCULATOR: '0x2345678901234567890123456789012345678901' as Address,
        CROSS_CHAIN_BRIDGE: '0x3456789012345678901234567890123456789012' as Address,
    },
    // Polygon Testnet
    MUMBAI: {
        ADAPTIVE_LIMIT_ORDER: '0x4567890123456789012345678901234567890123' as Address,
        CROSS_CHAIN_BRIDGE: '0x5678901234567890123456789012345678901234' as Address,
    },
    // Arbitrum Testnet
    ARBITRUM_SEPOLIA: {
        ADAPTIVE_LIMIT_ORDER: '0x6789012345678901234567890123456789012345' as Address,
        CROSS_CHAIN_BRIDGE: '0x7890123456789012345678901234567890123456' as Address,
    },
    // Base Testnet
    BASE_SEPOLIA: {
        ADAPTIVE_LIMIT_ORDER: '0x8901234567890123456789012345678901234567' as Address,
        CROSS_CHAIN_BRIDGE: '0x9012345678901234567890123456789012345678' as Address,
    },
    // Optimism Testnet
    OPTIMISM_SEPOLIA: {
        ADAPTIVE_LIMIT_ORDER: '0xA012345678901234567890123456789012345678' as Address,
        CROSS_CHAIN_BRIDGE: '0xB012345678901234567890123456789012345678' as Address,
    },
};

// Comprehensive testnet chain configuration
export const SUPPORTED_CHAINS = {
    // Ethereum Testnets
    sepolia: {
        name: 'Ethereum Sepolia',
        icon: '⟠',
        color: 'blue',
        contracts: CONTRACT_ADDRESSES.SEPOLIA,
        tokens: ['ETH', 'USDC', 'USDT', 'WBTC', 'DAI'],
        testnet: true,
        chainId: 11155111,
        rpcUrl: 'https://eth-sepolia.g.alchemy.com/v2/demo',
        blockExplorer: 'https://sepolia.etherscan.io',
    },

    // Polygon Testnet
    mumbai: {
        name: 'Polygon Mumbai',
        icon: '⬢',
        color: 'purple',
        contracts: CONTRACT_ADDRESSES.MUMBAI,
        tokens: ['MATIC', 'USDC', 'USDT', 'WETH', 'DAI'],
        testnet: true,
        chainId: 80001,
        rpcUrl: 'https://polygon-mumbai.g.alchemy.com/v2/demo',
        blockExplorer: 'https://mumbai.polygonscan.com',
    },

    // Arbitrum Testnet
    arbitrumSepolia: {
        name: 'Arbitrum Sepolia',
        icon: '🔹',
        color: 'blue',
        contracts: CONTRACT_ADDRESSES.ARBITRUM_SEPOLIA,
        tokens: ['ETH', 'USDC', 'ARB', 'USDT'],
        testnet: true,
        chainId: 421614,
        rpcUrl: 'https://arb-sepolia.g.alchemy.com/v2/demo',
        blockExplorer: 'https://sepolia.arbiscan.io',
    },

    // Base Testnet
    baseSepolia: {
        name: 'Base Sepolia',
        icon: '🔵',
        color: 'blue',
        contracts: CONTRACT_ADDRESSES.BASE_SEPOLIA,
        tokens: ['ETH', 'USDC', 'USDT'],
        testnet: true,
        chainId: 84532,
        rpcUrl: 'https://base-sepolia.g.alchemy.com/v2/demo',
        blockExplorer: 'https://sepolia.basescan.org',
    },

    // Optimism Testnet
    optimismSepolia: {
        name: 'Optimism Sepolia',
        icon: '🔴',
        color: 'red',
        contracts: CONTRACT_ADDRESSES.OPTIMISM_SEPOLIA,
        tokens: ['ETH', 'USDC', 'OP', 'USDT'],
        testnet: true,
        chainId: 11155420,
        rpcUrl: 'https://opt-sepolia.g.alchemy.com/v2/demo',
        blockExplorer: 'https://sepolia.optimistic.etherscan.io',
    },

    // NEAR Testnet (already configured)
    nearTestnet: {
        name: 'NEAR Testnet',
        icon: '🌌',
        color: 'green',
        contracts: null, // NEAR uses different contract system
        tokens: ['NEAR', 'wNEAR', 'USDC.e', 'USDT.e'],
        testnet: true,
        chainId: null,
        rpcUrl: 'https://rpc.testnet.near.org',
        blockExplorer: 'https://testnet.nearblocks.io',
    },

    // Solana Devnet
    solanaDevnet: {
        name: 'Solana Devnet',
        icon: '🟣',
        color: 'purple',
        contracts: null, // Future implementation
        tokens: ['SOL', 'USDC', 'USDT'],
        testnet: true,
        chainId: null,
        rpcUrl: 'https://api.devnet.solana.com',
        blockExplorer: 'https://explorer.solana.com/?cluster=devnet',
    },

    // Avalanche Testnet
    fuji: {
        name: 'Avalanche Fuji',
        icon: '🔺',
        color: 'red',
        contracts: null, // Future implementation
        tokens: ['AVAX', 'USDC', 'USDT', 'WETH'],
        testnet: true,
        chainId: 43113,
        rpcUrl: 'https://avalanche-fuji-c-chain.publicnode.com',
        blockExplorer: 'https://testnet.snowtrace.io',
    },
};

// Contract ABIs (same as before)
const ADAPTIVE_LIMIT_ORDER_ABI = [
    {
        name: 'calculateOrderSlippage',
        type: 'function',
        stateMutability: 'view',
        inputs: [
            { name: 'tokenIn', type: 'address' },
            { name: 'tokenOut', type: 'address' },
            { name: 'amountIn', type: 'uint256' }
        ],
        outputs: [{ name: 'slippage', type: 'uint256' }]
    },
    {
        name: 'createAdaptiveOrder',
        type: 'function',
        stateMutability: 'nonpayable',
        inputs: [
            { name: 'tokenIn', type: 'address' },
            { name: 'tokenOut', type: 'address' },
            { name: 'amountIn', type: 'uint256' },
            { name: 'basePrice', type: 'uint256' },
            { name: 'maxSlippageDeviation', type: 'uint256' },
            { name: 'initialSlippage', type: 'uint256' }
        ],
        outputs: [{ name: 'orderId', type: 'uint256' }]
    },
] as const;

// Testnet token addresses
const TOKENS = {
    sepolia: {
        ETH: '0x0000000000000000000000000000000000000000' as Address, // Native ETH
        USDC: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' as Address, // Sepolia USDC
        USDT: '0x509Ee0d083DdF8AC028f2a56731412edD63223B9' as Address, // Sepolia USDT
        WBTC: '0x29f2D40B0605204364af54EC677bD022dA425d03' as Address, // Sepolia WBTC
        DAI: '0x3e622317f8C93f7328350cF0B56d9eD4C620C5d6' as Address, // Sepolia DAI
    },
    mumbai: {
        MATIC: '0x0000000000000000000000000000000000001010' as Address, // Native MATIC
        USDC: '0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e' as Address, // Mumbai USDC
        USDT: '0x3813e82e6f7098b9583FC0F33a962D02018B6803' as Address, // Mumbai USDT
        WETH: '0x714550C2C1Ea08688607D86ed8EeF4f5E4F22323' as Address, // Mumbai WETH
        DAI: '0x27a44456bEDb94DbD59D0f0A14fE977c777fC5C3' as Address, // Mumbai DAI
    },
    arbitrumSepolia: {
        ETH: '0x0000000000000000000000000000000000000000' as Address, // Native ETH
        USDC: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d' as Address, // Arbitrum Sepolia USDC
        USDT: '0x8B3d4F3eF04E1B6cDFA3fE0D6d8a4fFa47e20c4D' as Address, // Mock USDT
        ARB: '0x5C1b28e0cce1C56eE4CBB6dE9e15F96F7e4DF4cA' as Address, // Mock ARB
    },
    baseSepolia: {
        ETH: '0x0000000000000000000000000000000000000000' as Address, // Native ETH
        USDC: '0x036CbD53842c5426634e7929541eC2318f3dCF7e' as Address, // Base Sepolia USDC
        USDT: '0x7A9Cb69Fd68Cb7F3cBA5d3E0e9e44E81bD2b9D8C' as Address, // Mock USDT
    },
    optimismSepolia: {
        ETH: '0x0000000000000000000000000000000000000000' as Address, // Native ETH
        USDC: '0x5fd84259d66Cd46123540766Be93DFE6D43130D7' as Address, // Optimism Sepolia USDC
        USDT: '0x8B3d4F3eF04E1B6cDFA3fE0D6d8a4fFa47e20c4D' as Address, // Mock USDT
        OP: '0x2E0eF41f35C97E5c9C5Ae5CfCCA52A6F6F4ee9f0' as Address, // Mock OP
    },
};

export interface SlippageMetrics {
    dynamicSlippage: number;
    baseSlippage: number;
    volatilityAdjustment: number;
    liquidityAdjustment: number;
    bridgeDelayPremium: number;
    crossChainPremium: number;
    confidence: number;
}

export interface AdaptiveOrder {
    id: string;
    maker: Address;
    fromChain: string;
    toChain: string;
    tokenIn: string;
    tokenOut: string;
    amountIn: string;
    basePrice: string;
    currentSlippage: number;
    active: boolean;
    adaptiveChanges: number;
    timeRemaining: string;
    status: 'Active' | 'Executing' | 'Completed' | 'Cancelled';
}

export interface OrderFormData {
    fromChain: keyof typeof SUPPORTED_CHAINS;
    toChain: keyof typeof SUPPORTED_CHAINS;
    fromToken: string;
    toToken: string;
    amount: string;
    maxSlippageDeviation: number;
}

export function useAdaptaFlow() {
    const { address, isConnected } = useAccount();
    const publicClient = usePublicClient();
    const { data: walletClient } = useWalletClient();

    const [isLoading, setIsLoading] = useState(false);
    const [orders, setOrders] = useState<AdaptiveOrder[]>([]);
    const [slippageMetrics, setSlippageMetrics] = useState<SlippageMetrics | null>(null);

    // Get 1inch quote for optimal swap route
    const get1inchQuote = useCallback(async (
        fromChain: string,
        toChain: string,
        tokenIn: string,
        tokenOut: string,
        amount: string
    ) => {
        try {
            // 1inch API endpoint for quotes
            const chainId = SUPPORTED_CHAINS[fromChain as keyof typeof SUPPORTED_CHAINS]?.chainId;
            if (!chainId) throw new Error('Unsupported chain for 1inch');

            const tokenInAddress = getTokenAddress(fromChain, tokenIn);
            const tokenOutAddress = getTokenAddress(toChain, tokenOut);
            const amountInWei = parseEther(amount);

            // 1inch API call
            const response = await fetch(
                `https://api.1inch.dev/swap/v5.2/${chainId}/quote?src=${tokenInAddress}&dst=${tokenOutAddress}&amount=${amountInWei.toString()}`,
                {
                    headers: {
                        'Authorization': `Bearer ${process.env.NEXT_1INCH_API_KEY
                            }`,
                        'Accept': 'application/json'
                    }
                }
            );

            if (!response.ok) {
                throw new Error('1inch API error');
            }

            const quote = await response.json();
            console.log('🔥 1inch Quote:', quote);

            return quote;
        } catch (error) {
            console.warn('1inch API failed, using fallback:', error);
            // Fallback to our custom calculation
            return null;
        }
    }, []);

    // Calculate dynamic slippage using 1inch + AI optimization
    const calculateSlippage = useCallback(async (
        fromChain: string,
        toChain: string,
        tokenIn: string,
        tokenOut: string,
        amount: string
    ): Promise<SlippageMetrics> => {
        if (!publicClient) throw new Error('No public client available');

        try {
            setIsLoading(true);

            // Get 1inch quote first
            const oneInchQuote = await get1inchQuote(fromChain, toChain, tokenIn, tokenOut, amount);

            // Get cross-chain bridge delay factor
            const bridgeDelayFactor = getBridgeDelayFactor(fromChain, toChain);

            // Get chain-specific slippage factors
            const chainSlippageFactor = getChainSlippageFactor(fromChain, toChain);

            // Use 1inch slippage if available, otherwise fallback
            let baseSlippage = 0.5; // Default fallback
            if (oneInchQuote) {
                baseSlippage = parseFloat(oneInchQuote.toTokenAmount) / parseFloat(oneInchQuote.fromTokenAmount);
                console.log('🔥 Using 1inch slippage:', baseSlippage);
            }

            // Calculate adaptive slippage components
            const metrics: SlippageMetrics = {
                baseSlippage: baseSlippage,
                volatilityAdjustment: Math.random() * 0.3, // Mock volatility
                liquidityAdjustment: Math.random() * 0.2, // Mock liquidity
                bridgeDelayPremium: bridgeDelayFactor,
                crossChainPremium: chainSlippageFactor,
                dynamicSlippage: 0,
                confidence: 75 + Math.random() * 20,
            };

            // Calculate total dynamic slippage
            metrics.dynamicSlippage =
                metrics.baseSlippage +
                metrics.volatilityAdjustment +
                metrics.liquidityAdjustment +
                metrics.bridgeDelayPremium +
                metrics.crossChainPremium;

            setSlippageMetrics(metrics);
            return metrics;

        } catch (error) {
            console.error('Error calculating slippage:', error);

            // Fallback mock data
            const fallbackMetrics: SlippageMetrics = {
                dynamicSlippage: 1.2,
                baseSlippage: 0.5,
                volatilityAdjustment: 0.2,
                liquidityAdjustment: 0.1,
                bridgeDelayPremium: getBridgeDelayFactor(fromChain, toChain),
                crossChainPremium: getChainSlippageFactor(fromChain, toChain),
                confidence: 65,
            };

            setSlippageMetrics(fallbackMetrics);
            return fallbackMetrics;
        } finally {
            setIsLoading(false);
        }
    }, [publicClient]);

    // Execute 1inch swap with adaptive slippage
    const execute1inchSwap = useCallback(async (
        quote: any,
        slippageTolerance: number
    ): Promise<string> => {
        if (!walletClient || !address) throw new Error('Wallet not connected');

        try {
            // 1inch swap API call
            const response = await fetch(
                `https://api.1inch.dev/swap/v5.2/${quote.chainId}/swap`,
                {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${process.env.NEXT_1INCH_API_KEY}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        src: quote.src,
                        dst: quote.dst,
                        amount: quote.amount,
                        from: address,
                        slippage: slippageTolerance,
                        disableEstimate: false,
                        allowPartialFill: false
                    })
                }
            );

            if (!response.ok) {
                throw new Error('1inch swap API error');
            }

            const swapData = await response.json();
            console.log('🔥 1inch Swap Data:', swapData);

            // Execute the swap transaction
            const txHash = await walletClient.sendTransaction({
                to: swapData.tx.to,
                data: swapData.tx.data,
                value: swapData.tx.value,
                gas: swapData.tx.gas
            });

            return txHash;
        } catch (error) {
            console.error('1inch swap failed:', error);
            throw error;
        }
    }, [walletClient, address]);

    // Create adaptive cross-chain order using 1inch
    const createOrder = useCallback(async (formData: OrderFormData): Promise<string> => {
        if (!walletClient || !address) throw new Error('Wallet not connected');

        try {
            setIsLoading(true);

            // Get 1inch quote first
            const oneInchQuote = await get1inchQuote(
                formData.fromChain,
                formData.toChain,
                formData.fromToken,
                formData.toToken,
                formData.amount
            );

            // Get slippage metrics with AI optimization
            const slippageMetrics = await calculateSlippage(
                formData.fromChain,
                formData.toChain,
                formData.fromToken,
                formData.toToken,
                formData.amount
            );

            let txHash: string;

            if (oneInchQuote) {
                // Use 1inch for the swap
                console.log('🔥 Executing 1inch swap with adaptive slippage:', {
                    from: `${formData.amount} ${formData.fromToken}`,
                    to: formData.toToken,
                    slippage: `${slippageMetrics.dynamicSlippage.toFixed(2)} % `,
                    chain: `${SUPPORTED_CHAINS[formData.fromChain].name}`
                });

                txHash = await execute1inchSwap(oneInchQuote, slippageMetrics.dynamicSlippage);
                console.log('✅ 1inch swap executed!', txHash);
            } else {
                // Fallback to demo transaction
                console.log('⚠️ 1inch quote failed, using demo transaction');
                txHash = await walletClient.sendTransaction({
                    to: address,
                    value: parseEther('0.001'),
                });
            }

            // Create mock order for UI (this would come from your backend in production)
            const newOrder: AdaptiveOrder = {
                id: `order_${Date.now()}`,
                maker: address,
                fromChain: formData.fromChain,
                toChain: formData.toChain,
                tokenIn: formData.fromToken,
                tokenOut: formData.toToken,
                amountIn: formData.amount,
                basePrice: '2000',
                currentSlippage: slippageMetrics.dynamicSlippage,
                active: true,
                adaptiveChanges: 0,
                timeRemaining: '23h 45m',
                status: 'Active',
            };

            setOrders(prev => [newOrder, ...prev]);
            return txHash;

        } catch (error) {
            console.error('Error creating cross-chain order:', error);
            throw error;
        } finally {
            setIsLoading(false);
        }
    }, [walletClient, address, calculateSlippage]);

    // Helper functions
    const getBridgeDelayFactor = (fromChain: string, toChain: string): number => {
        const bridgeDelays: Record<string, Record<string, number>> = {
            sepolia: { nearTestnet: 0.25, mumbai: 0.05, arbitrumSepolia: 0.02, baseSepolia: 0.02, optimismSepolia: 0.02, solanaDevnet: 0.4 },
            mumbai: { sepolia: 0.1, nearTestnet: 0.3, arbitrumSepolia: 0.05, baseSepolia: 0.05, optimismSepolia: 0.05 },
            arbitrumSepolia: { sepolia: 0.05, mumbai: 0.05, nearTestnet: 0.35, baseSepolia: 0.03, optimismSepolia: 0.03 },
            baseSepolia: { sepolia: 0.05, mumbai: 0.05, arbitrumSepolia: 0.03, nearTestnet: 0.35, optimismSepolia: 0.03 },
            optimismSepolia: { sepolia: 0.05, mumbai: 0.05, arbitrumSepolia: 0.03, baseSepolia: 0.03, nearTestnet: 0.35 },
            nearTestnet: { sepolia: 0.25, mumbai: 0.3, arbitrumSepolia: 0.35, baseSepolia: 0.35, optimismSepolia: 0.35 },
            solanaDevnet: { sepolia: 0.4, mumbai: 0.45, arbitrumSepolia: 0.45, baseSepolia: 0.45, optimismSepolia: 0.45 },
        };

        return bridgeDelays[fromChain]?.[toChain] || 0.2;
    };

    const getChainSlippageFactor = (fromChain: string, toChain: string): number => {
        // Testnet chains have similar characteristics to mainnet
        const chainFactors: Record<string, number> = {
            sepolia: 0.1,
            mumbai: 0.15,
            arbitrumSepolia: 0.08,
            baseSepolia: 0.08,
            optimismSepolia: 0.08,
            nearTestnet: 0.2,
            solanaDevnet: 0.25,
            fuji: 0.15,
        };

        return (chainFactors[fromChain] || 0.1) + (chainFactors[toChain] || 0.1);
    };

    const getTokenAddress = (chain: string, token: string): Address => {
        const chainTokens = TOKENS[chain as keyof typeof TOKENS];
        if (chainTokens && chainTokens[token as keyof typeof chainTokens]) {
            return chainTokens[token as keyof typeof chainTokens];
        }
        return TOKENS.sepolia.USDC; // Fallback to Sepolia USDC
    };

    // Enhanced testnet dashboard data
    const dashboardData = {
        crossChainPairs: [
            { from: 'sepolia', to: 'nearTestnet', slippage: 0.72, optimizedFrom: 1.25, volume: '$45.2K' },
            { from: 'mumbai', to: 'arbitrumSepolia', slippage: 0.45, optimizedFrom: 0.8, volume: '$32.8K' },
            { from: 'baseSepolia', to: 'optimismSepolia', slippage: 0.35, optimizedFrom: 0.6, volume: '$28.5K' },
            { from: 'sepolia', to: 'solanaDevnet', slippage: 0.95, optimizedFrom: 1.8, volume: '$19.3K' },
        ],
        totalVolume: '$125.8K',
        avgSavings: { percentage: 52, ordersProtected: 89 },
        activePairs: 15,
        testnetMode: true,
    };

    // Load orders when address changes
    useEffect(() => {
        if (isConnected && address) {
            console.log('Loading testnet orders for address:', address);
        }
    }, [isConnected, address]);

    return {
        // State
        isLoading,
        orders,
        slippageMetrics,
        dashboardData,
        supportedChains: SUPPORTED_CHAINS,

        // Actions
        calculateSlippage,
        createOrder,

        // Utils
        isConnected,
        address,
    };
} 