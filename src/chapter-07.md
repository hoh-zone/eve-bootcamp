# Chapter 7：Move 进阶 — 泛型、动态字段与事件系统

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握 Move 中泛型编程、动态字段存储、Table/VecMap 数据结构和事件系统，能独立设计复杂的链上数据模型。

---

> 状态：设计进阶章节。正文以泛型、动态字段、事件和 Table/VecMap 为主。

## 前置依赖

- 建议先读 [Chapter 3](./chapter-03.md)
- 建议先读 [Chapter 6](./chapter-06.md)

## 源码位置

- [book/src/code/chapter-07](./code/chapter-07)

## 关键测试文件

- 当前目录以 `auction.move` 与片段为主；建议用本地 `sui move build` 做结构验证。

## 推荐阅读顺序

1. 先读泛型与动态字段
2. 再对照 [book/src/code/chapter-07](./code/chapter-07)
3. 最后把事件和数据结构映射到后续案例

## 验证步骤

1. 能说清何时用 Table、VecMap、动态字段
2. 能读懂 `auction.move` 的基本状态存储
3. 能识别事件适合承载什么信息

## 常见报错

- 把历史记录无限堆进单个对象，导致读写与 Gas 成本失控

---

## 7.1 泛型（Generics）

泛型让你的代码可以适用于多种类型，同时保持类型安全。这在 EVE Frontier 的 OwnerCap 中被广泛使用。

### 基础泛型语法

```move
// T 是类型参数，类似其他语言的 <T>
public struct Box<T: store> has key, store {
    id: UID,
    value: T,
}

// 泛型函数
public fun wrap<T: store>(value: T, ctx: &mut TxContext): Box<T> {
    Box { id: object::new(ctx), value }
}

public fun unwrap<T: store>(box: Box<T>): T {
    let Box { id, value } = box;
    id.delete();
    value
}
```

### Phantom 类型参数

`phantom T` 不真正持有 T 类型的值，只用于类型区分：

```move
// T 没有实际被使用，但创造了类型区分
public struct OwnerCap<phantom T> has key {
    id: UID,
    authorized_object_id: ID,
}

// 这两个是完全不同的类型，系统不会混淆
let gate_cap: OwnerCap<Gate> = ...;
let ssu_cap: OwnerCap<StorageUnit> = ...;
```

### 带约束的泛型

```move
// T 必须同时具有 key 和 store abilities
public fun transfer_to_object<T: key + store, Container: key>(
    container: &mut Container,
    value: T,
) { ... }

// T 必须具有 copy 和 drop（临时值，不是资产）
public fun log_value<T: copy + drop>(value: T) { ... }
```

---

## 7.2 动态字段（Dynamic Fields）

Sui 有一个强大特性：**动态字段（Dynamic Fields）**，允许在运行时向对象添加任意键值对，不需要在编译期定义所有字段。

### 为什么需要动态字段？

假设你的存储箱需要支持任意类型的物品，而物品类型在编译时未知：

```move
// ❌ 不灵活的方式：固定字段
public struct Inventory has key {
    id: UID,
    fuel: Option<u64>,
    ore: Option<u64>,
    // 新增物品类型就要修改合约...
}

// ✅ 灵活的方式：动态字段
public struct Inventory has key {
    id: UID,
    // 没有预定义字段，用动态字段存储
}
```

### 动态字段 API

```move
use sui::dynamic_field as df;
use sui::dynamic_object_field as dof;

// 添加动态字段（值不是对象类型）
df::add(&mut inventory.id, b"fuel_amount", 1000u64);

// 读取动态字段
let fuel: &u64 = df::borrow(&inventory.id, b"fuel_amount");
let fuel_mut: &mut u64 = df::borrow_mut(&mut inventory.id, b"fuel_amount");

// 检查是否存在
let exists = df::exists_(&inventory.id, b"fuel_amount");

// 移除动态字段
let old_value: u64 = df::remove(&mut inventory.id, b"fuel_amount");

// 动态对象字段（值本身是一个对象，有独立 ObjectID）
dof::add(&mut storage.id, item_type_id, item_object);
let item = dof::borrow<u64, Item>(&storage.id, item_type_id);
let item = dof::remove<u64, Item>(&mut storage.id, item_type_id);
```

