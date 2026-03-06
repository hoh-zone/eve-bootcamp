# 实战案例 9：跨 Builder 协议聚合市场

> **目标：** 设计一个"协议适配器"层，让用户在一个 dApp 中同时访问多个不同 Builder 发布的市场合约（尽管它们接口各异），实现类似 DEX 聚合器的体验。

---

> 状态：教学示例。当前案例以聚合器架构和适配器分层为主，重点在统一接口而非单个 Move 合约。

## 对应代码目录

- [example-09/dapp](./code/example-09/dapp)

## 最小调用链

`前端查询多个市场 -> 适配器归一化报价 -> 选出最优市场 -> 按对应协议提交购买`

## 需求分析

**场景：** EVE Frontier 生态中已有 3 个不同 Builder 的市场合约：

| Builder | 合约地址 | 接口风格 |
|---------|---------|---------|
| Builder Alice | `0xAAA...` | `buy_item(market, character, item_id, coin)` |
| Builder Bob | `0xBBB...` | `purchase(storage, char, type_id, payment, ctx)` |
| 你（Builder You） | `0xYYY...` | `buy_item_v2(market, character, item_id, coin, clock, ctx)` |

玩家想买一件物品，需要查找哪个市场最便宜，并一键购买。

---

## 第一部分：链下适配器层（TypeScript）

由于不同合约接口不同，适配器在链下运行，将差异封装为统一接口：

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

// ── 适配器接口 ─────────────────────────────────────────────

export interface MarketAdapter {
  name: string
  packageId: string
  // 查询物品在该市场的价格
  getPrice(client: SuiClient, itemTypeId: number): Promise<number | null>
  // 构建购买交易
  buildBuyTx(
    tx: Transaction,
    itemTypeId: number,
    characterId: string,
    paymentCoin: any
  ): void
}

// ── 适配器 A：Builder Alice 的市场 ────────────────────────

export const AliceMarketAdapter: MarketAdapter = {
  name: "Alice's Market",
  packageId: "0xAAA...",

  async getPrice(client, itemTypeId) {
    // Alice 的市场用 Table 存储 listings，key 是 item_id
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

// ── 适配器 B：Builder Bob 的市场 ──────────────────────────

export const BobMarketAdapter: MarketAdapter = {
  name: "Bob's Depot",
  packageId: "0xBBB...",

  async getPrice(client, itemTypeId) {
    // Bob 的市场用不同的结构体，价格字段名为 'cost'
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

// ── 适配器 C：你自己的市场 ────────────────────────────────

export const MyMarketAdapter: MarketAdapter = {
  name: "Your Market",
  packageId: "0xYYY...",

  async getPrice(client, itemTypeId) {
    // 你的市场有完整文档，读取方式最直接
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
        tx.object("0x6"), // Clock（V2 多了这个参数）
      ],
    })
  },
}

// ── 聚合价格查询 ──────────────────────────────────────────

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
    .sort((a, b) => a.price - b.price) // 按价格升序
}
```

---

## 第二部分：聚合购买 dApp

```tsx
// src/AggregatedMarket.tsx
import { useState, useEffect } from 'react'
import { useConnection } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { useSuiClient } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { aggregatePrices, MyMarketAdapter, BobMarketAdapter, AliceMarketAdapter, MarketListing } from '../lib/marketAdapters'

const ADAPTERS_MAP = {
  [AliceMarketAdapter.packageId]: AliceMarketAdapter,
  [BobMarketAdapter.packageId]: BobMarketAdapter,
  [MyMarketAdapter.packageId]: MyMarketAdapter,
}

const ITEM_TYPES = [
  { id: 101, name: '稀有矿石' },
  { id: 102, name: '护盾模块' },
  { id: 103, name: '推进器' },
]

export function AggregatedMarket() {
  const { isConnected, handleConnect } = useConnection()
  const client = useSuiClient()
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
    if (!isConnected) { setStatus('请先连接钱包'); return }
    setStatus('⏳ 构建交易...')

    const tx = new Transaction()
    const priceMist = BigInt(Math.ceil(listing.price * 1e9))
    const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(priceMist)])

    const adapter = ADAPTERS_MAP[listing.marketId]
    adapter.buildBuyTx(tx, listing.itemTypeId, 'CHARACTER_ID', paymentCoin)

    try {
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ 购买成功！Tx: ${result.digest.slice(0, 12)}...`)
      searchListings(listing.itemTypeId) // 刷新
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="aggregated-market">
      <header>
        <h1>🛒 跨市场聚合器</h1>
        <p>实时比较多个 Builder 市场的价格，一键购买最低价</p>
        {!isConnected && <button onClick={handleConnect}>连接钱包</button>}
      </header>

      {/* 物品选择 */}
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

      {/* 价格列表 */}
      {loading && <div className="loading">🔍 查询各市场价格...</div>}

      {!loading && listings.length > 0 && (
        <div className="listings">
          <h3>
            {ITEM_TYPES.find(i => i.id === selectedItem)?.name} — 价格比较
            <span className="badge">最低价优先</span>
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
                {i === 0 && <span className="best-badge">最低</span>}
              </span>
              <button
                className="buy-btn"
                onClick={() => buyFromMarket(listing)}
                disabled={!isConnected}
              >
                立即购买
              </button>
            </div>
          ))}
        </div>
      )}

      {!loading && listings.length === 0 && selectedItem && (
        <div className="empty">所有市场均无此物品上架</div>
      )}

      {status && <div className="status">{status}</div>}
    </div>
  )
}
```

---

## 🎯 完整回顾

```
架构层次
├── 合约层：各 Builder 各自发布，接口不同
│   ├── Alice: buy_item(market, char, item_id, coin)
│   ├── Bob: purchase(storage, char, type_id, payment, ctx)
│   └── You: buy_item_v2(market, char, id, coin, clock, ctx)
│
├── 适配器层（TypeScript，链下）
│   ├── MarketAdapter 接口统一
│   ├── AliceMarketAdapter：封装 Alice 的读/写差异
│   ├── BobMarketAdapter：封装 Bob 的读/写差异
│   └── MyMarketAdapter：封装你自己的读/写
│
└── 聚合 dApp 层
    ├── aggregatePrices()：并行读取所有市场
    ├── 排序展示
    └── buyFromMarket()：调用对应适配器构建交易
```

## 🔧 扩展练习

1. **链上适配器注册**：在链上维护已认证适配器列表（防止恶意 Builder 以假价格骗取信任）
2. **滑点保护**：下单前再次验证链上最新价格，如变化超过 5% 则中止
3. **批量购买**：在一笔交易中同时从多个市场购买不同物品

---

## 📚 关联文档

- [Chapter 13：跨合约组合性](./chapter-13.md)
- [Chapter 12：链下索引](./chapter-12.md)
- [Chapter 18：全栈 dApp 架构](./chapter-18.md)
