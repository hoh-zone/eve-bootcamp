# 实战案例 7：星门物流网络（多跳路由系统）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 构建一个联盟拥有多个星门的物流网络，支持"A → B → C"多跳路由，链下计算最优路径，链上原子执行多次跳跃；并提供路由规划 dApp。

---

> 状态：教学示例。正文聚焦多跳路由和链下规划，完整目录以 `book/src/code/example-07/` 为准。

## 前置依赖

- 建议先读 [Chapter 12](./chapter-12.md)、[Chapter 17](./chapter-17.md)
- 需要本地 `sui` CLI 与 `pnpm`

## 对应代码目录

- [example-07](./code/example-07)
- [example-07/dapp](./code/example-07/dapp)

## 源码位置

- [Move.toml](./code/example-07/Move.toml)
- [multi_hop.move](./code/example-07/sources/multi_hop.move)
- [dapp/readme.md](./code/example-07/dapp/readme.md)

## 关键测试文件

- [tests/README.md](./code/example-07/tests/README.md)

## 推荐阅读顺序

1. 先看 `multi_hop.move` 的路径执行模型
2. 再理解链下如何算最优路径
3. 最后启动 dApp 对照多跳路线展示

## 最小调用链

`链下计算最优路由 -> 构建多跳 PTB -> 链上原子执行所有跳跃 -> 全部成功或全部回滚`

## 验证步骤

1. 在 [example-07](./code/example-07) 运行 `sui move build`
2. 在 [example-07/dapp](./code/example-07/dapp) 运行 `pnpm install && pnpm dev`
3. 按测试矩阵验证原子执行和失败回滚

## 常见报错

- 链下算出的路径和链上执行顺序不一致
- 多跳过程拆成多笔交易，失去原子性

---

## 需求分析

**场景：** 你的联盟控制着 5 个互联星门，形成如下拓扑：

```
Mining Area ──[Gate1]──► Hub Alpha ──[Gate2]──► Trade Hub
                              │
                         [Gate3]
                              │
                         Refinery ──[Gate4]──► Manufacturing
                              │
                         [Gate5]
                              │
                         Safe Harbor
```

**要求：**
- 玩家可以一次性购买"多跳通行证"，完成 A→Hub Alpha→Trade Hub 这样的复合路由
- 路由计算在链下进行（节省 Gas）
- 链上原子执行：要么全部跳跃成功，要么全部回滚
- dApp 提供可视化路线规划器

---

## 第一部分：多跳路由合约

```move
module logistics::multi_hop;

use world::gate::{Self, Gate};
use world::character::Character;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::clock::Clock;
use sui::object::{Self, ID};
use sui::event;

public struct LogisticsAuth has drop {}

/// 一次购买多跳路线
public entry fun purchase_route(
    source_gate: &Gate,
    hop1_dest: &Gate,       // 第一跳目的
    hop2_source: &Gate,     // 第二跳起点（= hop1_dest 的链接门）
    hop2_dest: &Gate,       // 第二跳目的
    character: &Character,
    mut payment: Coin<SUI>,  // 支付两跳的总费用
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 验证路线连续性：hop1_dest 和 hop2_source 必须是链接的星门
    assert!(
        gate::are_linked(hop1_dest, hop2_source),
        ERouteDiscontinuous,
    );

    // 计算并扣除每跳费用
    let hop1_toll = get_toll(source_gate);
    let hop2_toll = get_toll(hop2_source);
    let total_toll = hop1_toll + hop2_toll;

    assert!(coin::value(&payment) >= total_toll, EInsufficientPayment);

    // 退还找零
    let change = payment.split(coin::value(&payment) - total_toll, ctx);
    if coin::value(&change) > 0 {
        transfer::public_transfer(change, ctx.sender());
    } else { coin::destroy_zero(change); }

    // 发放两个 JumpPermit（1小时有效期）
    let expires = clock.timestamp_ms() + 60 * 60 * 1000;

    gate::issue_jump_permit(
        source_gate, hop1_dest, character, LogisticsAuth {}, expires, ctx,
    );
    gate::issue_jump_permit(
        hop2_source, hop2_dest, character, LogisticsAuth {}, expires, ctx,
    );

    // 扣除收费
    let hop1_coin = payment.split(hop1_toll, ctx);
    let hop2_coin = payment;
    collect_toll(source_gate, hop1_coin, ctx);
    collect_toll(hop2_source, hop2_coin, ctx);

    event::emit(RouteTicketIssued {
        character_id: object::id(character),
        gates: vector[object::id(source_gate), object::id(hop1_dest), object::id(hop2_dest)],
        total_toll,
    });
}

/// 通用 N 跳路由（接受可变长度路线）
public entry fun purchase_route_n_hops(
    gates: vector<&Gate>,          // 星门列表 [A, B, C, D, ...]
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let n = vector::length(&gates);
    assert!(n >= 2, ETooFewGates);
    assert!(n <= 6, ETooManyHops); // 防止超大交易

    // 验证路线连续性（每对相邻目的/起点必须链接）
    let mut i = 1;
    while (i < n - 1) {
        assert!(
            gate::are_linked(vector::borrow(&gates, i), vector::borrow(&gates, i)),
            ERouteDiscontinuous,
        );
        i = i + 1;
    };

    // 计算总费用
    let mut total: u64 = 0;
    let mut j = 0;
    while (j < n - 1) {
        total = total + get_toll(vector::borrow(&gates, j));
        j = j + 1;
    };

    assert!(coin::value(&payment) >= total, EInsufficientPayment);

    // 发放所有 Permit
    let expires = clock.timestamp_ms() + 60 * 60 * 1000;
    let mut k = 0;
    while (k < n - 1) {
        gate::issue_jump_permit(
            vector::borrow(&gates, k),
            vector::borrow(&gates, k + 1),
            character,
            LogisticsAuth {},
            expires,
            ctx,
        );
        k = k + 1;
    };

    // 退款找零
    let change = payment.split(coin::value(&payment) - total, ctx);
    if coin::value(&change) > 0 {
        transfer::public_transfer(change, ctx.sender());
    } else { coin::destroy_zero(change); }
    // 处理 payment 到各个星门金库...
}

fun get_toll(gate: &Gate): u64 {
    // 从星门的扩展数据读取通行费（动态字段）
    // 简化版：固定费率
    10_000_000_000 // 10 SUI
}

fun collect_toll(gate: &Gate, coin: Coin<SUI>, ctx: &TxContext) {
    // 将 coin 转到星门对应的 Treasury
    // ...
}

public struct RouteTicketIssued has copy, drop {
    character_id: ID,
    gates: vector<ID>,
    total_toll: u64,
}

const ERouteDiscontinuous: u64 = 0;
const EInsufficientPayment: u64 = 1;
const ETooFewGates: u64 = 2;
const ETooManyHops: u64 = 3;
```

