#!/bin/bash
set -e

echo "Building NEAR Adaptive Cross-Chain Contract..."

# Clean previous builds
rm -rf target/

# Build the contract
cargo build --target wasm32-unknown-unknown --release

# Copy the wasm file to a convenient location
mkdir -p res/
cp target/wasm32-unknown-unknown/release/adaptive_cross_chain.wasm res/

echo "✅ Contract built successfully!"
echo "📁 Contract location: res/adaptive_cross_chain.wasm"
echo "📊 Contract size: $(ls -lh res/adaptive_cross_chain.wasm | awk '{print $5}')"

# Optional: Check contract size (should be under 4MB for NEAR)
SIZE=$(stat -f%z res/adaptive_cross_chain.wasm 2>/dev/null || stat -c%s res/adaptive_cross_chain.wasm)
if [ $SIZE -gt 4194304 ]; then
    echo "⚠️  Warning: Contract size ($SIZE bytes) exceeds 4MB limit"
else
    echo "✅ Contract size is within limits"
fi 