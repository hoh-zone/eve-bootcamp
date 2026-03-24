# Chapter 5: dApp Front-End Development and Wallet Integration

> **Objective:** Use `@evefrontier/dapp-kit` to build a front-end dApp that can connect to EVE Vault wallet, read on-chain data, and execute transactions.

---

> Status: Foundation chapter. Main text focuses on wallet integration, front-end state reading, and transaction initiation.

## 5.1 The Role of dApp in EVE Frontier

After completing Move contract development, players need an interface to interact with your facilities. The dApp (decentralized application) is that interface, it can:

- Display real-time status of your smart assemblies (inventory, online status, etc.)
- Let players connect EVE Vault wallet
- Trigger on-chain transactions through UI (purchase items, apply for jump permits, etc.)
- Run in standard web browsers without downloading game client

### Two Usage Scenarios

| Scenario | Description |
|------|------|
| **In-Game Overlay** | When players approach assemblies in-game, game client displays your dApp (iframe) |
| **External Browser** | Independent webpage, connects wallet through EVE Vault extension |

Many people misunderstand dApps as "wrapping contracts with a front-end skin." In EVE Frontier, its more accurate role is:

> Turn on-chain facilities into service interfaces that players actually want to use.

Because for the same facility, if there's only a contract without a dApp, players usually lack these key pieces of information:

- What is the current state
- Do I have permission to operate
- How much does the operation cost
- What exactly happened after clicking the button

So dApps aren't just "presentation layer," they also bear three very practical responsibilities:

- **Explain state**
  Translate object fields into business states players can understand
- **Organize transactions**
  Help users assemble complex parameters, object IDs, amounts into a legal transaction
- **Handle feedback**
  Tell users whether they're currently waiting for signature, waiting for on-chain, success, failure, or need to retry

### A dApp's Minimum Working Loop

Regardless of whether you're making a shop, stargate, or turret console, front-ends basically can't avoid this loop:

```text
Connect wallet
  -> Read assembly and user state
  -> Determine currently allowed actions
  -> Build transaction
  -> Request signature / Initiate sponsored transaction
  -> Wait for result
  -> Refresh objects and interface
```

As long as one link in this loop isn't done well, user experience will break.

---

## 5.2 Installing dapp-kit

```bash
# Create React project (using Vite as example)
npx create-vite my-dapp --template react-ts
cd my-dapp

# Install EVE Frontier dApp SDK and dependencies
npm install @evefrontier/dapp-kit @tanstack/react-query react
```

### SDK Core Features Overview

| Feature | Provides |
|------|--------|
| 🔌 **Wallet Connection** | Integration with EVE Vault and standard Sui wallets |
| 📦 **Smart Object Data** | Get and transform assembly data through GraphQL |
| ⚡ **Sponsored Transactions** | Support gas-free transactions (backend pays) |
| 🔄 **Auto Polling** | Real-time refresh of on-chain data |
| 🎨 **Full TypeScript Types** | Complete type definitions for all components |

---

## 5.3 Project Basic Configuration

### Configure Provider

All dApp functionality must be wrapped in `EveFrontierProvider`:

```tsx
// src/main.tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { EveFrontierProvider } from '@evefrontier/dapp-kit'
import App from './App'

// React Query client (manage cache)
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 1000, // Refetch after 5 seconds
    }
  }
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {/* EVE Frontier SDK Provider */}
    <EveFrontierProvider queryClient={queryClient}>
      <App />
    </EveFrontierProvider>
  </React.StrictMode>
)
```

The role of `Provider` isn't just "making Hooks work." It actually helps you uniformly manage three types of contexts:

- Wallet connection context
- On-chain query and cache context
- dApp-kit's own environment information

So it's essentially the "operating platform" for the entire dApp. If this layer is misconfigured, many errors that seem like business problems later are actually context not initialized properly.

### Bind Assembly Through URL Parameters

dApp knows which assembly to display through URL parameters:

```
# In-game access:
https://your-dapp.com/?tenant=utopia&itemId=0x1234abcd...

# tenant: Game server instance name (prod/testnet/dev)
# itemId: Assembly's ObjectID on-chain
```

SDK automatically reads these parameters from URL, you don't need to handle manually.

The core idea here is:

> The same front-end page doesn't serve a fixed assembly, but dynamically binds current assembly context according to URL.

This has two direct benefits:

