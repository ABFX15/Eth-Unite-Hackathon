import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import {
    mainnet,
    polygon,
    arbitrum,
    base,
    optimism,
    sepolia,
    polygonMumbai,
    arbitrumSepolia,
    baseSepolia,
    optimismSepolia
} from 'wagmi/chains';

export const config = getDefaultConfig({
    appName: 'AdaptaFlow Protocol - Testnet Demo',
    projectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || 'demo',
    chains: [
        // Mainnets (for reference)
        mainnet,
        polygon,
        arbitrum,
        base,
        optimism,

        // Testnets (primary for hackathon)
        sepolia,
        polygonMumbai,
        arbitrumSepolia,
        baseSepolia,
        optimismSepolia,
    ],
    ssr: true,
}); 