### EVE Frontier 中的实际应用

存储单元的 **临时仓库（Ephemeral Inventory）** 就是用动态字段实现的：

```move
// 为特定角色创建临时仓库（以角色 OwnerCap ID 为 key）
df::add(
    &mut storage_unit.id,
    owner_cap_id,      // 用角色的 OwnerCap ID 作为 key
    EphemeralInventory::new(ctx),
);

// 角色访问自己的临时仓库
let my_inventory = df::borrow_mut<ID, EphemeralInventory>(
    &mut storage_unit.id,
    my_owner_cap_id,
);
```

---

## 7.3 Table 与 VecMap：链上集合类型

### Table：键值映射

```move
use sui::table::{Self, Table};

public struct Registry has key {
    id: UID,
    members: Table<address, MemberInfo>,
}

// 添加
table::add(&mut registry.members, member_addr, MemberInfo { ... });

// 查询
let info = table::borrow(&registry.members, member_addr);
let info_mut = table::borrow_mut(&mut registry.members, member_addr);

// 存在检查
let is_member = table::contains(&registry.members, member_addr);

// 移除
let old_info = table::remove(&mut registry.members, member_addr);

// 长度
let count = table::length(&registry.members);
```

> ⚠️ **注意**：Table 中的每个条目在链上都是一个独立的动态字段，每次访问都有单独的 cost。一个交易内最多访问 **1024 个动态字段**。

### VecMap：小规模有序映射

```move
use sui::vec_map::{Self, VecMap};

// VecMap 存储在对象字段中（不是动态字段），适合小数据集
public struct Config has key {
    id: UID,
    toll_settings: VecMap<u64, u64>,  // zone_id -> toll_amount
}

// 操作
vec_map::insert(&mut config.toll_settings, zone_id, amount);
let amount = vec_map::get(&config.toll_settings, &zone_id);
vec_map::remove(&mut config.toll_settings, &zone_id);
```

### 选择建议

| 场景 | 推荐类型 |
|------|---------|
| 大规模、动态增长的集合 | `Table` |
| 小于 100 条、需要遍历 | `VecMap` 或 `vector` |
| 以对象为值（有独立 ObjectID） | `dynamic_object_field` |
| 以简单值为值（u64, bool 等） | `dynamic_field` |

---

## 7.4 事件系统（Events）

事件是链上合约与链下应用通信的桥梁。事件不存储在链上状态中，但会附在交易记录里，可以被索引器（indexer）捕获。

### 定义和发射事件

```move
use sui::event;

// 事件结构体：只需要 copy + drop
public struct GateJumped has copy, drop {
    gate_id: ID,
    character_id: ID,
    destination_gate_id: ID,
    timestamp_ms: u64,
    toll_paid: u64,
}

public struct ItemSold has copy, drop {
    storage_unit_id: ID,
    seller: address,
    buyer: address,
    item_type_id: u64,
    price: u64,
}

// 在函数中发射事件
public fun process_purchase(
    storage_unit: &mut StorageUnit,
    buyer: &Character,
    payment: Coin<SUI>,
    item_type_id: u64,
    ctx: &mut TxContext,
): Item {
    let price = coin::value(&payment);
    // ... 处理购买逻辑 ...

    // 发射事件（无 gas 消耗差异，发射是免费的索引记录）
    event::emit(ItemSold {
        storage_unit_id: object::id(storage_unit),
        seller: storage_unit.owner_address,
        buyer: ctx.sender(),
        item_type_id,
        price,
    });

    // ... 返回物品 ...
}
```

### 在 TypeScript 中监听事件

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });

// 查询历史事件
const events = await client.queryEvents({
  query: {
    MoveEventType: `${MY_PACKAGE}::toll_gate_ext::GateJumped`,
  },
  limit: 50,
});

events.data.forEach(event => {
  const fields = event.parsedJson as {
    gate_id: string;
    character_id: string;
    toll_paid: string;
  };
  console.log(`跳跃: ${fields.character_id} 支付 ${fields.toll_paid}`);
});

// 实时订阅（WebSocket）
const unsubscribe = await client.subscribeEvent({
  filter: { Package: MY_PACKAGE },
  onMessage: (event) => {
    console.log("新事件:", event.type, event.parsedJson);
  },
});

