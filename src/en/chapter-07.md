# Chapter 7: Complete Guide to Builder Scaffold (Part 2) — TS Scripts and dApp Development

> **Learning Objectives**: Master the usage and principles of the 6 interaction scripts in `ts-scripts/`, understand the `helper.ts` toolchain, and learn to build your own EVE Frontier dApp based on the `dapps/` React template.

---

> Status: Mapped scripts and dApp directories. This text is based on the script layout in the `builder-scaffold` within this repository.

## Minimal Call Chain

`Read .env -> helper.ts initializes client/object ID -> TS script initiates PTB -> On-chain object changes -> dApp queries and displays new state`

## Directory Responsibility Boundaries

To use `builder-scaffold` smoothly, the key isn't memorizing every script name, but first distinguishing the three layers of responsibilities:

| Directory/File | Responsibility | Should NOT Do |
|------|------|------|
| `ts-scripts/smart_gate/*` | Organize individual business actions, assemble PTB | Cram lots of shared utility functions |
| `ts-scripts/utils/helper.ts` | Initialize client, read environment, encapsulate common queries | Write specific business rules |
| `dapps/src/*` | Display state, initiate interactions, handle wallet connections | Directly hardcode environment and object IDs |

## What Should a Complete Script Chain Look Like?

```text
.env
  -> helper.ts reads network / package id / key
  -> Business script assembles PTB
  -> Submit on-chain transaction
  -> dApp or query script refreshes object state
```

If a script is simultaneously responsible for "reading config + querying objects + assembling complex business rules + printing UI text", it should basically be split up.

What the script system really needs to solve isn't just "automating command lines", but separating responsibilities clearly:

- Where does configuration come from
- Who is responsible for common queries
- Who organizes individual business actions
- How do frontend and scripts share the same object understanding

## Two Common Anti-patterns

- `helper.ts` keeps growing until it becomes an unmaintainable "god file"
- Frontend directly copies object IDs and network configs from scripts, causing scripts and pages to drift over time

## Corresponding Code Directories

