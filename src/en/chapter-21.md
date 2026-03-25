# Chapter 21: Performance Optimization and Gas Minimization

> **Objective:** Master performance optimization techniques for on-chain operations, maximize off-chain computation, and build efficient, low-cost EVE Frontier applications through batching, object design optimization, and Gas budget control.

---

> Status: Engineering chapter. Main content focuses on Gas, batching, and object design optimization.

##  21.1 Gas Cost Model

Sui's Gas consists of two components:
```
Gas Fee = (Computation Units + Storage Delta) × Gas Price
```

- **Computation Units**: Move code execution consumption
- **Storage Delta**: Net increase in on-chain storage (new bytes charged, deleted bytes refunded)

**Key Insights**:
- Reading data is **free** (GraphQL/RPC reads don't go on-chain)
- Adding/removing dynamic fields has significant Gas cost
- Emitting events is almost free (doesn't occupy on-chain storage)

The easiest way to go wrong with Gas optimization is: many people immediately focus on "how to save a few units," without first seeing clearly:

> What's truly expensive is often not a particular line of code, but those things your entire state model forces the system to do repeatedly.

So performance optimization is best viewed in three layers:

- **Transaction Layer**
  Can this transaction be merged, is it doing many small actions repeatedly
- **Object Layer**
  Are your objects too large, too hot, too centralized
- **Architecture Layer**
  Which computations and aggregations shouldn't be on-chain at all

###  21.1.1 A Reusable Gas Comparison Record Template

This chapter easily becomes just slogans. It's recommended to record "before/after" data for at least one fixed set of operations:

| Operation | Inefficient Approach | Optimized Approach | Fields You Should Record |
|------|------|------|------|
| Two stargates online + link | 3 separate transactions | 1 PTB batch | `gasUsed`, object writes count, total time |
| Market create listing | Append to large object `vector` | Independent object or dynamic field | Object size, write count, storage rebate |
| History records | Persist to shared object | Emit event + off-chain indexing | Event count, object growth bytes |

> These numbers don't need to pursue "absolute standard values," but you must keep comparison records under the same environment, otherwise optimization conclusions have no persuasive power.

---

##  21.2 Batching: Do Multiple Things in One Transaction

Sui's Programmable Transaction Blocks (PTB) allow executing multiple Move calls in **one transaction**:

```typescript
// ❌ Inefficient: 3 separate transactions
await client.signAndExecuteTransaction({ transaction: tx_online }); // Online gate 1
await client.signAndExecuteTransaction({ transaction: tx_online }); // Online gate 2
await client.signAndExecuteTransaction({ transaction: tx_link });   // Link gates

// ✅ Efficient: 1 transaction completes all operations
const tx = new Transaction();

// Borrow OwnerCap (once)
const [ownerCap1, receipt1] = tx.moveCall({ target: `${PKG}::character::borrow_owner_cap`, ... });
const [ownerCap2, receipt2] = tx.moveCall({ target: `${PKG}::character::borrow_owner_cap`, ... });

// Execute all operations
tx.moveCall({ target: `${PKG}::gate::online`, arguments: [gate1, ownerCap1, ...] });
tx.moveCall({ target: `${PKG}::gate::online`, arguments: [gate2, ownerCap2, ...] });
tx.moveCall({ target: `${PKG}::gate::link`,   arguments: [gate1, gate2, ...] });

// Return OwnerCap
tx.moveCall({ target: `${PKG}::character::return_owner_cap`, arguments: [..., receipt1] });
tx.moveCall({ target: `${PKG}::character::return_owner_cap`, arguments: [..., receipt2] });

await client.signAndExecuteTransaction({ transaction: tx });
// Save 2/3 of base Gas fee!
```

###  21.2.1 How to Record a Real Gas Comparison

1. First fix inputs: same network, same object count, same batch of operations
2. Record inefficient version execution results: `digest`, `gasUsed`, write object count in `effects`
3. Then execute PTB version, record same fields
4. Organize results into a comparison table, write into your release or optimization notes

Recommended to record at least these fields:

```text
- digest
- computationCost
- storageCost
- storageRebate
- nonRefundableStorageFee
- changedObjects count
```

### PTB is not "merge everything you can"

Batching is powerful, but it's not best to blindly stuff all actions into one transaction.

Suitable for merging:

- Steps that are already strongly related
- Flows that must atomically succeed or fail together
- Operations borrowing the same type of permission object multiple times

Not necessarily suitable for over-merging:

- Stuffing too much unrelated logic into one transaction
- Hard to pinpoint problems once failure occurs
- Gas budget and computation become unpredictable

So PTB's goal is not "maximize length," but "converge a flow that should truly be atomic."

---

##  21.3 Object Design Optimization

### Principle One: Avoid Large Objects

```move
// ❌ Put all data in one object (max 250KB)
public struct BadMarket has key {
    id: UID,
    listings: vector<Listing>,     // Object grows as products increase
    bid_history: vector<BidRecord>, // History data grows infinitely
}

// ✅ Use dynamic fields or independent objects for distributed storage
public struct GoodMarket has key {
    id: UID,
    listing_count: u64,  // Only store counter
    // Specific Listing stored via dynamic fields: df::add(id, item_id, listing)
}
```

### Principle Two: Delete Objects No Longer Needed (Get Storage Rebate)

```move
// After auction ends, delete Listing to get Gas refund
public fun end_auction(auction: DutchAuction) {
    let DutchAuction { id, .. } = auction;
    id.delete(); // Delete object → storage rebate
}

// After claiming, delete DividendClaim object
public fun close_claim_record(record: DividendClaim) {
    let DividendClaim { id, .. } = record;
    id.delete();
}
```

### Principle Three: Use u8/u16 Instead of u64 for Small Integers

```move
// ❌ Waste space
public struct Config has key {
    id: UID,
    tier: u64,     // Only stores 1-5, but occupies 8 bytes
    status: u64,   // Only stores 0-3, but occupies 8 bytes
}

// ✅ Compact storage
public struct Config has key {
    id: UID,
    tier: u8,      // Only occupies 1 byte
    status: u8,    // Only occupies 1 byte
}
```

### Why is object design almost always the root cause of performance issues?

Because on Sui, performance and object model are tied together:

- Larger objects mean heavier reads/writes
- Hotter shared objects mean higher contention
- More centralized state means harder to scale

So many performance optimizations end up not "rewriting algorithms," but "refactoring object boundaries."

### A very practical criterion

As long as an object has both of these characteristics, you should start to be alert:

- Frequently written
- Still growing

Such objects will almost certainly become performance hotspots.

---

##  21.4 Off-Chain Computation, On-Chain Verification

**Golden Rule**: All computation that doesn't need enforcement should be done off-chain.

```move
// ❌ Sort on-chain (extremely Gas-consuming)
public fun get_top_bidders(auction: &Auction, n: u64): vector<address> {
    let mut sorted = vector::empty<BidRecord>();
    // ... O(n²) sorting, executed on-chain every time
}

// ✅ Store raw data on-chain, sort off-chain
public fun get_bid_at(auction: &Auction, index: u64): BidRecord {
    *df::borrow<u64, BidRecord>(&auction.id, index)
}
// dApp or backend reads all bids, sorts in memory, displays leaderboard
```

### Complex Routing Computation Done Off-Chain

```typescript
// Example: Stargate logistics routing (off-chain optimal path calculation)
function findOptimalRoute(
  start: string,
  end: string,
  gateGraph: Map<string, string[]>, // gate_id → [connected_gate_ids]
): string[] {
  // Dijkstra or other path algorithms, executed in dApp/backend
  // After calculating optimal path, only submit final jump operations on-chain
  return dijkstra(gateGraph, start, end);
}
```

### Off-chain computation is not cutting corners, but proper division of labor

Many things suitable for off-chain are essentially not "unimportant," but rather:

- Results need display, but don't need on-chain enforcement
- Algorithm is complex, but ultimately only need to submit a conclusion
- Can be recalculated, cached, replaced

If such work is forced on-chain, it only raises cost and failure surface together.

### When must you verify on-chain?

When results affect:

- Asset ownership
- Permission authorization
- Amount settlement
- Scarce resource allocation

Then you must put key conclusions back on-chain for verification, not just trust off-chain calculations.

---

##  21.5 Gas Budget Setting

```typescript
const tx = new Transaction();

// Set Gas budget cap (prevent unexpected excess consumption)
tx.setGasBudget(10_000_000); // 10 SUI cap

// Or use dryRun to estimate Gas
const estimate = await client.dryRunTransactionBlock({
  transactionBlock: await tx.build({ client }),
});
console.log("Estimated Gas:", estimate.effects.gasUsed);
```

### The most valuable part of `dryRun` is not "estimating a number," but discovering model issues early

If a transaction's dry run results already show:

- Many write objects
- Abnormally high storage cost
- Very little refund

That usually means the problem is not in the budget, but in the structure itself.

---

##  21.6 Parallel Execution: Contention-Free Shared Object Design

Sui can execute transactions operating on different objects in parallel. Contention for the same shared object causes sequential execution:

```
// ❌ All users contend for the same Market object
Market (shared) ← All purchase transactions need write lock → Sequential execution
(High traffic causes queue buildup, latency increases)

// ✅ Sharding design (multiple SubMarkets)
Market_Shard_0 (shared) ← Transactions where item type_id % 4 == 0
Market_Shard_1 (shared) ← Transactions where item type_id % 4 == 1
Market_Shard_2 (shared) ← Transactions where item type_id % 4 == 2
Market_Shard_3 (shared) ← Transactions where item type_id % 4 == 3
(4 shards execute in parallel, throughput ×4)
```

```move
// Shard routing
public fun buy_item_sharded(
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

### The most important question in concurrency design

Not "can it be parallel," but:

> In my business flow, which states must contend for the same shared object, and which can naturally be split?

For example, in a market system, common dimensions that can be split include:

- Item type
- Region
- Tenant
- Time bucket

As long as the split dimension is chosen correctly, throughput typically improves significantly.

### Sharding also has costs

Don't treat sharding as a free lunch. It brings:

- More complex query aggregation
- More complex routing logic
- Frontend and indexing layers need to know sharding rules

So sharding is a clear trade-off of "increasing system complexity for throughput," not the default option.

---

## 🔖 Chapter Summary

| Optimization Technique | Savings Ratio |
|--------|--------|
| PTB batching (merge multiple transactions) | 30-70% base fee |
| Off-chain computation, on-chain verification | Eliminate complex computation Gas |
| Delete obsolete objects | Get storage rebate |
| Compact data types (u8 vs u64) | Reduce object size |
| Shard shared objects | Increase concurrent throughput |

## 📚 Further Reading

- [Sui Gas Documentation](https://docs.sui.io/concepts/tokenomics/gas-in-sui)
- [PTB Programming Guide](https://docs.sui.io/concepts/transactions/prog-txn-blocks)
- [Sui Object Constraints](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
