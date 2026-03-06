# Chapter 17：性能优化与 Gas 最小化

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握链上操作的性能优化技巧，最大化利用链下计算，通过批处理、对象设计优化和 Gas 预算控制，构建高效低成本的 EVE Frontier 应用。

---

## 17.1 Gas 成本模型

Sui 的 Gas 由两部分组成：
```
Gas 费 = (计算单元 + 存储差额) × Gas 价格
```

- **计算单元**：Move 代码执行消耗
- **存储差额**：链上存储的净增量（新增字节收费，删除字节退款）

**关键洞察**：
- 读取数据是**免费的**（GraphQL/RPC 读取不上链）
- 动态字段的增删有显著 Gas 成本
- 发射事件几乎免费（不占用链上存储）

---

## 17.2 批处理：一笔交易做多件事

Sui 的可编程交易块（PTB）允许在**一笔交易**中执行多个 Move 调用：

```typescript
// ❌ 低效：3 笔单独交易
await client.signAndExecuteTransaction({ transaction: tx_online }); // 上线星门1
await client.signAndExecuteTransaction({ transaction: tx_online }); // 上线星门2  
await client.signAndExecuteTransaction({ transaction: tx_link });   // 链接星门

// ✅ 高效：1 笔交易完成所有操作
const tx = new Transaction();

// 借用 OwnerCap（一次）
const [ownerCap1, receipt1] = tx.moveCall({ target: `${PKG}::character::borrow_owner_cap`, ... });
const [ownerCap2, receipt2] = tx.moveCall({ target: `${PKG}::character::borrow_owner_cap`, ... });

// 执行所有操作
tx.moveCall({ target: `${PKG}::gate::online`, arguments: [gate1, ownerCap1, ...] });
tx.moveCall({ target: `${PKG}::gate::online`, arguments: [gate2, ownerCap2, ...] });
tx.moveCall({ target: `${PKG}::gate::link`,   arguments: [gate1, gate2, ...] });

// 归还 OwnerCap
tx.moveCall({ target: `${PKG}::character::return_owner_cap`, arguments: [..., receipt1] });
tx.moveCall({ target: `${PKG}::character::return_owner_cap`, arguments: [..., receipt2] });

await client.signAndExecuteTransaction({ transaction: tx });
// 节省 2/3 的 Gas 基础费！
```

---

## 17.3 对象设计优化

### 原则一：避免大对象

```move
// ❌ 把所有数据放在一个对象（最大 250KB）
public struct BadMarket has key {
    id: UID,
    listings: vector<Listing>,     // 随商品增多，对象越来越大
    bid_history: vector<BidRecord>, // 历史数据无限增长
}

// ✅ 用动态字段或独立对象分散存储
public struct GoodMarket has key {
    id: UID,
    listing_count: u64,  // 只存计数器
    // 具体 Listing 用动态字段存储：df::add(id, item_id, listing)
}
```

### 原则二：删除不再需要的对象（获取存储退款）

```move
// 拍卖结束后，删除 Listing 获得 Gas 退款
public entry fun end_auction(auction: DutchAuction) {
    let DutchAuction { id, .. } = auction;
    id.delete(); // 删除对象 → 存储退款
}

// 领取完毕后，删除 DividendClaim 对象
public entry fun close_claim_record(record: DividendClaim) {
    let DividendClaim { id, .. } = record;
    id.delete();
}
```

### 原则三：用 u8/u16 代替 u64 存储小整数

```move
// ❌ 浪费空间
public struct Config has key {
    id: UID,
    tier: u64,     // 只存 1-5，但占 8 字节
    status: u64,   // 只存 0-3，但占 8 字节
}

// ✅ 紧凑存储
public struct Config has key {
    id: UID,
    tier: u8,      // 只占 1 字节
    status: u8,    // 只占 1 字节
}
```

---

## 17.4 链下计算，链上验证

**黄金法则**：所有不需要强制执行的计算，都放到链下做。

```move
// ❌ 在链上排序（极度消耗 Gas）
public fun get_top_bidders(auction: &Auction, n: u64): vector<address> {
    let mut sorted = vector::empty<BidRecord>();
    // ... O(n²) 排序，每次都在链上执行
}

// ✅ 链上只存原始数据，链下排序
public fun get_bid_at(auction: &Auction, index: u64): BidRecord {
    *df::borrow<u64, BidRecord>(&auction.id, index)
}
// dApp 或后端读取所有竞价，在内存中排序，展示排行榜
```

### 复杂路由计算在链下完成

```typescript
// Example: 星门物流路由（链下计算最优路径）
function findOptimalRoute(
  start: string,
  end: string,
  gateGraph: Map<string, string[]>, // gate_id → [connected_gate_ids]
): string[] {
  // Dijkstra 等路径算法，在 dApp/后端执行
  // 计算出最优路径后，只把最终跳跃操作提交上链
  return dijkstra(gateGraph, start, end);
}
```

---

## 17.5 Gas 预算设置

```typescript
const tx = new Transaction();

// 设置 Gas 预算上限（防止意外超额消耗）
tx.setGasBudget(10_000_000); // 10 SUI上限

// 或使用 dryRun 预估 Gas
const estimate = await client.dryRunTransactionBlock({
  transactionBlock: await tx.build({ client }),
});
console.log("预估 Gas:", estimate.effects.gasUsed);
```

---

## 17.6 并行执行：无争用的共享对象设计

Sui 可以并行执行操作不同对象的交易。争用同一共享对象会导致顺序执行：

```
// ❌ 所有用户都争用同一个 Market 对象
Market (shared) ← 所有购买交易都需要写锁 → 顺序执行
（高流量时，队列堆积，延迟上升）

// ✅ 分片设计（多个 SubMarket）
Market_Shard_0 (shared) ← 物品 type_id % 4 == 0 的交易
Market_Shard_1 (shared) ← 物品 type_id % 4 == 1 的交易
Market_Shard_2 (shared) ← 物品 type_id % 4 == 2 的交易
Market_Shard_3 (shared) ← 物品 type_id % 4 == 3 的交易
（4 个分片并行执行，吞吐量 ×4）
```

```move
// 分片路由
public entry fun buy_item_sharded(
    shards: &mut vector<MarketShard>,
    item_type_id: u64,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    let shard_index = item_type_id % vector::length(shards);
    let shard = vector::borrow_mut(shards, shard_index);
    buy_from_shard(shard, item_type_id, payment, ctx);
}
```

---

## 🔖 本章小结

| 优化技巧 | 节省比例 |
|--------|--------|
| PTB 批处理（合并多笔交易） | 30-70% 基础费 |
| 链下计算，链上验证 | 消除复杂计算 Gas |
| 删除废弃对象 | 获得存储退款 |
| 紧凑数据类型（u8 vs u64） | 减小对象尺寸 |
| 分片共享对象 | 提升并发吞吐量 |

## 📚 延伸阅读

- [Sui Gas 文档](https://docs.sui.io/concepts/tokenomics/gas-in-sui)
- [PTB 编程指南](https://docs.sui.io/concepts/transactions/prog-txn-blocks)
- [Sui 对象限制](../welcome/contstraints.md)