- [builder-scaffold/ts-scripts](https://github.com/evefrontier/builder-scaffold/tree/main/ts-scripts)
- [builder-scaffold/dapps](https://github.com/evefrontier/builder-scaffold/tree/main/dapps)

## 1. Prerequisites for TypeScript Scripts

Before running any script, you need to complete the following preparation:

```
Prerequisites:
1. ✅ world-contracts deployed (local or testnet)
2. ✅ smart_gate contract deployed (execute sui client publish)
3. ✅ .env file filled with all necessary environment variables
4. ✅ test-resources.json + extracted-object-ids.json exist in project root
```

### Configure .env File

```bash
cp .env.example .env
```

Key environment variables:

```dotenv
# Network selection
NETWORK=localnet        # localnet | testnet | mainnet

# Admin private key (exported Sui key, 0x prefixed Bech32 format)
ADMIN_EXPORTED_KEY=suiprivkey1...

# Contract addresses
WORLD_PACKAGE_ID=0xabc...    # Package ID after world-contracts deployment
BUILDER_PACKAGE_ID=0xdef...  # Package ID after smart_gate deployment

# Tenant name (game world namespace)
TENANT=evefrontier
```

### The Essence of `.env` Isn't a Config Table, But Engineering Boundaries

As long as a value changes depending on the environment, it shouldn't be scattered throughout script bodies.

The most common drifting values include:

- Network
- Package IDs
- Admin keys
- Tenant names
- Key object IDs

Once these things are written separately in scripts, frontend, and tests, troubleshooting later will be very painful.

---

## 2. Execution Order and Functions of the 6 Scripts

### Complete Execution Flow

```
① pnpm configure-rules       → Set Gate extension rules (tribe ID, bounty item type_id)
② pnpm authorise-gate        → Register extension to Gate object
③ pnpm authorise-storage-unit → Register extension to StorageUnit
④ pnpm issue-tribe-jump-permit → Issue pass for characters meeting tribal conditions
⑤ pnpm jump-with-permit      → Jump with pass
⑥ pnpm collect-corpse-bounty → Submit corpse items → Receive pass (bounty flow)
```

---

## 3. Detailed Reading: configure-rules.ts

This is the most frequently modified script, responsible for initializing two types of rules:

```typescript
// ts-scripts/smart_gate/configure-rules.ts
import { Transaction } from "@mysten/sui/transactions";
import { getEnvConfig, initializeContext, hydrateWorldConfig } from "../utils/helper";
import { resolveSmartGateExtensionIds } from "./extension-ids";

async function main() {
    // 1. Read .env config
    const env = getEnvConfig();

    // 2. Initialize Sui client + keypair
    const ctx = initializeContext(env.network, env.adminExportedKey);
    const { client, keypair, address } = ctx;

    // 3. Read world-contracts config from chain
    await hydrateWorldConfig(ctx);

    // 4. Query AdminCap, ExtensionConfig object IDs from chain
    const { builderPackageId, adminCapId, extensionConfigId } =
        await resolveSmartGateExtensionIds(client, address);

    const tx = new Transaction();

    // 5. Set tribe rule (tribe=100, valid for 1 hour)
    tx.moveCall({
        target: `${builderPackageId}::tribe_permit::set_tribe_config`,
        arguments: [
            tx.object(extensionConfigId),
            tx.object(adminCapId),
            tx.pure.u32(100),           // Allowed tribe ID
            tx.pure.u64(3600000),       // Validity: 1 hour (milliseconds)
        ],
    });

    // 6. Set bounty rule (item type_id=ITEM_A_TYPE_ID, valid for 1 hour)
    tx.moveCall({
        target: `${builderPackageId}::corpse_gate_bounty::set_bounty_config`,
        arguments: [
            tx.object(extensionConfigId),
            tx.object(adminCapId),
            tx.pure.u64(ITEM_A_TYPE_ID),  // Corpse item's type_id
            tx.pure.u64(3600000),
        ],
    });

    // 7. Submit transaction
    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEffects: true, showObjectChanges: true },
    });

    console.log("Transaction digest:", result.digest);
}
```

### What Structure Is Most Worth Keeping in This Type of Script?

It's this clear chain:

1. Read environment
2. Initialize context
3. Resolve key on-chain objects
4. Assemble PTB
5. Submit and record digest

As long as you maintain this skeleton when adding new scripts in the future, the engineering will be much more stable.

### Modifying Rule Parameters

Common modification points:

```typescript
// Change to allow tribe ID = 3 (corresponding to your game world's tribe config)
tx.pure.u32(3),

// Change to 24-hour validity period
tx.pure.u64(24 * 60 * 60 * 1000),

// ITEM_A_TYPE_ID is defined in utils/constants.ts, adjust according to actual items
```

---

## 4. Utility Function Analysis: `utils/helper.ts`

This is the shared base component for all scripts:

```typescript
import { getEnvConfig, initializeContext, hydrateWorldConfig } from "../utils/helper";

// getEnvConfig(): Read .env and validate necessary fields
const env = getEnvConfig();
// → { network, rpcUrl, packageId, adminExportedKey, tenant }

// initializeContext(): Create Sui RPC client and Ed25519 keypair
const ctx = initializeContext(env.network, env.adminExportedKey);
// → { client, keypair, address, config, network }

// hydrateWorldConfig(): Read world config from chain (ObjectRegistry, AdminACL and other object IDs)
await hydrateWorldConfig(ctx);
// Afterwards can access all world object IDs via ctx.config
```

### Key Utilities

```
utils/
├── helper.ts           # Environment config, context initialization, world config reading
├── config.ts           # Network types, WorldConfig interface, RPC URL mapping
├── constants.ts        # TENANT, ITEM_A_TYPE_ID and other constants
├── derive-object-id.ts # Derive Sui object ID from game item_id (deterministic)
└── proof.ts            # Generate LocationProof (for location verification testing)
```

### Why Is `helper.ts` Both Important and Dangerous?

Because it naturally becomes the central file that all scripts depend on.

Important because:

- It unifies network, client, and config reading
- It reduces duplicate code

Dangerous because:

- It can easily expand infinitely
- Eventually absorbing a bunch of business logic too

So a more stable principle is: `helper.ts` should only do "common infrastructure", not "specific business strategy".

---

## 5. resolve-extension-ids.ts: Automatically Query Object IDs

```typescript
// No need to manually query object IDs! Script will automatically find AdminCap and ExtensionConfig from chain
export async function resolveSmartGateExtensionIds(client, ownerAddress) {
    // Find AdminCap object belonging to ownerAddress
    const adminCapId = await findObjectByType(
        client,
        ownerAddress,
        `${builderPackageId}::config::AdminCap`,
    );

    // Find shared ExtensionConfig object
    const extensionConfigId = await findSharedObjectByType(
        client,
        `${builderPackageId}::config::ExtensionConfig`,
    );

    return { builderPackageId, adminCapId, extensionConfigId };
}
```

---

## 6. Adding Scripts for Custom Contracts

Using the `toll_gate` example from Chapter 6, add a `configure-toll.ts`:

```typescript
// ts-scripts/smart_gate/configure-toll.ts
import "dotenv/config";
import { Transaction } from "@mysten/sui/transactions";
import { getEnvConfig, initializeContext, hydrateWorldConfig } from "../utils/helper";
import { resolveSmartGateExtensionIds } from "./extension-ids";

async function main() {
    const env = getEnvConfig();
    const ctx = initializeContext(env.network, env.adminExportedKey);
    await hydrateWorldConfig(ctx);
    const { client, keypair } = ctx;

    const { builderPackageId, adminCapId, extensionConfigId } =
        await resolveSmartGateExtensionIds(client, ctx.address);

    const tx = new Transaction();

    tx.moveCall({
        target: `${builderPackageId}::toll_gate::set_toll_config`,
        arguments: [
            tx.object(extensionConfigId),
            tx.object(adminCapId),
            tx.pure.u64(1_000_000_000),   // Toll: 1 SUI = 10^9 MIST
            tx.pure.u64(3600000),          // Valid for 1 hour
        ],
    });

    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEffects: true },
    });

    console.log("Toll config set! Digest:", result.digest);
}

main();
```

Then add to `package.json`:

```json
"scripts": {
    "configure-toll": "tsx ts-scripts/smart_gate/configure-toll.ts"
}
```

---

## 7. dApp Template: Quick Start

```bash
cd dapps
pnpm install
cp .envsample .env       # Fill in VITE_ITEM_ID and other variables
pnpm dev                 # Start dev server: http://localhost:5173
```

### Tech Stack

| Library | Version | Purpose |
|----|------|------|
| React + TypeScript | 18 | UI framework |
| Vite | 5 | Build tool |
| Radix UI | 1 | UI component library |
| `@evefrontier/dapp-kit` | latest | EVE Frontier dedicated SDK |
| `@mysten/dapp-kit-react` | latest | Sui wallet connection |

### Provider Architecture (main.tsx)

```tsx
// src/main.tsx
ReactDOM.createRoot(document.getElementById("root")!).render(
    <EveFrontierProvider queryClient={queryClient}>
        {/* One Provider combines all necessary Contexts */}
        {/* QueryClientProvider → DAppKitProvider → VaultProvider → SmartObjectProvider → NotificationProvider */}
        <App />
    </EveFrontierProvider>,
);
```

---

## 8. Core Hooks Reference

### Wallet Connection (App.tsx)

```tsx
import { abbreviateAddress, useConnection } from "@evefrontier/dapp-kit";
import { useCurrentAccount } from "@mysten/dapp-kit-react";

// Connect/disconnect wallet
const { handleConnect, handleDisconnect, isConnected, walletAddress } = useConnection();

// Read current account
const account = useCurrentAccount();

// Display abbreviated address (e.g., 0x1234...5678)
<span>{abbreviateAddress(account?.address ?? "")}</span>
```

### Read Smart Object (Assembly Data)

```tsx
import { useSmartObject } from "@evefrontier/dapp-kit";

// Pass in-game item_id (from URL params or env)
const { assembly, character, loading, error, refetch } = useSmartObject({
    itemId: VITE_ITEM_ID,
});

// assembly contains: name, typeId, state, id, owner character
// character contains: holder character info
```

### Execute Transaction (WalletStatus.tsx)

```tsx
import { useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

const { signAndExecuteTransaction } = useDAppKit();

async function callMyContract() {
    const tx = new Transaction();
    tx.moveCall({
        target: `${PACKAGE_ID}::tribe_permit::issue_jump_permit`,
        arguments: [/* ... */],
    });

    const result = await signAndExecuteTransaction({ transaction: tx });
    await refetch();  // Refresh assembly state
}
```

---

## 9. Practice: Issue Tribal Pass in dApp

```tsx
// src/components/IssuePermit.tsx
import { useSmartObject, useConnection } from "@evefrontier/dapp-kit";
import { useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

export function IssuePermit({ gateItemId }: { gateItemId: string }) {
    const { assembly } = useSmartObject({ itemId: gateItemId });
    const { isConnected } = useConnection();
    const { signAndExecuteTransaction } = useDAppKit();

    const handleIssuePermit = async () => {
        const tx = new Transaction();
        tx.moveCall({
            target: `${import.meta.env.VITE_BUILDER_PACKAGE_ID}::tribe_permit::issue_jump_permit`,
            arguments: [
                tx.object(import.meta.env.VITE_EXTENSION_CONFIG_ID),
                tx.object(SOURCE_GATE_ID),
                tx.object(DEST_GATE_ID),
                tx.object(CHARACTER_ID),
                tx.object("0x6"),  // Clock object (Sui system object fixed ID)
            ],
        });

        const result = await signAndExecuteTransaction({ transaction: tx });
        console.log("JumpPermit issued!", result.digest);
    };

    return (
        <button
            onClick={handleIssuePermit}
            disabled={!isConnected || !assembly}
        >
            {assembly ? `Apply for ${assembly.name}` : "Loading..."}
        </button>
    );
}
```

---

## 10. Sponsored Transactions (Sponsored TX)

For Builders wanting to hide gas fees, dapp-kit supports sponsored transactions:

```tsx
import { useSponsoredTransaction } from "@evefrontier/dapp-kit";

const { sponsoredSignAndExecute } = useSponsoredTransaction();

// Player doesn't need to pay gas — Builder's server pays for them
await sponsoredSignAndExecute({ transaction: tx });

// Note: Only EVE Vault wallet supports this feature
// If user uses other wallets, need to catch WalletSponsoredTransactionNotSupportedError
```

---

## 11. GraphQL Data Query (Advanced)

When `useSmartObject` isn't sufficient, you can use GraphQL directly:

```tsx
import { executeGraphQLQuery, getAssemblyWithOwner } from "@evefrontier/dapp-kit";

// Query Gate's complete data (including owner character)
const gateData = await getAssemblyWithOwner({ itemId: gateItemId });

// Execute custom GraphQL query
const result = await executeGraphQLQuery(`
    query GetMyGates($owner: SuiAddress!) {
        objects(filter: { type: "${PACKAGE_ID}::smart_gate::Gate", owner: $owner }) {
            nodes {
                address
                contents { json }
            }
        }
    }
`, { owner: address });
```

---

## 12. Complete Project Setup Flow Summary

```
1. Clone builder-scaffold
2. Clone world-contracts (Docker users: on host, automatically visible in container)
3. Choose workflow: Docker or Host
4. Start local chain (docker compose run or sui start)
5. Deploy world-contracts (refer to docs/builder-flow-docker.md)
6. Compile smart_gate: sui move build -e testnet
7. Deploy smart_gate: sui client test-publish --pubfile-path ...
8. Fill .env file (BUILDER_PACKAGE_ID + WORLD_PACKAGE_ID + ADMIN_KEY)
9. Run pnpm configure-rules → pnpm authorise-gate → pnpm issue-tribe-jump-permit
10. Start dApp: cd dapps && pnpm dev
```

---

## Chapter Summary

| Component | Purpose |
|------|------|
| `configure-rules` | Set tribe + bounty config rules |
| `authorise-gate` | Register XAuth to target Gate |
| `issue-tribe-jump-permit` | Issue JumpPermit for qualified players |
| `utils/helper.ts` | Environment variables, Sui client, world config initialization |
| `EveFrontierProvider` | Uniformly wraps all React Contexts |
| `useSmartObject` | Core Hook for reading on-chain Assembly data |
| `useSponsoredTransaction` | Sponsored transactions paying Gas for players |

> These two chapters cover the complete chain from local setup to contract deployment, script interaction, and frontend development for Builder Scaffold. Combined with previous World contract chapters, you now have all the knowledge to independently build an end-to-end EVE Frontier Builder application.
