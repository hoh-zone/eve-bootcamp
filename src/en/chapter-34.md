# Chapter 34: EVE Vault Technical Architecture and Development Deployment

> **Learning Objective**: Understand EVE Vault's Chrome MV3 architecture (5 script layers, message protocol, Keeper security container), master complete flow for locally building and debugging extension, and division of responsibilities among packages in Monorepo.

---

> Status: Source code guide. Recommend reading while opening extension entry points and background code to verify message flows.

## Minimal Call Chain

`Page/content script request -> background dispatches message -> keeper protects sensitive state -> approval page signs -> response returns to caller`

## Corresponding Code Directory

- [evevault](https://github.com/evefrontier/evevault)

## 1. Project Structure (Monorepo)

```
evevault/
├── apps/
│   ├── extension/          # Chrome MV3 extension (main body)
│   │   ├── entrypoints/    # WXT entry points (each = independent page/script)
│   │   │   ├── background.ts        # Service Worker (background resident)
│   │   │   ├── content.ts           # Content script (injected into each page)
│   │   │   ├── injected.ts          # Page context script (register wallet)
│   │   │   ├── popup/               # Extension popup
│   │   │   ├── sign_transaction/    # Transaction approval page
│   │   │   ├── sign_sponsored_transaction/ # Sponsored transaction approval page
│   │   │   ├── sign_personal_message/     # Message signing approval page
│   │   │   ├── sign_and_execute_transaction/
│   │   │   └── keeper/              # Security key container
│   │   └── src/
│   │       ├── features/   # Feature modules (auth, wallet)
│   │       ├── lib/        # Core library (adapters, background, utils)
│   │       └── routes/     # React routes (TanStack Router)
│   └── web/                # Web version (coming soon)
└── packages/
    └── shared/             # Cross-app shared: types, Sui client, utility functions
        └── src/
            ├── types/      # Message types, wallet types, auth types
            ├── sui/        # SuiClient, GraphQL client
            └── auth/       # Enoki integration, zkLogin tools
```

**Build Tools**: Bun (package management) + Turborepo (build cache) + WXT (extension framework)

What's really worth understanding about Monorepo here:

> Vault isn't a single-page extension, but a group of isolated subsystems collaborating through message protocol.

So when looking at directory, better not just see "where files are," but see "which layer holds which powers."

---

## 2. Chrome MV3's 5-Layer Script Architecture

These 5 layers really solve security contradiction in browser extensions:

- dApp needs easy-to-access wallet interface
- But sensitive state can't be exposed to arbitrary page scripts

So architecture deliberately split into:

- Page layer is discoverable
- Relay layer can communicate
- Background layer can dispatch
- Keeper layer can keep secret
- Approval page lets user make final confirmation

Chrome MV3 extension isolation boundaries and communication methods between scripts:

```
┌──────────────────── Browser Tab (Web Page)───────────────────────┐
│                                                               │
│  dApp (Web Page JavaScript)                                       │
│      ↕ wallet-standard API (same process call)                      │
│  injected.ts ← Injected into page process by content.ts                   │
│      EveVaultWallet class registered to @mysten/wallet-standard           │
└───────────────────────────────────────────────────────────────┘
               ↕ window.postMessage (cross-process)
┌──────────────────── Chrome Extension Process ────────────────────┐
│  content.ts (content script)                                        │
│      Forward: page → background                                  │
│      Forward: background → page                                  │
└───────────────────────────────────────────────────────────────┘
               ↕ chrome.runtime.sendMessage
┌──────────────────── Service Worker ────────────────────────────┐
│  background.ts                                                  │
│      OAuth flow, Token exchange, Storage management                      │
│      Handle signing requests (forward to Keeper)                             │
│      ↕ chrome.runtime Port                                    │
│  keeper.ts (hidden iframe, memory security container)                        │
│      Store ephemeral private key (not written to chrome.storage)                       │
└─────────────────────────────────────────────────────────────────┘
               ↕ chrome.runtime.sendMessage
┌──────────────────── Extension Pages ───────────────────────────┐
│  popup/               ← Displayed when clicking extension icon                       │
│  sign_transaction/    ← Transaction approval popup                           │
│  sign_sponsored_transaction/ ← Sponsored transaction approval                   │
│  sign_personal_message/ ← Message signing approval                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Message System (Message Protocol)

Why is message protocol this extension system's lifeline?

Because this extension doesn't rely on direct function calls, but is driven by cross-process messages.

Once message types, field semantics, or response contracts become messy, hardest-to-debug problems appear:

- Page seems to send request
- Background also received
- But keeper or approval page returned semantics already inconsistent

So in this type of system, message protocol itself is "interface standard."

All cross-process communication through standardized message type definitions:

```typescript
// packages/shared/src/types/messages.ts

// Auth-related messages
export enum AuthMessageTypes {
    AUTH_SUCCESS = "auth_success",
    AUTH_ERROR = "auth_error",
    EXT_LOGIN = "ext_login",
    REFRESH_TOKEN = "refresh_token",
}

// Vault (encryption container) messages
export enum VaultMessageTypes {
    UNLOCK_VAULT = "UNLOCK_VAULT",
    LOCK = "LOCK",
    CREATE_KEYPAIR = "CREATE_KEYPAIR",
    GET_PUBLIC_KEY = "GET_PUBLIC_KEY",
    ZK_EPH_SIGN_BYTES = "ZK_EPH_SIGN_BYTES",  // Sign with ephemeral private key
    SET_ZKPROOF = "SET_ZKPROOF",
    GET_ZKPROOF = "GET_ZKPROOF",
    CLEAR_ZKPROOF = "CLEAR_ZKPROOF",
}

// Wallet Standard related (dApp triggered)
export enum WalletStandardMessageTypes {
    SIGN_PERSONAL_MESSAGE = "sign_personal_message",
    SIGN_TRANSACTION = "sign_transaction",
    SIGN_AND_EXECUTE_TRANSACTION = "sign_and_execute_transaction",
    EVEFRONTIER_SIGN_SPONSORED_TRANSACTION = "sign_sponsored_transaction",
}

// Keeper security container messages
export enum KeeperMessageTypes {
    READY = "KEEPER_READY",
    CREATE_KEYPAIR = "KEEPER_CREATE_KEYPAIR",
    UNLOCK_VAULT = "KEEPER_UNLOCK_VAULT",
    GET_PUBLIC_KEY = "KEEPER_GET_KEY",
    EPH_SIGN = "KEEPER_EPH_SIGN",       // Ephemeral private key signing
    CLEAR_EPHKEY = "KEEPER_CLEAR_EPHKEY",
    SET_ZKPROOF = "KEEPER_SET_ZKPROOF",
    GET_ZKPROOF = "KEEPER_GET_ZKPROOF",
    CLEAR_ZKPROOF = "KEEPER_CLEAR_ZKPROOF",
}
```

### Message Flow: dApp Signing Request Complete Path

```
dApp calls wallet.signTransaction(tx)
    ↓ wallet-standard (same process)
injected.ts (EveVaultWallet.signTransaction)
    ↓ window.postMessage({ type: "sign_transaction", ... })
content.ts
    ↓ chrome.runtime.sendMessage(...)
background.ts (walletHandlers.ts)
    → Open sign_transaction approval window
    ← User clicks "Approve"
    → Send message to Keeper
    ↓ chrome.runtime Port
keeper.ts
    → Sign with ephemeral private key
    → Return ZK Proof + signature
    ↓ chrome.runtime Port
background.ts
    ↓ chrome.runtime.sendMessage
content.ts
    ↓ window.postMessage
injected.ts
    → Return SignedTransaction to dApp
```

---

## 4. Wallet Standard Implementation (SuiWallet.ts)

EVE Vault implements `@mysten/wallet-standard`'s `Wallet` interface, letting all dApps supporting Wallet Standard automatically discover it:

```typescript
// apps/extension/src/lib/adapters/SuiWallet.ts

export class EveVaultWallet implements Wallet {
    readonly #version = "1.0.0" as const;
    readonly #name = "Eve Vault" as const;

    // Supported Sui network chains
    get chains(): Wallet["chains"] {
        return [SUI_TESTNET_CHAIN, SUI_DEVNET_CHAIN] as `sui:${string}`[];
    }

    // Implemented Wallet Standard features
    get features() {
        return {
            [StandardConnect]: { connect: this.#connect },
            [StandardDisconnect]: { disconnect: this.#disconnect },
            [StandardEvents]: { on: this.#on },
            [SuiSignTransaction]: { signTransaction: this.#signTransaction },
            [SuiSignAndExecuteTransaction]: { signAndExecuteTransaction: this.#signAndExecuteTransaction },
            [SuiSignPersonalMessage]: { signPersonalMessage: this.#signPersonalMessage },
            // EVE Frontier proprietary extension feature
            [EVEFRONTIER_SPONSORED_TRANSACTION]: {
                signSponsoredTransaction: this.#signSponsoredTransaction,
            },
        };
    }
}
```

### Register to Page (injected.ts)

```typescript
// apps/extension/entrypoints/injected.ts
import { registerWallet } from "@mysten/wallet-standard";
import { EveVaultWallet } from "../src/lib/adapters/SuiWallet";

// Register immediately on page load
registerWallet(new EveVaultWallet());
```

dApps automatically discover `EveVaultWallet` through `@mysten/wallet-standard`'s `getWallets()`, no special integration needed.

---

## 5. Keeper: Security Key Container

Keeper is EVE Vault's most unique security design — ephemeral private key never leaves Keeper process memory:

```typescript
// apps/extension/entrypoints/keeper/keeper.ts

// Message types Keeper handles
switch (message.type) {
    case KeeperMessageTypes.CREATE_KEYPAIR:
        // Generate new Ed25519 ephemeral key pair
        // Private key only in memory, not written to chrome.storage
        break;

    case KeeperMessageTypes.EPH_SIGN:
        // Sign bytes with ephemeral private key
        // Only expose signature result, not private key
        break;

    case KeeperMessageTypes.CLEAR_EPHKEY:
        // Clear ephemeral private key in memory (lock operation)
        break;
}
```

**Security Guarantee**:
- Ephemeral private key = memory variable, not serialized to chrome.storage
- Browser closes or Keeper crashes → Private key auto-destroyed
- Re-unlock → Regenerate new ephemeral key pair
- Background/Popup cannot directly read private key, can only request signing through Port messages

Keeper's most important aspect isn't "mystery," but permission minimization.

It compresses most sensitive capability into very few things:

- Generate ephemeral key
- Sign with ephemeral key
- Clear ephemeral key

Beyond this, other layers try not to touch private key body.

---

## 6. Local Development Configuration

### Install Dependencies

```bash
# Recommend using Bun
bun install
```

### Configure .env

```bash
# apps/extension/.env
VITE_FUSION_SERVER_URL="https://auth.evefrontier.com"
VITE_FUSIONAUTH_CLIENT_ID=your-fusionauth-client-id
VITE_FUSION_CLIENT_SECRET=your-fusionauth-client-secret
VITE_ENOKI_API_KEY=your-enoki-api-key
EXTENSION_ID="your-extension-public-key"
```

### Start Development Mode

```bash
# Only run extension (recommended)
bun run dev:extension

# Run all apps (extension + web)
bun run dev
```

In development mode, WXT generates extension files in `apps/extension/.output/chrome-mv3/`, monitors file changes for auto-rebuild.

### Load Extension in Chrome

1. Open `chrome://extensions`
2. Enable "Developer mode" in top-right
3. Click "Load unpacked"
4. Select `apps/extension/.output/chrome-mv3/`

After each file change, Chrome auto-detects and prompts update (no manual reload needed).

---

## 7. Build Production Version

```bash
# Build Chrome extension
bun run build:extension
# Output: apps/extension/.output/chrome-mv3.zip

# Build all apps
bun run build

# Clear all cache (use when build time becomes slow)
bun run clean
```

---

## 8. FusionAuth OAuth Configuration

In FusionAuth console need to add following redirect URI (fixed format):

```
https://<extension-id>.chromiumapp.org/
```

Extension ID is Chrome-assigned unique identifier for extension (can be found on `chrome://extensions` page).

**Necessary OAuth scopes (Scopes)**:
- `openid` (get JWT format token)
- `profile` (get user info)
- `email` (user email)

---

## 9. Turborepo Build Cache

Project uses Turborepo to accelerate builds:

```bash
# turbo.json defines task parallel relationships
# build:extension depends on shared package build
bun run build:extension
# → First build packages/shared
# → Then build apps/extension (uses cache)

# Force rebuild (ignore cache)
bun run build --force
```

---

## 10. E2E Testing

```bash
# tests/e2e/ directory contains end-to-end tests like balance queries
bun run test:e2e

# Before testing need wallet logged in and test account configured
# tests/e2e/helpers/state.ts provides state management tools
```

---

## Chapter Summary

| Component | Layer | Function |
|------|-----|------|
| `injected.ts` | Page process | Register EveVaultWallet to Wallet Standard |
| `content.ts` | Content script | Message bridge: page ↔ Background |
| `background.ts` | Service Worker | OAuth, storage, request coordination |
| `keeper.ts` | Hidden container | Ephemeral private key's secure storage and use |
| `popup/` | Extension Page | User interface: login, address, balance |
| `sign_*/` | Extension Pages | Transaction/message approval UI |
| `SuiWallet.ts` | Adapter | Wallet Standard complete implementation |

> Next Chapter: **Future Outlook** — ZK proofs, full decentralization, and EVM interoperability possibilities for EVE Frontier and Sui ecosystem.
