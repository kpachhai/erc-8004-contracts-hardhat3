import "@nomicfoundation/hardhat-ethers";

import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";
import hashscanVerify from "hashscan-verify";

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin, hashscanVerify],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          },
          viaIR: true
        }
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          },
          viaIR: true
        }
      }
    }
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1"
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op"
    },
    hederaTestnet: {
      chainId: 296,
      type: "http",
      chainType: "l1",
      url: configVariable("HEDERA_RPC_URL"),
      accounts: [configVariable("HEDERA_PRIVATE_KEY")]
    }
  }
};

export default config;