- You can reuse the same front-end to serve many facilities
- In-game overlay only needs to pass `tenant` and `itemId` in, page will know "who I'm serving now"

### Why Are `tenant` and `itemId` Both Essential?

- `itemId` solves "which object is it"
- `tenant` solves "which world instance it belongs to"

If only passing `itemId`, in multi-tenant or multi-environment scenarios, it's easy to read data from wrong world; if only passing `tenant`, you don't know which facility object it currently is.

---

## 5.4 Core Hooks Explained

### Hook 1: useConnection (Wallet Connection State)

```tsx
import { useConnection } from '@evefrontier/dapp-kit'

function WalletButton() {
  const {
    isConnected,          // boolean: whether wallet connected
    currentAddress,       // string | null: current wallet address
    handleConnect,        // () => void: trigger connection flow
    handleDisconnect,     // () => void: disconnect
  } = useConnection()

  if (!isConnected) {
    return (
      <button onClick={handleConnect} className="connect-btn">
        Connect EVE Vault Wallet
      </button>
    )
  }

  return (
    <div>
      <span>Connected: {currentAddress?.slice(0, 8)}...</span>
      <button onClick={handleDisconnect}>Disconnect</button>
    </div>
  )
}
```

`useConnection` solves not simply "can pop up wallet," but the first layer of state forking for the entire page:

- When wallet not connected, page can only show public information
- When wallet connected but no character, page might need to prompt to initialize identity first
- Only when wallet connected and has character, page can enter real interactive state

### Hook 2: useSmartObject (Current Assembly Data)

```tsx
import { useSmartObject } from '@evefrontier/dapp-kit'

function AssemblyStatus() {
  const {
    assembly,    // Current assembly's complete data (inventory, state, name, etc.)
    loading,     // Whether loading
    error,       // Error message
    refetch,     // Manual refresh
  } = useSmartObject()

  if (loading) return <div className="spinner">Reading on-chain data...</div>
  if (error) return <div className="error">Error: {error.message}</div>

  return (
    <div className="assembly-card">
      <h2>{assembly?.name}</h2>
      <p>Status: {assembly?.status}</p>
      <p>Owner: {assembly?.owner}</p>
    </div>
  )
}
```

What's most important here isn't the Hook name, but developing a habit:

> Pages should always center on "on-chain object state," not on local button state.

In other words, after users click buttons, don't just set `status = success` locally on front-end. A more stable approach is:

1. Wait for transaction to return
2. Re-read object
3. Refresh UI with on-chain true state

Otherwise you'll easily get:

- Front-end thinks it succeeded
- But on-chain object didn't change
- Page still shows "operation completed"

### Hook 3: useNotification (User Notifications)

```tsx
import { useNotification } from '@evefrontier/dapp-kit'

function ActionButton() {
  const { showNotification } = useNotification()

  const handleAction = async () => {
    try {
      // ... execute transaction ...
      showNotification({ type: 'success', message: 'Transaction successful!' })
    } catch (e) {
      showNotification({ type: 'error', message: 'Transaction failed: ' + e.message })
    }
  }

  return <button onClick={handleAction}>Execute Operation</button>
}
```

The true value of notification systems isn't "making a popup," but breaking on-chain asynchronous processes into stages users can understand:

- Connecting wallet
- Waiting for signature
- On-chain processing
- Confirmed
- Failed, need retry

If you only give users "success / failure," many complex transactions will seem like black boxes.

---

## 5.5 Executing On-Chain Transactions

### Standard Transaction (User Pays Gas)

Use `useDAppKit` from `@mysten/dapp-kit-react` to execute:

```tsx
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

function BuyItemButton({ storageUnitId, typeId }: Props) {
  const dAppKit = useDAppKit()

  const handleBuy = async () => {
    // Build transaction
    const tx = new Transaction()

    tx.moveCall({
      // Call your published extension contract function
      target: `${MY_PACKAGE_ID}::vending_machine::buy_item`,
      arguments: [
        tx.object(storageUnitId),
        tx.object(CHARACTER_ID),
        tx.splitCoins(tx.gas, [tx.pure.u64(100)]),  // Pay 100 SUI
        tx.pure.u64(typeId),
      ],
    })

    // Sign and execute
    try {
      const result = await dAppKit.signAndExecuteTransaction({
        transaction: tx,
      })
      console.log('Transaction successful!', result.digest)
    } catch (e) {
      console.error('Transaction failed', e)
    }
  }

  return <button onClick={handleBuy}>Buy Item</button>
}
```

