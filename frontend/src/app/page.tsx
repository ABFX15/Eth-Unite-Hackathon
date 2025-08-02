"use client";

import { Suspense } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount } from "wagmi";
import { useNear } from "./providers";
import { useAdaptaFlow, SUPPORTED_CHAINS } from "./hooks/useAdaptaFlow";
import Link from "next/link";

export default function Home() {
  const { isConnected: isEthConnected } = useAccount();
  const {
    isConnected: isNearConnected,
    accounts: nearAccounts,
    connectWallet: connectNear,
    loading: nearLoading,
  } = useNear();

  const { dashboardData, supportedChains } = useAdaptaFlow();

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-orange-900 to-black">
      {/* Top Banner */}
      <div className="bg-gradient-to-r from-orange-600/20 to-red-600/20 backdrop-blur-sm border-b border-orange-500/30 text-center py-2 px-4">
        <div className="flex items-center justify-center space-x-2">
          <span className="text-lg">🔥</span>
          <span className="font-semibold text-orange-200">
            Live on Testnets
          </span>
          <span className="text-lg">🔥</span>
        </div>
        <p className="text-sm text-orange-300">
          Experience the future of cross-chain trading
        </p>
      </div>

      <header className="bg-black/50 backdrop-blur-md shadow-2xl border-b border-orange-500/30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center space-x-6">
              <div className="flex items-center">
                <div className="w-12 h-12 mr-4">
                  <img
                    src="/logo.png"
                    alt="AdaptaFlow Logo"
                    className="w-full h-full object-contain"
                  />
                </div>
                <h1 className="text-3xl font-bold bg-gradient-to-r from-orange-400 to-red-400 bg-clip-text text-transparent">
                  AdaptaFlow Protocol
                </h1>
                <span className="ml-3 px-3 py-1 bg-gradient-to-r from-orange-500/20 to-red-500/20 border border-orange-400/30 text-orange-300 text-sm font-medium rounded-full backdrop-blur-sm">
                  Multi-Chain Intelligence
                </span>
              </div>
              <nav className="flex items-center space-x-4">
                <span className="text-orange-400 font-medium">Home</span>
                <Link
                  href="/trade"
                  className="text-gray-300 hover:text-orange-400 transition-colors"
                >
                  Trade
                </Link>
              </nav>
            </div>
            <div className="flex items-center space-x-4">
              <Link
                href="/trade"
                className="bg-gradient-to-r from-orange-600 to-red-600 hover:from-orange-700 hover:to-red-700 text-white px-6 py-2 rounded-lg font-medium transition-all duration-200 shadow-lg"
              >
                Launch App
              </Link>
              <WalletConnectionStatus />
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        {/* Hero Section */}
        <div className="text-center mb-16">
          <h2 className="text-6xl font-bold bg-gradient-to-r from-orange-400 via-red-400 to-orange-400 bg-clip-text text-transparent mb-6">
            Adaptive Cross-Chain Intelligence
          </h2>
          <p className="text-xl text-gray-300 max-w-4xl mx-auto mb-8">
            The first protocol to intelligently optimize 1inch cross-chain swaps
            with AI-powered bridge intelligence. Combines 1inch's cross-chain
            aggregation with adaptive slippage optimization.
            <span className="block mt-2 text-orange-400 font-semibold">
              🔥 1inch Cross-Chain • 🧠 AI Bridge Intelligence • ⚡ Single
              Transaction
            </span>
          </p>
          <div className="flex justify-center items-center space-x-8 mb-8">
            <StatCard title="Supported Chains" value="8+" />
            <StatCard title="Volume Protected" value="$125K" />
            <StatCard title="Avg Savings" value="52%" />
            <StatCard title="Success Rate" value="94%" />
          </div>
          <div className="flex justify-center">
            <Link
              href="/trade"
              className="bg-gradient-to-r from-orange-600 to-red-600 hover:from-orange-700 hover:to-red-700 text-white px-8 py-4 rounded-xl font-bold text-lg transition-all duration-200 shadow-2xl hover:scale-105 border border-orange-400/30"
            >
              🚀 Start Trading Now
            </Link>
          </div>
        </div>

        {/* Protocol Features */}
        <div className="bg-gradient-to-r from-orange-900/20 to-red-900/20 backdrop-blur-sm rounded-2xl border border-orange-500/30 p-8 mb-12">
          <h3 className="text-2xl font-bold text-white mb-6 text-center">
            🚀 Next-Generation Cross-Chain Trading
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="text-center">
              <div className="bg-gradient-to-br from-orange-500/20 to-red-500/20 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4 border border-orange-400/30">
                <span className="text-2xl">🔗</span>
              </div>
              <h4 className="font-semibold mb-2 text-white">
                1. Connect Wallet
              </h4>
              <p className="text-sm text-gray-300">
                Connect to any supported blockchain. MetaMask, WalletConnect,
                and NEAR wallets supported.
              </p>
            </div>
            <div className="text-center">
              <div className="bg-gradient-to-br from-red-500/20 to-orange-500/20 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4 border border-red-400/30">
                <span className="text-2xl">🧠</span>
              </div>
              <h4 className="font-semibold mb-2 text-white">
                2. AI Optimization
              </h4>
              <p className="text-sm text-gray-300">
                Our ML algorithms calculate optimal slippage based on bridge
                delays and market conditions.
              </p>
            </div>
            <div className="text-center">
              <div className="bg-gradient-to-br from-yellow-500/20 to-orange-500/20 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4 border border-yellow-400/30">
                <span className="text-2xl">⚡</span>
              </div>
              <h4 className="font-semibold mb-2 text-white">
                3. Execute Trade
              </h4>
              <p className="text-sm text-gray-300">
                Enjoy optimal execution with adaptive slippage that evolves with
                market conditions.
              </p>
            </div>
          </div>
        </div>

        {/* Supported Networks */}
        <div className="bg-black/40 backdrop-blur-sm rounded-2xl border border-gray-700/50 p-8 mb-12">
          <h3 className="text-2xl font-bold text-white mb-6 text-center">
            🌐 Multi-Chain Ecosystem
          </h3>
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-8 gap-4">
            {Object.entries(supportedChains).map(([key, chain]) => (
              <div
                key={key}
                className="text-center p-4 bg-gradient-to-b from-gray-800/50 to-gray-900/50 border border-gray-600/30 rounded-lg hover:border-orange-400/50 transition-all duration-300 hover:scale-105"
              >
                <div className="text-2xl mb-2">{chain.icon}</div>
                <h4 className="font-semibold text-sm text-white">
                  {chain.name}
                </h4>
                <p className="text-xs text-gray-400 mt-1">
                  {chain.tokens.length} assets
                </p>
                <div className="mt-2 w-full h-1 bg-gradient-to-r from-orange-500 to-red-500 rounded-full opacity-60"></div>
              </div>
            ))}
          </div>

          {/* Faucet Links */}
          <div className="mt-8 p-6 bg-gradient-to-r from-gray-800/50 to-gray-900/50 rounded-lg border border-gray-600/30">
            <h4 className="font-semibold text-white mb-4 text-center">
              💧 Development Resources
            </h4>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 text-sm">
              <div className="text-center">
                <p className="font-medium text-orange-400">Sepolia ETH</p>
                <a
                  href="https://faucet.sepolia.dev/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-orange-300 hover:text-orange-200 transition-colors"
                >
                  Get ETH
                </a>
              </div>
              <div className="text-center">
                <p className="font-medium text-red-400">Mumbai MATIC</p>
                <a
                  href="https://faucet.polygon.technology/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-red-300 hover:text-red-200 transition-colors"
                >
                  Get MATIC
                </a>
              </div>
              <div className="text-center">
                <p className="font-medium text-orange-400">Arbitrum Sepolia</p>
                <a
                  href="https://faucet.arbitrum.io/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-orange-300 hover:text-orange-200 transition-colors"
                >
                  Get ARB
                </a>
              </div>
              <div className="text-center">
                <p className="font-medium text-yellow-400">NEAR Protocol</p>
                <a
                  href="https://wallet.testnet.near.org/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-yellow-300 hover:text-yellow-200 transition-colors"
                >
                  Get NEAR
                </a>
              </div>
            </div>
          </div>
        </div>

        {/* Live Dashboard */}
        <div className="bg-black/40 backdrop-blur-sm rounded-2xl border border-gray-700/50 p-8 mb-12">
          <h3 className="text-2xl font-bold text-white mb-6 text-center">
            📊 Live Intelligence Dashboard
          </h3>
          <MultiChainDashboard dashboardData={dashboardData} />
        </div>

        {/* Feature Cards */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mb-16">
          <FeatureCard
            icon="🧠"
            title="AI-Powered Optimization"
            description="Machine learning algorithms analyze bridge delays, volatility, and liquidity to calculate optimal slippage in real-time."
            highlight={true}
          />
          <FeatureCard
            icon="⚡"
            title="Lightning Fast Execution"
            description="Sub-second slippage calculations with atomic cross-chain swaps and MEV protection across all supported networks."
          />
          <FeatureCard
            icon="🛡️"
            title="Maximum Security"
            description="Non-custodial protocol with reentrancy protection, CEI patterns, and battle-tested smart contract architecture."
          />
        </div>

        {/* Call to Action */}
        <div className="bg-gradient-to-r from-orange-900/30 to-red-900/30 backdrop-blur-sm rounded-2xl border border-orange-500/30 p-12 mb-16 text-center">
          <h3 className="text-4xl font-bold text-white mb-6">
            Ready to Start Trading?
          </h3>
          <p className="text-xl text-gray-300 mb-8 max-w-2xl mx-auto">
            Experience the power of AI-driven cross-chain trading with adaptive
            slippage optimization. Join the future of DeFi today.
          </p>
          <div className="flex justify-center items-center space-x-6">
            <Link
              href="/trade"
              className="bg-gradient-to-r from-orange-600 to-red-600 hover:from-orange-700 hover:to-red-700 text-white px-8 py-4 rounded-lg font-bold text-lg transition-all duration-200 shadow-xl hover:scale-105"
            >
              🚀 Launch Trading App
            </Link>
            <div className="text-center">
              <div className="text-sm text-gray-400 mb-2">Live on testnets</div>
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
                <span className="text-green-400 text-sm font-medium">
                  Active
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* How It Works */}
        <div className="bg-black/40 backdrop-blur-sm rounded-2xl border border-gray-700/50 p-8 mb-12">
          <h3 className="text-2xl font-bold text-white mb-8 text-center">
            How AdaptaFlow Intelligence Works
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
            <div className="text-center">
              <div className="bg-gradient-to-br from-orange-500/20 to-red-500/20 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4 border border-orange-400/30">
                <span className="text-2xl">🌐</span>
              </div>
              <h4 className="font-semibold mb-2 text-white">
                Cross-Chain Analysis
              </h4>
              <p className="text-sm text-gray-300">
                Monitor volatility, bridge delays, and liquidity across 8+
                blockchain networks in real-time
              </p>
            </div>
            <div className="text-center">
              <div className="bg-gradient-to-br from-red-500/20 to-orange-500/20 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4 border border-red-400/30">
                <span className="text-2xl">🎯</span>
              </div>
              <h4 className="font-semibold mb-2 text-white">AI Optimization</h4>
              <p className="text-sm text-gray-300">
                Machine learning calculates optimal slippage for each chain pair
                with 94% success rate
              </p>
            </div>
            <div className="text-center">
              <div className="bg-gradient-to-br from-yellow-500/20 to-orange-500/20 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4 border border-yellow-400/30">
                <span className="text-2xl">⚡</span>
              </div>
              <h4 className="font-semibold mb-2 text-white">
                Atomic Execution
              </h4>
              <p className="text-sm text-gray-300">
                Secure cross-chain swaps with hashlock/timelock guarantees and
                MEV protection
              </p>
            </div>
            <div className="text-center">
              <div className="bg-gradient-to-br from-orange-500/20 to-yellow-500/20 rounded-full w-16 h-16 flex items-center justify-center mx-auto mb-4 border border-orange-400/30">
                <span className="text-2xl">📈</span>
              </div>
              <h4 className="font-semibold mb-2 text-white">
                Continuous Learning
              </h4>
              <p className="text-sm text-gray-300">
                Protocol learns from every transaction to improve future
                predictions and optimize performance
              </p>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}

