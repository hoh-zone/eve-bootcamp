# Chapter 21：性能优化与 Gas 最小化

> **目标：** 掌握链上操作的性能优化技巧，最大化利用链下计算，通过批处理、对象设计优化和 Gas 预算控制，构建高效低成本的 EVE Frontier 应用。

---

> 状态：工程章节。正文以 Gas、批处理和对象设计优化为主。

##  21.1 Gas 成本模型

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

Gas 优化最容易走偏的一点是：很多人一上来就盯着“怎么省几个单位”，却没先看清：

> 真正昂贵的，往往不是某一行代码，而是你整个状态模型迫使系统反复做的那些事。

所以性能优化最好分三层看：

- **交易层**
  这笔交易是否能合并、是否重复做了很多小动作
- **对象层**
  你的对象是否过大、过热、过于集中
- **架构层**
  哪些计算和聚合其实根本不该上链

###  21.1.1 一组可以复用的 Gas 对比记录模板

这一章最容易流于口号。建议至少拿一组固定操作记录“优化前/后”数据：

| 操作 | 低效写法 | 优化写法 | 你要记录的字段 |
|------|------|------|------|
| 两个星门上线 + 链接 | 3 笔独立交易 | 1 笔 PTB 批处理 | `gasUsed`、对象写入数、总耗时 |
| 市场创建挂单 | 大对象追加 `vector` | 独立对象或动态字段 | 对象大小、写入次数、存储退款 |
| 历史记录 | 持久化到共享对象 | 改发事件 + 链下索引 | 事件数、对象增长字节 |

> 这些数字不需要追求“绝对标准值”，但必须留下同环境下的对比记录，否则优化结论没有说服力。

---

##  21.2 批处理：一笔交易做多件事

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

###  21.2.1 如何记录一次真实 Gas 对比

1. 先固定输入：同一网络、同一对象数量、同一批操作
2. 记录低效版本的执行结果：`digest`、`gasUsed`、`effects` 中的写对象数
3. 再执行 PTB 版本，记录同样字段
4. 把结果整理成一张对比表，写进你的发布或优化笔记

推荐至少记录这些字段：

```text
- digest
- computationCost
- storageCost
- storageRebate
- nonRefundableStorageFee
- changedObjects count
```

### PTB 不是“能合就全合”

批处理很强，但也不是无脑把所有动作塞进一笔就最好。

适合合并的情况：

- 原本就强关联的步骤
- 必须原子成功或一起失败的流程
- 多次借用同类权限对象的操作

不一定适合过度合并的情况：

- 一笔交易里塞太多无关逻辑
- 一旦失败就很难定位问题
- Gas 预算和计算量开始变得不可预测

所以 PTB 的目标不是“最大化长度”，而是“收敛一条真正应该原子化的流程”。

---

##  21.3 对象设计优化

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

### 对象设计为什么几乎总是性能问题的根源？

因为在 Sui 上，性能和对象模型是绑在一起的：

- 对象越大，读写越重
- 共享对象越热，争用越高
- 状态越集中，扩展越难

所以很多性能优化，最后都不是在“重写算法”，而是在“重构对象边界”。

### 一个很实用的判断标准

只要一个对象同时具备下面两个特征，就要开始警惕：

- 经常被写
- 还在不断长大

这类对象几乎一定会成为性能热点。

---

##  21.4 链下计算，链上验证

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

### 链下计算不是偷懒，而是正确分工

很多适合链下做的事，本质上不是“不重要”，而是：

- 结果需要展示，但不需要链上强制执行
- 算法复杂，但最终只需提交一个结论
- 可重算、可缓存、可替换

这类工作如果硬放链上，只会把成本和失败面一起拉高。

### 什么时候必须链上验证？

当结果会影响：

- 资产归属
- 权限放行
- 金额结算
- 稀缺资源分配

就必须把关键结论放回链上验证，而不是只信链下算出来就算数。

---

##  21.5 Gas 预算设置

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

### `dryRun` 最值钱的地方，不是“估个数”，而是提前发现模型问题

如果一笔交易的 dry run 结果已经显示：

- 写对象很多
- 存储成本异常高
- 返还很少

那通常说明问题不在预算，而在结构本身。

---

##  21.6 并行执行：无争用的共享对象设计

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

### 并发设计里最该问的问题

不是“能不能并行”，而是：

> 我的业务流里，到底哪些状态必须争用同一个共享对象，哪些其实可以天然拆开？

比如市场系统里，常见可以拆开的维度包括：

- 物品类型
- 区域
- 租户
- 时间桶

只要拆分维度选对，吞吐量通常会明显提升。

### 分片也有代价

别把分片当成免费午餐。它会带来：

- 查询聚合更复杂
- 路由逻辑更复杂
- 前端和索引层要额外知道分片规则

所以分片是“为了吞吐而增加系统复杂度”的明确交换，不是默认选项。

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
- [Sui 对象限制](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
