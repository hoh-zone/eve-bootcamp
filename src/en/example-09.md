# Example 9: Cross-Builder Protocol Aggregator Market

> **Goal:** Design a "protocol adapter" layer allowing users to access multiple different Builder-published market contracts (despite varying interfaces) in one dApp, achieving DEX aggregator-like experience.

---

> Status: Teaching example. Current example focuses on aggregator architecture and adapter layering, emphasizing unified interfaces rather than individual Move contracts.

## Code Directory

- [example-09/dapp](./code/example-09/dapp)

## Minimal Call Chain

`Frontend queries multiple markets -> Adapter normalizes quotes -> Select optimal market -> Submit purchase per corresponding protocol`

## Requirements Analysis

**Scenario:** EVE Frontier ecosystem already has 3 different Builder market contracts:

| Builder | Contract Address | Interface Style |
|---------|---------|---------|
| Builder Alice | `0xAAA...` | `buy_item(market, character, item_id, coin)` |
| Builder Bob | `0xBBB...` | `purchase(storage, char, type_id, payment, ctx)` |
| You (Builder You) | `0xYYY...` | `buy_item_v2(market, character, item_id, coin, clock, ctx)` |

Players want to find which market has the cheapest item and buy with one click.

---

## Part 1: Off-Chain Adapter Layer (TypeScript)

Since different contracts have different interfaces, adapters run off-chain, encapsulating differences into a unified interface:

```typescript
// lib/marketAdapters.ts
import { Transaction } from "@mysten/sui/transactions"
import { SuiClient } from "@mysten/sui/client"

export interface MarketListing {
  marketId: string
  builder: string
  itemTypeId: number
  price: number        // SUI
  adapterName: string
}

// ── Adapter Interface ─────────────────────────────────────────────

export interface MarketAdapter {
  name: string
  packageId: string
  // Query item price in this market
  getPrice(client: SuiClient, itemTypeId: number): Promise<number | null>
  // Build purchase transaction
  buildBuyTx(
    tx: Transaction,
    itemTypeId: number,
    characterId: string,
    paymentCoin: any
  ): void
}

// ── Adapter A: Builder Alice's Market ────────────────────────

export const AliceMarketAdapter: MarketAdapter = {
  name: "Alice's Market",
  packageId: "0xAAA...",

  async getPrice(client, itemTypeId) {
    // Alice's market uses Table to store listings, key is item_id
    const obj = await client.getDynamicFieldObject({
      parentId: "0xAAA_MARKET_ID",
      name: { type: "u64", value: itemTypeId.toString() },
    })
    const fields = (obj.data?.content as any)?.fields
    return fields ? Number(fields.price) / 1e9 : null
  },

  buildBuyTx(tx, itemTypeId, characterId, paymentCoin) {
    tx.moveCall({
      target: `0xAAA...::market::buy_item`,
      arguments: [
        tx.object("0xAAA_MARKET_ID"),
        tx.object(characterId),
        tx.pure.u64(itemTypeId),
        paymentCoin,
      ],
    })
  },
}

// ── Adapter B: Builder Bob's Market ──────────────────────────

export const BobMarketAdapter: MarketAdapter = {
  name: "Bob's Depot",
  packageId: "0xBBB...",

  async getPrice(client, itemTypeId) {
    // Bob's market uses different struct, price field named 'cost'
    const obj = await client.getObject({
      id: "0xBBB_STORAGE_ID",
      options: { showContent: true },
    })
    const listings = (obj.data?.content as any)?.fields?.listings?.fields?.contents
    const found = listings?.find((e: any) => Number(e.fields?.key) === itemTypeId)
    return found ? Number(found.fields.value.fields.cost) / 1e9 : null
  },

  buildBuyTx(tx, itemTypeId, characterId, paymentCoin) {
    tx.moveCall({
      target: `0xBBB...::depot::purchase`,
      arguments: [
        tx.object("0xBBB_STORAGE_ID"),
        tx.object(characterId),
        tx.pure.u64(itemTypeId),
        paymentCoin,
      ],
    })
  },
}

// ── Adapter C: Your Own Market ────────────────────────────────

export const MyMarketAdapter: MarketAdapter = {
  name: "Your Market",
  packageId: "0xYYY...",

  async getPrice(client, itemTypeId) {
    // Your market has complete documentation, most straightforward reading
    const obj = await client.getDynamicFieldObject({
      parentId: "0xYYY_MARKET_ID",
      name: { type: "u64", value: itemTypeId.toString() },
    })
    const fields = (obj.data?.content as any)?.fields
    return fields ? Number(fields.value.fields.price) / 1e9 : null
  },

  buildBuyTx(tx, itemTypeId, characterId, paymentCoin) {
    tx.moveCall({
      target: `0xYYY...::market::buy_item_v2`,
      arguments: [
        tx.object("0xYYY_MARKET_ID"),
        tx.object(characterId),
        tx.pure.u64(itemTypeId),
        paymentCoin,
        tx.object("0x6"), // Clock (V2 adds this parameter)
      ],
    })
  },
}

// ── Aggregate Price Query ──────────────────────────────────────────

const ALL_ADAPTERS = [AliceMarketAdapter, BobMarketAdapter, MyMarketAdapter]

export async function aggregatePrices(
  client: SuiClient,
  itemTypeId: number,
): Promise<MarketListing[]> {
  const results = await Promise.all(
    ALL_ADAPTERS.map(async (adapter) => {
      const price = await adapter.getPrice(client, itemTypeId).catch(() => null)
      if (price === null) return null
      return {
        marketId: adapter.packageId,
        builder: adapter.name,
        itemTypeId,
        price,
        adapterName: adapter.name,
      } as MarketListing
    })
  )

  return results
    .filter((r): r is MarketListing => r !== null)
    .sort((a, b) => a.price - b.price) // Sort by price ascending
}
```