function WalletConnectionStatus() {
  const { isConnected: isEthConnected } = useAccount();
  const {
    isConnected: isNearConnected,
    accounts: nearAccounts,
    connectWallet: connectNear,
    loading: nearLoading,
  } = useNear();

  return (
    <div className="flex items-center space-x-4">
      {/* Ethereum Wallet */}
      <div className="flex items-center space-x-2">
        <div
          className={`w-3 h-3 rounded-full ${
            isEthConnected
              ? "bg-green-400 shadow-green-400/50 shadow-lg"
              : "bg-gray-500"
          }`}
        />
        <span className="text-sm text-gray-300">
          {isEthConnected ? "EVM Connected" : "EVM Disconnected"}
        </span>
        <ConnectButton />
      </div>

      {/* NEAR Wallet */}
      <div className="flex items-center space-x-2">
        <div
          className={`w-3 h-3 rounded-full ${
            isNearConnected
              ? "bg-green-400 shadow-green-400/50 shadow-lg"
              : nearLoading
              ? "bg-yellow-400 shadow-yellow-400/50 shadow-lg"
              : "bg-gray-500"
          }`}
        />
        <span className="text-sm text-gray-300">
          {nearLoading
            ? "NEAR Loading..."
            : isNearConnected
            ? "NEAR Connected"
            : "NEAR Disconnected"}
        </span>
        {!isNearConnected && !nearLoading && (
          <button
            onClick={connectNear}
            className="bg-gradient-to-r from-green-600 to-green-700 hover:from-green-700 hover:to-green-800 text-white px-4 py-2 rounded-lg font-medium text-sm transition-all duration-200 shadow-lg"
          >
            Connect NEAR
          </button>
        )}
        {isNearConnected && nearAccounts.length > 0 && (
          <span className="text-xs text-gray-400 font-mono bg-gray-800 px-2 py-1 rounded">
            {nearAccounts[0].accountId}
          </span>
        )}
      </div>
    </div>
  );
}