### What Stages Does a Front-End Transaction Typically Split Into?

From front-end perspective, a transaction splits into at least 5 stages:

1. **Prepare parameters**
   Are assembly ID, character ID, amount, type parameters complete
2. **Build transaction**
   Assemble objects, pure values, coin split actions, and function entries into `Transaction`
3. **Request signature**
   Have wallet or sponsorship service confirm this transaction
4. **Submit execution**
   Transaction truly enters on-chain execution
5. **Write back to interface**
   Refresh UI based on digest and latest object state

Many front-end bugs don't occur at "transaction failed," but at steps 1 and 5:

- Parameters got wrong object
- Using old cache locally
- Transaction succeeded but page didn't refresh
- Have digest but object query not updated yet

### Sponsored Transaction (Sponsored Tx, Gas-Free)

When operation needs server verification or platform pays Gas:

```tsx
import { signAndExecuteSponsoredTransaction } from '@evefrontier/dapp-kit'

const result = await signAndExecuteSponsoredTransaction({
  transaction: tx,
  // SDK automatically handles sponsorship logic, communicates with EVE Frontier backend
})
```

Sponsored transactions have better experience, but longer chain. It typically means:

1. Front-end first builds transaction
2. Request backend to check if sponsorship allowed
3. Backend performs risk control / co-sign / pay
4. User completes necessary signature
5. Transaction then submitted for execution

So once sponsored transactions fail, when troubleshooting you can't just stare at front-end, need to distinguish which layer the problem is at:

- Front-end built transaction incorrectly
- User qualifications not met
- Backend refused sponsorship
- Wallet signature stage failed
- On-chain execution itself failed

---

## 5.6 Reading On-Chain Data (GraphQL)

```typescript
import {
  getAssemblyWithOwner,
  getObjectWithJson,
  executeGraphQLQuery,
} from '@evefrontier/dapp-kit'

// Get assembly and its owner information
async function loadAssembly(assemblyId: string) {
  const { moveObject, character } = await getAssemblyWithOwner(assemblyId)
  console.log('Assembly data:', moveObject)
  console.log('Owner character:', character)
}

// Custom GraphQL query
async function queryGates() {
  const query = `
    query GetGates($type: String!) {
      objects(filter: { type: $type }, first: 10) {
        nodes {
          address
          asMoveObject { contents { json } }
        }
      }
    }
  `
  const data = await executeGraphQLQuery(query, {
    type: `${WORLD_PACKAGE}::gate::Gate`
  })
  return data
}
```

### Why Can't Front-End Only Rely on Event Streams?

Because front-end pages typically need "current state," not just "what historically happened."

Events are better suited to answer:

- Who did what when
- Whether a certain action occurred
- Used for logs, notifications, timelines

Object queries are better suited to answer:

- What is this facility's state now
- How much current inventory remains
- Who is current owner
- Whether currently online

So mature dApps are often:

- Use object queries to get current state
- Use event queries to supplement history and timeline

Only relying on events to restore current state usually becomes increasingly fragile.

---

## 5.7 Practical Utility Functions

```typescript
import {
  abbreviateAddress,
  isOwner,
  formatM3,
  formatDuration,
  getTxUrl,
  getDatahubGameInfo,
} from '@evefrontier/dapp-kit'

// Shorten address: 0x1234...cdef
abbreviateAddress('0x1234567890abcdef')

// Check if currently connected wallet is specified object's owner
const isMine = isOwner(assembly, currentAddress)

// Format volume
formatM3(1500)  // "1.5 m³"

// Format time
formatDuration(3661000)  // "1h 1m 1s"

// Get transaction browser link
getTxUrl('HNFaf...')  // Returns Sui Explorer URL

// Get game item metadata (name, icon, etc.)
const info = await getDatahubGameInfo(83463)
console.log(info.name, info.iconUrl)
```

These utility functions seem like scraps, but they directly determine whether your front-end will seem "like a product rather than a script page."

For example:

- Addresses not abbreviated, page becomes hard to read
- Amounts and volumes not formatted, players have difficulty judging quickly
- No transaction links, when problems occur users and developers can't track

Front-end product feel is often piled up by these small functions.

---

## 5.8 Complete dApp Example

