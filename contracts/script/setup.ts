// setup.ts - Cross-chain ENS v2 testing with blocksmith.js
import { anvil } from "prool/instances";
import {
  executeDeployScripts,
  resolveConfig,
  type Environment,
  type UnknownDeployments,
  type UnresolvedNetworkSpecificData,
  type UnresolvedUnknownNamedAccounts,
} from "rocketh";
import {
  createClient,
  getContract,
  webSocket,
  type Abi,
  type Account,
  type Chain,
  type Client,
  type GetContractReturnType,
  type Transport,
} from "viem";

import type { artifacts } from "@rocketh";
import { mnemonicToAccount } from "viem/accounts";
import { readConfig } from "./readConfig.js";

const l1Config = {
  port: 8545,
  chainId: 31337,
};

const l2Config = {
  port: 8546,
  chainId: 31338,
};

function createDeploymentGetter<
  transport extends Transport = Transport,
  chain extends Chain | undefined = Chain | undefined,
  account extends Account | undefined = Account | undefined,
  client extends Client<transport, chain, account> = Client<
    transport,
    chain,
    account
  >,
>(
  environment: Environment<
    UnresolvedUnknownNamedAccounts,
    UnresolvedNetworkSpecificData,
    UnknownDeployments
  >,
  client: client,
) {
  return <TAbi extends Abi>(
    name: string,
  ): GetContractReturnType<TAbi, client> => {
    const deployment = environment.get(name);
    return getContract({
      abi: deployment.abi,
      address: deployment.address,
      client,
    }) as unknown as GetContractReturnType<TAbi, client>;
  };
}

/**
 * Sets up the cross-chain testing environment using blocksmith.js
 * @ref https://github.com/adraffy/blocksmith.js
 * @returns Environment with L1 and L2 contracts and a relayer
 */
export async function setupCrossChainEnvironment() {
  console.log("Setting up cross-chain ENS v2 environment...");

  // Launch two separate Anvil instances for L1 and L2
  const l1 = anvil(l1Config);
  const l2 = anvil(l2Config);

  await l1.start();
  await l2.start();

  console.log(`L1: Chain ID ${l1Config.chainId}, URL: ${l1.host}:${l1.port}`);
  console.log(`L2: Chain ID ${l2Config.chainId}, URL: ${l2.host}:${l2.port}`);

  // Deploy contracts to both chains
  console.log("Deploying contracts...");

  const l1Deploy = await executeDeployScripts(
    resolveConfig(
      await readConfig({
        askBeforeProceeding: false,
        network: "l1-local",
      }),
    ),
  );

  const l2Deploy = await executeDeployScripts(
    resolveConfig(
      await readConfig({
        askBeforeProceeding: false,
        network: "l2-local",
      }),
    ),
  );

  console.log("Cross-chain environment setup complete!");

  const account = mnemonicToAccount(
    "test test test test test test test test test test test junk",
  );

  const l1Chain = {
    id: l1Config.chainId,
    name: "L1 Local",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: {
      default: { http: [`http://127.0.0.1:${l1.port}`] },
      public: { http: [`http://127.0.0.1:${l1.port}`] },
    },
  } as const;

  const l2Chain = {
    id: l2Config.chainId,
    name: "L2 Local",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: {
      default: { http: [`http://127.0.0.1:${l2.port}`] },
      public: { http: [`http://127.0.0.1:${l2.port}`] },
    },
  } as const;

  const l1Client = createClient({
    chain: l1Chain,
    transport: webSocket(`ws://127.0.0.1:${l1.port}`, {
      retryCount: 0,
    }),
    account,
  });
  const l1Contracts = createDeploymentGetter(l1Deploy, l1Client);

  const l2Client = createClient({
    chain: l2Chain,
    transport: webSocket(`ws://127.0.0.1:${l2.port}`, {
      retryCount: 0,
    }),
    account,
  });
  const l2Contracts = createDeploymentGetter(l2Deploy, l2Client);

  // Return all deployed contracts, providers, and the relayer
  return {
    l1: {
      client: l1Client,
      accounts: {
        deployer: account,
      },
      contracts: {
        ejectionController: l1Contracts<
          (typeof artifacts.L1EjectionController)["abi"]
        >("L1EjectionController"),
        ethRegistry:
          l1Contracts<(typeof artifacts.PermissionedRegistry)["abi"]>(
            "L1ETHRegistry",
          ),
        mockBridge:
          l1Contracts<(typeof artifacts.MockL1Bridge)["abi"]>("MockL1Bridge"),
        registryDatastore:
          l1Contracts<(typeof artifacts.RegistryDatastore)["abi"]>(
            "RegistryDatastore",
          ),
        rootRegistry:
          l1Contracts<(typeof artifacts.PermissionedRegistry)["abi"]>(
            "RootRegistry",
          ),
        simpleRegistryMetadata: l1Contracts<
          (typeof artifacts.SimpleRegistryMetadata)["abi"]
        >("SimpleRegistryMetadata"),
        universalResolver:
          l1Contracts<(typeof artifacts.UniversalResolverV2)["abi"]>(
            "UniversalResolver",
          ),
      },
    },
    l2: {
      client: l2Client,
      accounts: {
        deployer: account,
      },
      contracts: {
        ethRegistrar:
          l2Contracts<(typeof artifacts.ETHRegistrar)["abi"]>("ETHRegistrar"),
        ethRegistry:
          l2Contracts<(typeof artifacts.PermissionedRegistry)["abi"]>(
            "ETHRegistry",
          ),
        bridgeController:
          l2Contracts<(typeof artifacts.L2BridgeController)["abi"]>(
            "L2BridgeController",
          ),
        mockBridge:
          l2Contracts<(typeof artifacts.MockL2Bridge)["abi"]>("MockL2Bridge"),
        priceOracle:
          l2Contracts<(typeof artifacts.IPriceOracle)["abi"]>("PriceOracle"),
        registryDatastore:
          l2Contracts<(typeof artifacts.RegistryDatastore)["abi"]>(
            "RegistryDatastore",
          ),
        simpleRegistryMetadata: l2Contracts<
          (typeof artifacts.SimpleRegistryMetadata)["abi"]
        >("SimpleRegistryMetadata"),
      },
    },
    // Safe shutdown function to properly terminate WebSocket connections
    shutdown: async () => {
      await l1.stop();
      await l2.stop();
    },
  };
}
export type CrossChainEnvironment = Awaited<
  ReturnType<typeof setupCrossChainEnvironment>
>;
export type L1Contracts = CrossChainEnvironment["l1"]["contracts"];
export type L2Contracts = CrossChainEnvironment["l2"]["contracts"];
export type L1Client = CrossChainEnvironment["l1"]["client"];
export type L2Client = CrossChainEnvironment["l2"]["client"];