---

## 第二部分：链下路径规划（Dijkstra）

```typescript
// lib/routePlanner.ts

interface Gate {
  id: string
  name: string
  linkedGates: string[]  // 链接的星门 ID 列表
  tollAmount: number     // 通行费（SUI）
}

interface Route {
  gateIds: string[]
  totalToll: number
  hops: number
}

// Dijkstra 最短路径（以通行费为权重）
export function findCheapestRoute(
  gateMap: Map<string, Gate>,
  fromId: string,
  toId: string,
): Route | null {
  const dist = new Map<string, number>()
  const prev = new Map<string, string | null>()
  const unvisited = new Set(gateMap.keys())

  for (const id of gateMap.keys()) {
    dist.set(id, Infinity)
    prev.set(id, null)
  }
  dist.set(fromId, 0)

  while (unvisited.size > 0) {
    // 找距离最小的未访问节点
    let current: string | null = null
    let minDist = Infinity
    for (const id of unvisited) {
      if ((dist.get(id) ?? Infinity) < minDist) {
        minDist = dist.get(id)!
        current = id
      }
    }

    if (!current || current === toId) break
    unvisited.delete(current)

    const gate = gateMap.get(current)!
    for (const neighborId of gate.linkedGates) {
      const neighbor = gateMap.get(neighborId)
      if (!neighbor || !unvisited.has(neighborId)) continue

      const newDist = (dist.get(current) ?? 0) + neighbor.tollAmount
      if (newDist < (dist.get(neighborId) ?? Infinity)) {
        dist.set(neighborId, newDist)
        prev.set(neighborId, current)
      }
    }
  }

  if (dist.get(toId) === Infinity) return null // 不可达

  // 重建路径
  const path: string[] = []
  let cur: string | null = toId
  while (cur) {
    path.unshift(cur)
    cur = prev.get(cur) ?? null
  }

  return {
    gateIds: path,
    totalToll: dist.get(toId) ?? 0,
    hops: path.length - 1,
  }
}
```

---

## 第三部分：路由规划 dApp