```tsx
// src/App.tsx
import { useConnection, useSmartObject, useNotification } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

export default function App() {
  const { isConnected, handleConnect, currentAddress } = useConnection()
  const { assembly, loading } = useSmartObject()
  const { showNotification } = useNotification()
  const dAppKit = useDAppKit()

  const handleJump = async () => {
    if (!isConnected) {
      showNotification({ type: 'warning', message: 'Please connect wallet first' })
      return
    }

    const tx = new Transaction()
    tx.moveCall({
      target: `${MY_PACKAGE}::toll_gate::pay_and_jump`,
      arguments: [
        tx.object(GATE_ID),
        tx.object(DEST_GATE_ID),
        tx.object(CHARACTER_ID),
        tx.splitCoins(tx.gas, [tx.pure.u64(100)]),
      ],
    })

    try {
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      showNotification({ type: 'success', message: 'Jump successful!' })
    } catch (e: any) {
      showNotification({ type: 'error', message: e.message })
    }
  }

  if (loading) return <div>Loading...</div>

  return (
    <div className="app">
      <header>
        <h1>🌀 Stargate Console</h1>
        {!isConnected
          ? <button onClick={handleConnect}>Connect Wallet</button>
          : <span>✅ {currentAddress?.slice(0, 8)}...</span>
        }
      </header>

      <main>
        <div className="gate-info">
          <h2>{assembly?.name ?? 'Unknown Gate'}</h2>
          <p>Status: {assembly?.status}</p>
        </div>

        <button
          className="jump-btn"
          onClick={handleJump}
          disabled={!isConnected}
        >
          💳 Pay 100 SUI and Jump
        </button>
      </main>
    </div>
  )
}
```

Although this example is simple, it has completely demonstrated a minimal interaction loop:

- Connect wallet
- Read current assembly
- Build transaction
- Request signature and execute
- Give result notification

### In Real Projects Usually Need to Add Three More Layers of State

Example works, but if you want to make it a stable product, usually need to add:

1. **Local UI state**
   For example button loading, modal open/close, form input
2. **Wallet state**
   Current address, whether authorized, whether switched to wrong network
3. **On-chain object state**
   Facility state, inventory, price, current owner

Don't mix these three layers of state into one layer. They update at different speeds, have different reliability, different troubleshooting methods.

---

## 5.9 Embedding dApp in Game

When approaching your assembly in-game, client will load your registered dApp URL in an overlay. Configuration method:

1. Deploy dApp to public URL (like Vercel, Netlify)
2. Set your dApp URL in assembly configuration
3. Game client will automatically open and pass in `?itemId=...&tenant=...` parameters when players interact

Related documentation: [Connecting In-Game](https://github.com/evefrontier/builder-documentation/blob/main/dapps/connecting-in-game.md) | [Customizing External dApps](https://github.com/evefrontier/builder-documentation/blob/main/dapps/customizing-external-dapps.md)

### Biggest Difference Between In-Game Overlay and External Browser

Although both are called dApps, runtime constraints aren't completely the same:

- **In-Game Overlay**
  More like embedded page controlled by host environment, focus is fast, stable, clear parameters, short interaction path
- **External Browser**
  More like independent Web application, can accommodate more complete page structure and longer interaction processes

So when making in-game dApps, usually need extra attention to:

- Page first screen must be fast
- Can't rely on too complex multi-page jumps
- When parameters lost need fallback prompts
- When wallet not connected, character not initialized, facility not online, need clear state pages

---

## 🔖 Chapter Summary

| Knowledge Point | Core Points |
|--------|--------|
| Provider Configuration | `<EveFrontierProvider>` wraps entire application |
| URL Parameters | `?tenant=&itemId=` binds on-chain assembly |
| `useConnection` | Wallet connection state and operations |
| `useSmartObject` | Auto-polling assembly on-chain data |
| Execute Transaction | `dAppKit.signAndExecuteTransaction()` |
| Sponsored Transaction | `signAndExecuteSponsoredTransaction()` gas-free |
| Read Data | GraphQL / `getAssemblyWithOwner()` |

## 📚 Extended Reading

- [dapp-kit Complete Documentation](https://github.com/evefrontier/builder-documentation/blob/main/dapp-kit/dapp-kit.md)
- [TypeDoc API Documentation](http://sui-docs.evefrontier.com/)
- [Connecting from an External Browser](https://github.com/evefrontier/builder-documentation/blob/main/dapps/connecting-from-an-external-browser.md)
- [@mysten/dapp-kit-react Documentation](https://sdk.mystenlabs.com/dapp-kit)
