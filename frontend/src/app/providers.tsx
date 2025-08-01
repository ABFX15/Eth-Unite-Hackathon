"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { RainbowKitProvider } from "@rainbow-me/rainbowkit";
import { config } from "./wagmi";
import {
  createContext,
  useContext,
  useEffect,
  useState,
  ReactNode,
} from "react";

// NEAR Wallet Selector imports
import { setupWalletSelector } from "@near-wallet-selector/core";
import { setupMyNearWallet } from "@near-wallet-selector/my-near-wallet";
import { setupModal } from "@near-wallet-selector/modal-ui";
import type { WalletSelector, AccountState } from "@near-wallet-selector/core";

import "@rainbow-me/rainbowkit/styles.css";
import "@near-wallet-selector/modal-ui/styles.css";

const queryClient = new QueryClient();

// NEAR Context
interface NearContextType {
  selector: WalletSelector | null;
  modal: any;
  accounts: AccountState[];
  isConnected: boolean;
  loading: boolean;
  connectWallet: () => void;
  signOut: () => void;
}

const NearContext = createContext<NearContextType>({
  selector: null,
  modal: null,
  accounts: [],
  isConnected: false,
  loading: true,
  connectWallet: () => {},
  signOut: () => {},
});

export function NearProvider({ children }: { children: ReactNode }) {
  const [selector, setSelector] = useState<WalletSelector | null>(null);
  const [modal, setModal] = useState<any>(null);
  const [accounts, setAccounts] = useState<AccountState[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    initNearWallet();
  }, []);

  const initNearWallet = async () => {
    console.log("🔄 Initializing NEAR wallet selector...");

    try {
      const walletSelector = await setupWalletSelector({
        network: "testnet",
        modules: [setupMyNearWallet()],
      });

      const walletSelectorModal = setupModal(walletSelector, {
        contractId: "guest-book.testnet", // Use a known testnet contract
      });

      setSelector(walletSelector);
      setModal(walletSelectorModal);

      // Subscribe to account changes
      const subscription = walletSelector.store.observable.subscribe(
        (state) => {
          console.log("📱 NEAR wallet state changed:", state);
          setAccounts(state.accounts);
        }
      );

      // Get initial state
      const state = walletSelector.store.getState();
      console.log("🏁 Initial NEAR wallet state:", state);
      setAccounts(state.accounts);

      setLoading(false);
      console.log("✅ NEAR wallet selector initialized successfully");

      // Cleanup on unmount
      return () => subscription.unsubscribe();
    } catch (error) {
      console.error("❌ Failed to initialize NEAR wallet:", error);
      setLoading(false);
    }
  };

  const connectWallet = () => {
    console.log("🔗 Opening NEAR wallet selector modal...");

    if (modal) {
      modal.show();
    } else {
      console.error("❌ Modal not initialized");
    }
  };

  const signOut = async () => {
    if (selector) {
      const wallet = await selector.wallet();
      wallet.signOut().then(() => {
        console.log("👋 Signed out of NEAR wallet");
        setAccounts([]);
      });
    }
  };

  const value: NearContextType = {
    selector,
    modal,
    accounts,
    isConnected: accounts.length > 0,
    loading,
    connectWallet,
    signOut,
  };

  return <NearContext.Provider value={value}>{children}</NearContext.Provider>;
}

export function useNear() {
  const context = useContext(NearContext);
  if (!context) {
    throw new Error("useNear must be used within a NearProvider");
  }
  return context;
}

export function Providers({ children }: { children: ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          <NearProvider>{children}</NearProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