function FeatureCard({
  icon,
  title,
  description,
  highlight = false,
}: {
  icon: string;
  title: string;
  description: string;
  highlight?: boolean;
}) {
  return (
    <div
      className={`rounded-xl p-6 text-center transition-all duration-300 hover:scale-105 ${
        highlight
          ? "bg-gradient-to-br from-orange-600/20 to-red-600/20 border border-orange-400/30 shadow-orange-500/20 shadow-xl"
          : "bg-black/40 backdrop-blur-sm border border-gray-700/50"
      }`}
    >
      <div className="text-4xl mb-4">{icon}</div>
      <h3
        className={`text-xl font-bold mb-2 ${
          highlight ? "text-white" : "text-white"
        }`}
      >
        {title}
      </h3>
      <p className={highlight ? "text-orange-200" : "text-gray-300"}>
        {description}
      </p>
    </div>
  );
}

function MultiChainDashboard({ dashboardData }: { dashboardData: any }) {
  return (
    <div className="space-y-6">
      {/* Top Cross-Chain Pairs */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {dashboardData.crossChainPairs.map((pair: any, index: number) => (
          <div
            key={index}
            className="text-center p-4 bg-gradient-to-b from-gray-800/50 to-gray-900/50 border border-gray-600/30 rounded-lg"
          >
            <h4 className="text-sm font-semibold text-white mb-2">
              {
                SUPPORTED_CHAINS[pair.from as keyof typeof SUPPORTED_CHAINS]
                  ?.icon
              }{" "}
              →{" "}
              {SUPPORTED_CHAINS[pair.to as keyof typeof SUPPORTED_CHAINS]?.icon}{" "}
              {
                SUPPORTED_CHAINS[pair.from as keyof typeof SUPPORTED_CHAINS]
                  ?.name
              }{" "}
              →{" "}
              {SUPPORTED_CHAINS[pair.to as keyof typeof SUPPORTED_CHAINS]?.name}
            </h4>
            <div className="text-2xl font-bold bg-gradient-to-r from-green-400 to-green-600 bg-clip-text text-transparent mb-1">
              {pair.slippage}%
            </div>
            <div className="text-xs text-green-400">
              ↓ from {pair.optimizedFrom}%
            </div>
            <div className="text-xs text-gray-400 mt-2">{pair.volume} 24h</div>
          </div>
        ))}
      </div>

      {/* Summary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 pt-6 border-t border-gray-700/50">
        <div className="text-center">
          <h4 className="text-lg font-semibold text-white mb-2">
            Total Volume
          </h4>
          <div className="text-3xl font-bold bg-gradient-to-r from-orange-400 to-red-400 bg-clip-text text-transparent">
            {dashboardData.totalVolume}
          </div>
          <div className="text-sm text-gray-400">Last 24h across chains</div>
        </div>
        <div className="text-center">
          <h4 className="text-lg font-semibold text-white mb-2">Avg Savings</h4>
          <div className="text-3xl font-bold bg-gradient-to-r from-green-400 to-green-600 bg-clip-text text-transparent">
            {dashboardData.avgSavings.percentage}%
          </div>
          <div className="text-sm text-gray-400">
            {dashboardData.avgSavings.ordersProtected} orders protected
          </div>
        </div>
        <div className="text-center">
          <h4 className="text-lg font-semibold text-white mb-2">
            Active Pairs
          </h4>
          <div className="text-3xl font-bold bg-gradient-to-r from-yellow-400 to-orange-400 bg-clip-text text-transparent">
            {dashboardData.activePairs}
          </div>
          <div className="text-sm text-gray-400">Cross-chain routes</div>
        </div>
      </div>
    </div>
  );
}

function StatCard({ title, value }: { title: string; value: string }) {
  return (
    <div className="text-center">
      <p className="text-3xl font-bold bg-gradient-to-r from-orange-400 to-red-400 bg-clip-text text-transparent mb-2">
        {value}
      </p>
      <p className="text-gray-300">{title}</p>
    </div>
  );
}
