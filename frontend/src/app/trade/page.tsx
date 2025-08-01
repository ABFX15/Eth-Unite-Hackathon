"use client";

import { Suspense, useState, useEffect } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount } from "wagmi";
import { useNear } from "../providers";
import {
  useAdaptaFlow,
  type OrderFormData,
  type SlippageMetrics,
  SUPPORTED_CHAINS,
} from "../hooks/useAdaptaFlow";
import Link from "next/link";

export default function TradePage() {
  const { isConnected: isEthConnected, address: ethAddress } = useAccount();
  const {
    isConnected: isNearConnected,
    accounts: nearAccounts,
    connectWallet: connectNear,
    loading: nearLoading,
  } = useNear();

  const {
    isLoading,
    orders,
    slippageMetrics,
    dashboardData,
    supportedChains,
    calculateSlippage,
    createOrder,
  } = useAdaptaFlow();

  const [formData, setFormData] = useState<OrderFormData>({
    fromChain: "sepolia",
    toChain: "nearTestnet",
    fromToken: "ETH",
    toToken: "NEAR",
    amount: "",
    maxSlippageDeviation: 1.0,
  });

  const [calculatedSlippage, setCalculatedSlippage] =
    useState<SlippageMetrics | null>(null);
  const [isCalculating, setIsCalculating] = useState(false);

  // Auto-calculate slippage when form data changes
  useEffect(() => {
    const debounceTimer = setTimeout(async () => {
      if (formData.amount && parseFloat(formData.amount) > 0) {
        try {
          setIsCalculating(true);
          const metrics = await calculateSlippage(
            formData.fromChain,
            formData.toChain,
            formData.fromToken,
            formData.toToken,
            formData.amount
          );
          setCalculatedSlippage(metrics);
        } catch (error) {
          console.error("Error calculating slippage:", error);
        } finally {
          setIsCalculating(false);
        }
      }
    }, 1000);

    return () => clearTimeout(debounceTimer);
  }, [
    formData.fromChain,
    formData.toChain,
    formData.fromToken,
    formData.toToken,
    formData.amount,
    calculateSlippage,
  ]);

  const handleCreateOrder = async () => {
    if (!isEthConnected) {
      alert("Please connect your wallet first");
      return;
    }

    if (!formData.amount || parseFloat(formData.amount) <= 0) {
      alert("Please enter a valid amount");
      return;
    }

    try {
      const hash = await createOrder(formData);
      const fromChain = supportedChains[formData.fromChain];
      const toChain = supportedChains[formData.toChain];

      alert(
        `🔥 Order created successfully!\n\nTransaction: ${hash}\n\nRoute: ${fromChain.name} → ${toChain.name}\nExplorer: ${fromChain.blockExplorer}`
      );

      // Reset form
      setFormData({
        ...formData,
        amount: "",
      });
      setCalculatedSlippage(null);
    } catch (error) {
      console.error("Error creating order:", error);
      alert("Failed to create order. Please try again.");
    }
  };

  // Update tokens when chain changes
  const handleFromChainChange = (chain: keyof typeof SUPPORTED_CHAINS) => {
    const chainConfig = supportedChains[chain];
    setFormData({
      ...formData,
      fromChain: chain,
      fromToken: chainConfig.tokens[0], // Set to first available token
    });
  };

  const handleToChainChange = (chain: keyof typeof SUPPORTED_CHAINS) => {
    const chainConfig = supportedChains[chain];
    setFormData({
      ...formData,
      toChain: chain,
      toToken: chainConfig.tokens[0], // Set to first available token
    });
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-orange-900 to-black">
      {/* Header */}
      <header className="bg-black/50 backdrop-blur-md shadow-2xl border-b border-orange-500/30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center space-x-6">
              <Link
                href="/"
                className="flex items-center hover:opacity-80 transition-opacity"
              >
                <div className="w-10 h-10 mr-3">
                  <img
                    src="/logo.png"
                    alt="AdaptaFlow Logo"
                    className="w-full h-full object-contain"
                  />
                </div>
                <h1 className="text-3xl font-bold bg-gradient-to-r from-orange-400 to-red-400 bg-clip-text text-transparent">
                  AdaptaFlow
                </h1>
              </Link>
              <nav className="flex items-center space-x-4">
                <Link
                  href="/"
                  className="text-gray-300 hover:text-orange-400 transition-colors"
                >
                  Home
                </Link>
                <span className="text-orange-400 font-medium">Trade</span>
              </nav>
            </div>
            <div className="flex items-center space-x-4">
              <WalletConnectionStatus />
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        {/* Page Title */}
        <div className="text-center mb-12">
          <h2 className="text-4xl font-bold bg-gradient-to-r from-orange-400 via-red-400 to-orange-400 bg-clip-text text-transparent mb-4">
            Adaptive Cross-Chain Trading
          </h2>
          <p className="text-xl text-gray-300 max-w-2xl mx-auto">
            Execute cross-chain trades with AI-powered slippage optimization
          </p>
        </div>

        {/* Trading Interface */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
          {/* Order Form */}
          <div className="bg-black/40 backdrop-blur-sm rounded-2xl border border-gray-700/50 p-8">
            <h3 className="text-2xl font-bold text-white mb-6">
              🎯 Create Adaptive Order
            </h3>
            <MultiChainOrderForm
              formData={formData}
              setFormData={setFormData}
              supportedChains={supportedChains}
              calculatedSlippage={calculatedSlippage}
              isCalculating={isCalculating}
              isLoading={isLoading}
              onCreateOrder={handleCreateOrder}
              onFromChainChange={handleFromChainChange}
              onToChainChange={handleToChainChange}
              isConnected={isEthConnected}
            />
          </div>

          {/* Active Orders */}
          <div className="bg-black/40 backdrop-blur-sm rounded-2xl border border-gray-700/50 p-8">
            <h3 className="text-2xl font-bold text-white mb-6">
              📈 Your Active Orders
            </h3>
            <div className="space-y-4">
              {!isEthConnected ? (
                <div className="text-center py-12 text-gray-400">
                  <p className="mb-4">Connect your wallet to view orders</p>
                  <ConnectButton />
                </div>
              ) : orders.length === 0 ? (
                <div className="text-center py-12 text-gray-400">
                  <p>No active orders yet.</p>
                  <p className="text-sm mt-2">
                    Create your first adaptive order to get started!
                  </p>
                </div>
              ) : (
                orders.map((order) => (
                  <MultiChainOrderCard
                    key={order.id}
                    order={order}
                    supportedChains={supportedChains}
                  />
                ))
              )}
            </div>
          </div>
        </div>

        {/* Quick Stats */}
        <div className="mt-12 bg-black/40 backdrop-blur-sm rounded-2xl border border-gray-700/50 p-8">
          <h3 className="text-xl font-bold text-white mb-6 text-center">
            📊 Live Market Data
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
            <div className="text-center">
              <div className="text-2xl font-bold bg-gradient-to-r from-green-400 to-green-600 bg-clip-text text-transparent">
                2.4%
              </div>
              <div className="text-sm text-gray-400">Avg Slippage ETH→NEAR</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold bg-gradient-to-r from-orange-400 to-red-400 bg-clip-text text-transparent">
                $12.5K
              </div>
              <div className="text-sm text-gray-400">24h Volume</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold bg-gradient-to-r from-yellow-400 to-orange-400 bg-clip-text text-transparent">
                94%
              </div>
              <div className="text-sm text-gray-400">Success Rate</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                8
              </div>
              <div className="text-sm text-gray-400">Active Chains</div>
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

function MultiChainOrderForm({
  formData,
  setFormData,
  supportedChains,
  calculatedSlippage,
  isCalculating,
  isLoading,
  onCreateOrder,
  onFromChainChange,
  onToChainChange,
  isConnected,
}: {
  formData: OrderFormData;
  setFormData: (data: OrderFormData) => void;
  supportedChains: typeof SUPPORTED_CHAINS;
  calculatedSlippage: SlippageMetrics | null;
  isCalculating: boolean;
  isLoading: boolean;
  onCreateOrder: () => void;
  onFromChainChange: (chain: keyof typeof SUPPORTED_CHAINS) => void;
  onToChainChange: (chain: keyof typeof SUPPORTED_CHAINS) => void;
  isConnected: boolean;
}) {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            From Chain
          </label>
          <select
            value={formData.fromChain}
            onChange={(e) =>
              onFromChainChange(e.target.value as keyof typeof SUPPORTED_CHAINS)
            }
            className="w-full px-3 py-2 bg-gray-800/50 border border-gray-600/50 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-white"
          >
            {Object.entries(supportedChains).map(([key, chain]) => (
              <option key={key} value={key}>
                {chain.icon} {chain.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            To Chain
          </label>
          <select
            value={formData.toChain}
            onChange={(e) =>
              onToChainChange(e.target.value as keyof typeof SUPPORTED_CHAINS)
            }
            className="w-full px-3 py-2 bg-gray-800/50 border border-gray-600/50 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-white"
          >
            {Object.entries(supportedChains).map(([key, chain]) => (
              <option key={key} value={key}>
                {chain.icon} {chain.name}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            From Token
          </label>
          <select
            value={formData.fromToken}
            onChange={(e) =>
              setFormData({ ...formData, fromToken: e.target.value })
            }
            className="w-full px-3 py-2 bg-gray-800/50 border border-gray-600/50 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-white"
          >
            {supportedChains[formData.fromChain].tokens.map((token) => (
              <option key={token} value={token}>
                {token}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">
            To Token
          </label>
          <select
            value={formData.toToken}
            onChange={(e) =>
              setFormData({ ...formData, toToken: e.target.value })
            }
            className="w-full px-3 py-2 bg-gray-800/50 border border-gray-600/50 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-white"
          >
            {supportedChains[formData.toChain].tokens.map((token) => (
              <option key={token} value={token}>
                {token}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-300 mb-2">
          Amount
        </label>
        <input
          type="number"
          value={formData.amount}
          onChange={(e) => setFormData({ ...formData, amount: e.target.value })}
          placeholder="0.1"
          className="w-full px-3 py-2 bg-gray-800/50 border border-gray-600/50 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-white placeholder-gray-400"
        />
        <p className="text-xs text-gray-400 mt-1">Enter amount to trade</p>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-300 mb-2">
          Max Slippage Deviation
        </label>
        <select
          value={formData.maxSlippageDeviation}
          onChange={(e) =>
            setFormData({
              ...formData,
              maxSlippageDeviation: parseFloat(e.target.value),
            })
          }
          className="w-full px-3 py-2 bg-gray-800/50 border border-gray-600/50 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-orange-500 text-white"
        >
          <option value={0.5}>0.5% (Conservative)</option>
          <option value={1.0}>1.0% (Balanced)</option>
          <option value={2.0}>2.0% (Aggressive)</option>
        </select>
      </div>

      {/* AI Slippage Preview */}
      {(calculatedSlippage || isCalculating) && (
        <div className="bg-gradient-to-r from-orange-900/30 to-red-900/30 backdrop-blur-sm rounded-lg p-4 border border-orange-500/30">
          <h4 className="font-semibold text-orange-300 mb-2">
            🔥 AI Slippage Optimization
          </h4>
          {isCalculating ? (
            <div className="text-center py-4">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-orange-400 mx-auto"></div>
              <p className="text-sm text-orange-300 mt-2">
                Analyzing cross-chain conditions...
              </p>
            </div>
          ) : calculatedSlippage ? (
            <div className="text-sm space-y-1">
              <div className="flex justify-between">
                <span className="text-gray-300">Base slippage:</span>
                <span className="font-medium text-white">
                  {calculatedSlippage.baseSlippage.toFixed(2)}%
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-300">Volatility adjustment:</span>
                <span className="font-medium text-white">
                  +{calculatedSlippage.volatilityAdjustment.toFixed(2)}%
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-300">Bridge delay premium:</span>
                <span className="font-medium text-white">
                  +{calculatedSlippage.bridgeDelayPremium.toFixed(2)}%
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-300">Cross-chain premium:</span>
                <span className="font-medium text-white">
                  +{calculatedSlippage.crossChainPremium.toFixed(2)}%
                </span>
              </div>
              <div className="flex justify-between border-t border-orange-400/30 pt-2">
                <span className="font-semibold text-orange-300">
                  Optimized slippage:
                </span>
                <span className="font-bold bg-gradient-to-r from-orange-400 to-red-400 bg-clip-text text-transparent">
                  {calculatedSlippage.dynamicSlippage.toFixed(2)}%
                </span>
              </div>
              <div className="text-xs text-orange-400 mt-2">
                🔥 Confidence: {calculatedSlippage.confidence.toFixed(0)}% |
                Route: {supportedChains[formData.fromChain].icon} →{" "}
                {supportedChains[formData.toChain].icon}
              </div>
            </div>
          ) : null}
        </div>
      )}

      <button
        onClick={onCreateOrder}
        disabled={!isConnected || isLoading || !formData.amount}
        className="w-full bg-gradient-to-r from-orange-600 to-red-600 hover:from-orange-700 hover:to-red-700 disabled:from-gray-600 disabled:to-gray-700 disabled:cursor-not-allowed text-white py-3 rounded-lg font-medium transition-all duration-200 shadow-lg"
      >
        {!isConnected
          ? "Connect Wallet"
          : isLoading
          ? "Creating Order..."
          : "Create Adaptive Order"}
      </button>
    </div>
  );
}

function MultiChainOrderCard({
  order,
  supportedChains,
}: {
  order: any;
  supportedChains: typeof SUPPORTED_CHAINS;
}) {
  const statusColor =
    order.status === "Active"
      ? "green"
      : order.status === "Executing"
      ? "orange"
      : "gray";

  const fromChain =
    supportedChains[order.fromChain as keyof typeof SUPPORTED_CHAINS];
  const toChain =
    supportedChains[order.toChain as keyof typeof SUPPORTED_CHAINS];

  return (
    <div className="bg-gradient-to-r from-gray-800/50 to-gray-900/50 border border-gray-600/30 rounded-lg p-4 hover:border-orange-400/50 transition-all duration-300">
      <div className="flex justify-between items-start mb-3">
        <div>
          <span className="text-sm text-gray-400">Order #{order.id}</span>
          <p className="font-medium text-white">
            {order.amountIn} {order.tokenIn} → {order.tokenOut}
          </p>
          <p className="text-sm text-gray-400">
            {fromChain?.icon} {fromChain?.name} → {toChain?.icon}{" "}
            {toChain?.name}
          </p>
        </div>
        <span
          className={`px-2 py-1 bg-${statusColor}-900/50 text-${statusColor}-400 text-xs font-medium rounded-full border border-${statusColor}-400/30`}
        >
          {order.status}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-4 text-sm">
        <div>
          <span className="text-gray-400">Current Slippage:</span>
          <p className="font-medium bg-gradient-to-r from-orange-400 to-red-400 bg-clip-text text-transparent">
            {order.currentSlippage.toFixed(2)}%
          </p>
        </div>
        <div>
          <span className="text-gray-400">Adaptations:</span>
          <p className="font-medium text-green-400">
            {order.adaptiveChanges} optimizations
          </p>
        </div>
        <div>
          <span className="text-gray-400">Time Remaining:</span>
          <p className="font-medium text-white">{order.timeRemaining}</p>
        </div>
        <div>
          <span className="text-gray-400">Bridge Status:</span>
          <p className="font-medium text-white">Active</p>
        </div>
      </div>
    </div>
  );
}