---

## Part 2: Aggregated Purchase dApp

```tsx
// src/AggregatedMarket.tsx
import { useState, useEffect } from 'react'
import { useConnection } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { useCurrentClient } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'
import { aggregatePrices, MyMarketAdapter, BobMarketAdapter, AliceMarketAdapter, MarketListing } from '../lib/marketAdapters'

const ADAPTERS_MAP = {
  [AliceMarketAdapter.packageId]: AliceMarketAdapter,
  [BobMarketAdapter.packageId]: BobMarketAdapter,
  [MyMarketAdapter.packageId]: MyMarketAdapter,
}

const ITEM_TYPES = [
  { id: 101, name: 'Rare Ore' },
  { id: 102, name: 'Shield Module' },
  { id: 103, name: 'Thruster' },
]

export function AggregatedMarket() {
  const { isConnected, handleConnect } = useConnection()
  const client = useCurrentClient()
  const dAppKit = useDAppKit()
  const [selectedItem, setSelectedItem] = useState<number | null>(null)
  const [listings, setListings] = useState<MarketListing[]>([])
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState('')

  const searchListings = async (itemTypeId: number) => {
    setSelectedItem(itemTypeId)
    setLoading(true)
    try {
      const results = await aggregatePrices(client, itemTypeId)
      setListings(results)
    } finally {
      setLoading(false)
    }
  }

  const buyFromMarket = async (listing: MarketListing) => {
    if (!isConnected) { setStatus('Please connect wallet first'); return }
    setStatus('⏳ Building transaction...')

    const tx = new Transaction()
    const priceMist = BigInt(Math.ceil(listing.price * 1e9))
    const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(priceMist)])

    const adapter = ADAPTERS_MAP[listing.marketId]
    adapter.buildBuyTx(tx, listing.itemTypeId, 'CHARACTER_ID', paymentCoin)

    try {
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ Purchase successful! Tx: ${result.digest.slice(0, 12)}...`)
      searchListings(listing.itemTypeId) // Refresh
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="aggregated-market">
      <header>
        <h1>🛒 Cross-Market Aggregator</h1>
        <p>Real-time compare prices across multiple Builder markets, buy at lowest price with one click</p>
        {!isConnected && <button onClick={handleConnect}>Connect Wallet</button>}
      </header>

      {/* Item Selection */}
      <div className="item-selector">
        {ITEM_TYPES.map(item => (
          <button
            key={item.id}
            className={`item-btn ${selectedItem === item.id ? 'selected' : ''}`}
            onClick={() => searchListings(item.id)}
          >
            {item.name}
          </button>
        ))}
      </div>

      {/* Price List */}
      {loading && <div className="loading">🔍 Querying market prices...</div>}

      {!loading && listings.length > 0 && (
        <div className="listings">
          <h3>
            {ITEM_TYPES.find(i => i.id === selectedItem)?.name} — Price Comparison
            <span className="badge">Lowest Price First</span>
          </h3>
          {listings.map((listing, i) => (
            <div
              key={listing.marketId}
              className={`listing-row ${i === 0 ? 'best-price' : ''}`}
            >
              <span className="rank">#{i + 1}</span>
              <span className="builder">{listing.builder}</span>
              <span className="price">
                {listing.price.toFixed(2)} SUI
                {i === 0 && <span className="best-badge">Lowest</span>}
              </span>
              <button
                className="buy-btn"
                onClick={() => buyFromMarket(listing)}
                disabled={!isConnected}
              >
                Buy Now
              </button>
            </div>
          ))}
        </div>
      )}

      {!loading && listings.length === 0 && selectedItem && (
        <div className="empty">No listings for this item in all markets</div>
      )}

      {status && <div className="status">{status}</div>}
    </div>
  )
}
```

---

## 🎯 Complete Review

```
Architecture Layers
├── Contract Layer: Each Builder publishes separately, different interfaces
│   ├── Alice: buy_item(market, char, item_id, coin)
│   ├── Bob: purchase(storage, char, type_id, payment, ctx)
│   └── You: buy_item_v2(market, char, id, coin, clock, ctx)
│
├── Adapter Layer (TypeScript, off-chain)
│   ├── MarketAdapter interface unified
│   ├── AliceMarketAdapter: Encapsulates Alice's read/write differences
│   ├── BobMarketAdapter: Encapsulates Bob's read/write differences
│   └── MyMarketAdapter: Encapsulates your own read/write
│
└── Aggregator dApp Layer
    ├── aggregatePrices(): Parallel read all markets
    ├── Sort and display
    └── buyFromMarket(): Call corresponding adapter to build transaction
```

## 🔧 Extension Exercises

1. **On-Chain Adapter Registry**: Maintain verified adapter list on-chain (prevent malicious Builders with fake prices to gain trust)
2. **Slippage Protection**: Verify latest on-chain price before order, abort if change exceeds 5%
3. **Batch Purchase**: Buy different items from multiple markets in one transaction

---

## 📚 Related Documentation

- [Chapter 15: Cross-Contract Composability](./chapter-15.md)
- [Chapter 9: Off-Chain Indexing](./chapter-09.md)
- [Chapter 19: Full-Stack dApp Architecture](./chapter-19.md)
