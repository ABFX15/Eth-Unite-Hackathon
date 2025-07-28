#!/bin/bash
set -e

# Configuration
CONTRACT_NAME="adaptive-crosschain-dev"
ETHEREUM_CONTRACT="0x..." # Replace with actual Ethereum contract address
BRIDGE_CONTRACT="factory.bridge.near" # Rainbow Bridge factory

echo "🚀 Deploying Adaptive Cross-Chain Contract to NEAR testnet..."

# Build the contract first
./build.sh

# Deploy to NEAR testnet
echo "📤 Deploying contract..."
near deploy \
    --accountId $CONTRACT_NAME \
    --wasmFile res/adaptive_cross_chain.wasm

# Initialize the contract
echo "🔧 Initializing contract..."
near call $CONTRACT_NAME new \
    '{
        "ethereum_contract": "'$ETHEREUM_CONTRACT'",
        "bridge_contract": "'$BRIDGE_CONTRACT'"
    }' \
    --accountId $CONTRACT_NAME

echo "✅ Contract deployed and initialized successfully!"
echo "📋 Contract Account: $CONTRACT_NAME"
echo "🔗 Ethereum Contract: $ETHEREUM_CONTRACT"
echo "🌉 Bridge Contract: $BRIDGE_CONTRACT"

# Test the deployment
echo "🧪 Testing deployment..."
near view $CONTRACT_NAME get_order_count

echo "🎉 Deployment complete! Your adaptive cross-chain contract is ready!"
echo ""
echo "Next steps:"
echo "1. Fund the contract account with NEAR tokens"
echo "2. Configure the Ethereum side with this contract address"
echo "3. Create your first cross-chain order!" 