```tsx
// src/RoutePlannerApp.tsx
import { useState, useEffect } from 'react'
import { useConnection } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { findCheapestRoute } from '../lib/routePlanner'
import { Transaction } from '@mysten/sui/transactions'

const LOGISTICS_PKG = "0x_LOGISTICS_PACKAGE_"

// 星门网络拓扑（通常从链上读取）
const GATE_NETWORK = new Map([
  ['gate_mining', { id: 'gate_mining', name: '矿区入口', linkedGates: ['gate_hub_alpha'], tollAmount: 5 }],
  ['gate_hub_alpha', { id: 'gate_hub_alpha', name: 'Hub Alpha', linkedGates: ['gate_mining', 'gate_trade', 'gate_refinery'], tollAmount: 3 }],
  ['gate_trade', { id: 'gate_trade', name: '贸易中心', linkedGates: ['gate_hub_alpha'], tollAmount: 8 }],
  ['gate_refinery', { id: 'gate_refinery', name: '精炼厂', linkedGates: ['gate_hub_alpha', 'gate_manufacturing', 'gate_harbor'], tollAmount: 4 }],
  ['gate_manufacturing', { id: 'gate_manufacturing', name: '制造厂', linkedGates: ['gate_refinery'], tollAmount: 6 }],
  ['gate_harbor', { id: 'gate_harbor', name: '安全港湾', linkedGates: ['gate_refinery'], tollAmount: 2 }],
])

export function RoutePlannerApp() {
  const { isConnected, handleConnect } = useConnection()
  const dAppKit = useDAppKit()
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [route, setRoute] = useState<{gateIds: string[]; totalToll: number; hops: number} | null>(null)
  const [status, setStatus] = useState('')

  const planRoute = () => {
    if (!from || !to) return
    const result = findCheapestRoute(GATE_NETWORK, from, to)
    setRoute(result)
  }

  const purchaseRoute = async () => {
    if (!route || route.gateIds.length < 2) return

    const tx = new Transaction()

    // 准备支付（总费用 + 5% 缓冲防止价格变动）
    const totalSui = Math.ceil(route.totalToll * 1.05) * 1e9
    const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(totalSui)])

    // 构建星门参数列表
    const gateArgs = route.gateIds.map(id => tx.object(id))

    // 调用多跳路由合约
    if (route.hops === 2) {
      tx.moveCall({
        target: `${LOGISTICS_PKG}::multi_hop::purchase_route`,
        arguments: [
          gateArgs[0], gateArgs[1], gateArgs[1], gateArgs[2],
          tx.object('CHARACTER_ID'),
          paymentCoin,
          tx.object('0x6'),
        ],
      })
    }

    try {
      setStatus('⏳ 购买路线通行证...')
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ 路线购买成功！Tx: ${result.digest.slice(0, 12)}...`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="route-planner">
      <h1>🗺 星门物流路线规划</h1>

      <div className="planner-inputs">
        <div>
          <label>出发星门</label>
          <select value={from} onChange={e => setFrom(e.target.value)}>
            <option value="">选择出发地...</option>
            {[...GATE_NETWORK.values()].map(g => (
              <option key={g.id} value={g.id}>{g.name}</option>
            ))}
          </select>
        </div>

        <div className="arrow">→</div>

        <div>
          <label>目的星门</label>
          <select value={to} onChange={e => setTo(e.target.value)}>
            <option value="">选择目的地...</option>
            {[...GATE_NETWORK.values()].map(g => (
              <option key={g.id} value={g.id}>{g.name}</option>
            ))}
          </select>
        </div>

        <button onClick={planRoute} disabled={!from || !to || from === to}>
          📍 规划路线
        </button>
      </div>

      {route && (
        <div className="route-result">
          <h3>最优路线（费用最低）</h3>
          <div className="route-path">
            {route.gateIds.map((id, i) => (
              <>
                <span key={id} className="gate-node">
                  {GATE_NETWORK.get(id)?.name}
                </span>
                {i < route.gateIds.length - 1 && (
                  <span className="arrow-icon">→</span>
                )}
              </>
            ))}
          </div>
          <div className="route-stats">
            <span>🔀 跳跃次数：{route.hops}</span>
            <span>💰 总费用：{route.totalToll} SUI</span>
          </div>
          <button
            className="purchase-btn"
            onClick={purchaseRoute}
            disabled={!isConnected}
          >
            {isConnected ? '🚀 一键购买全程通行证' : '请先连接钱包'}
          </button>
        </div>
      )}

      {route === null && from && to && from !== to && (
        <p className="no-route">⚠️ 找不到从 {from} 到 {to} 的路线</p>
      )}

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 🎯 完整回顾

```
合约层
├── multi_hop.move
│   ├── purchase_route()      → 两跳快速版（指定4个星门参数）
│   ├── purchase_route_n_hops() → N跳通用版（vector参数，最多6跳）
│   └── LogisticsAuth {}      → 星门扩展 Witness

链下路径规划
└── routePlanner.ts
    └── findCheapestRoute()   → Dijkstra，以通行费为权重

dApp 层
└── RoutePlannerApp.tsx
    ├── 下拉选择出发/目的地
    ├── 调用 Dijkstra 展示最优路线
    └── 一键购买全程通行证
```

## 🔧 扩展练习

1. **最短跳数路由**：实现第二种模式（优先减少跳数而不是费用）
2. **实时拥堵感知**：监听 GateJumped 事件，计算最近 5 分钟各星门流量，路由时避开拥堵
3. **物品护送保险**：购买路线时可额外购买"物品损失险"NFT，失败时赔付

---

## 📚 关联文档

- [Smart Gate API](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/gate/README.md)
- [Chapter 17：批处理事务](./chapter-17.md)
- [Chapter 12：链下索引](./chapter-12.md)