// 停止订阅
setTimeout(() => unsubscribe(), 60_000);
```

### 用事件驱动 dApp 实时更新

```tsx
// src/hooks/useGateEvents.ts
import { useEffect, useState } from 'react'
import { SuiClient } from '@mysten/sui/client'

interface JumpEvent {
  gate_id: string
  character_id: string
  toll_paid: string
  timestamp_ms: string
}

export function useGateEvents(packageId: string) {
  const [events, setEvents] = useState<JumpEvent[]>([])

  useEffect(() => {
    const client = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })

    const subscribe = async () => {
      await client.subscribeEvent({
        filter: { MoveEventType: `${packageId}::toll_gate_ext::GateJumped` },
        onMessage: (event) => {
          setEvents(prev => [event.parsedJson as JumpEvent, ...prev.slice(0, 49)])
        },
      })
    }

    subscribe()
  }, [packageId])

  return events
}
```

---

## 7.5 动态字段 vs 事件的使用场景

| 需求 | 方案 |
|------|------|
| 持久化存储的集合数据 | 动态字段 / Table |
| 历史记录查询（不需要在合约中保留） | 事件 |
| 实时通知链下系统 | 事件 |
| 合约内部的状态检查 | 动态字段 |
| 分析统计数据（交易量、活跃用户） | 事件 + 链下索引 |

---

## 7.6 实战：设计一个可追踪的拍卖状态机

将本章知识整合，设计一个复杂的拍卖状态对象：

```move
module my_auction::auction;

use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::event;
use sui::clock::Clock;

/// 拍卖状态枚举（用 u8 表示）
const STATUS_OPEN: u8 = 0;
const STATUS_ENDED: u8 = 1;
const STATUS_CANCELLED: u8 = 2;

/// 拍卖对象
public struct Auction<phantom ItemType: key + store> has key {
    id: UID,
    status: u8,
    min_bid: u64,
    current_bid: u64,
    current_winner: Option<address>,
    end_time_ms: u64,
    bid_history_count: u64,
    // 竞价历史用动态字段存储（避免大对象）
}

/// 竞价事件
public struct BidPlaced has copy, drop {
    auction_id: ID,
    bidder: address,
    amount: u64,
    timestamp_ms: u64,
}

/// 竞价函数
public fun place_bid<T: key + store>(
    auction: &mut Auction<T>,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let bid_amount = coin::value(&payment);
    let now = clock.timestamp_ms();

    // 验证
    assert!(auction.status == STATUS_OPEN, EAuctionNotOpen);
    assert!(now < auction.end_time_ms, EAuctionEnded);
    assert!(bid_amount > auction.current_bid, EBidTooLow);

    // 退还前一位竞拍者的出价（简化版）
    // ...

    // 更新拍卖状态
    auction.current_bid = bid_amount;
    auction.current_winner = option::some(ctx.sender());

    // 记录竞价历史（用动态字段）
    let bid_key = auction.bid_history_count;
    auction.bid_history_count = bid_key + 1;
    df::add(&mut auction.id, bid_key, BidRecord {
        bidder: ctx.sender(),
        amount: bid_amount,
        timestamp_ms: now,
    });

    // 发射事件（供 dApp 实时显示）
    event::emit(BidPlaced {
        auction_id: object::id(auction),
        bidder: ctx.sender(),
        amount: bid_amount,
        timestamp_ms: now,
    });
}
```

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 泛型 | `<T>` 类型参数 + `phantom T` 类型区分 |
| 动态字段 | 运行时添加字段，`df::add/borrow/remove`，max 1024/tx |
| Table | 链上大规模 KV 存储，`table::add/borrow/contains` |
| VecMap | 小型有序 KV，存在字段里，适合配置表 |
| 事件 | `has copy + drop`，`event::emit()`，可被链下订阅 |
| 事件 vs 动态字段 | 临时通知用事件；持久状态用动态字段 |

## 📚 延伸阅读

- [Sui 动态字段文档](https://docs.sui.io/concepts/dynamic-fields)
- [Move Book：泛型](https://move-book.com/reference/generics.html)
- [Sui 事件文档](https://docs.sui.io/guides/developer/accessing-data/using-events)
- [inventory.move](https://github.com/evefrontier/world-contracts/blob/main/contracts/world/sources/primitives/inventory.move)
