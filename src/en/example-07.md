# Example 7: Gate Logistics Network (Multi-Hop Routing System)

> **Goal:** Build a logistics network where an alliance owns multiple gates, supporting "A → B → C" multi-hop routing, off-chain calculates optimal path, on-chain atomically executes multiple jumps; with route planning dApp.

---

> Status: Teaching example. Current example focuses on multi-hop routing and off-chain planning architecture, emphasizing unified interfaces rather than individual Move contracts.

## Code Directory

- [example-07](./code/example-07)
- [example-07/dapp](./code/example-07/dapp)

## Minimal Call Chain

`Off-chain calculates optimal route -> Builds multi-hop PTB -> On-chain atomically executes all jumps -> All succeed or all rollback`

## Requirements Analysis

**Scenario:** Your alliance controls 5 interconnected gates, forming the following topology:

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

**Requirements:**
- Players can purchase "multi-hop passes" in one transaction, completing composite routes like A→Hub Alpha→Trade Hub
- Route calculation done off-chain (saves Gas)
- On-chain atomic execution: all jumps succeed or all rollback
- dApp provides visual route planner

---

## Part 1: Multi-Hop Routing Contract

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

/// Purchase multi-hop route in one transaction
public fun purchase_route(
    source_gate: &Gate,
    hop1_dest: &Gate,       // First hop destination
    hop2_source: &Gate,     // Second hop source (= hop1_dest's linked gate)
    hop2_dest: &Gate,       // Second hop destination
    character: &Character,
    mut payment: Coin<SUI>,  // Payment for both hops' total toll
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Verify route continuity: hop1_dest and hop2_source must be linked gates
    assert!(
        gate::are_linked(hop1_dest, hop2_source),
        ERouteDiscontinuous,
    );

    // Calculate and deduct toll for each hop
    let hop1_toll = get_toll(source_gate);
    let hop2_toll = get_toll(hop2_source);
    let total_toll = hop1_toll + hop2_toll;

    assert!(coin::value(&payment) >= total_toll, EInsufficientPayment);

    // Return change
    let change = payment.split(coin::value(&payment) - total_toll, ctx);
    if coin::value(&change) > 0 {
        transfer::public_transfer(change, ctx.sender());
    } else { coin::destroy_zero(change); }

    // Issue two JumpPermits (valid for 1 hour)
    let expires = clock.timestamp_ms() + 60 * 60 * 1000;

    gate::issue_jump_permit(
        source_gate, hop1_dest, character, LogisticsAuth {}, expires, ctx,
    );
    gate::issue_jump_permit(
        hop2_source, hop2_dest, character, LogisticsAuth {}, expires, ctx,
    );

    // Collect tolls
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

/// General N-hop routing (accepts variable-length routes)
public fun purchase_route_n_hops(
    gates: vector<&Gate>,          // Gate list [A, B, C, D, ...]
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let n = vector::length(&gates);
    assert!(n >= 2, ETooFewGates);
    assert!(n <= 6, ETooManyHops); // Prevent overly large transactions

    // Verify route continuity (each adjacent destination/source pair must be linked)
    let mut i = 1;
    while (i < n - 1) {
        assert!(
            gate::are_linked(vector::borrow(&gates, i), vector::borrow(&gates, i)),
            ERouteDiscontinuous,
        );
        i = i + 1;
    };

    // Calculate total toll
    let mut total: u64 = 0;
    let mut j = 0;
    while (j < n - 1) {
        total = total + get_toll(vector::borrow(&gates, j));
        j = j + 1;
    };

    assert!(coin::value(&payment) >= total, EInsufficientPayment);

    // Issue all Permits
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

    // Refund change
    let change = payment.split(coin::value(&payment) - total, ctx);
    if coin::value(&change) > 0 {
        transfer::public_transfer(change, ctx.sender());
    } else { coin::destroy_zero(change); }
    // Process payment to each gate treasury...
}

fun get_toll(gate: &Gate): u64 {
    // Read toll from gate's extension data (dynamic field)
    // Simplified version: fixed rate
    10_000_000_000 // 10 SUI
}

fun collect_toll(gate: &Gate, coin: Coin<SUI>, ctx: &TxContext) {
    // Transfer coin to gate's corresponding Treasury
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

## Part 2: Off-Chain Path Planning (Dijkstra)

```typescript
// lib/routePlanner.ts

interface Gate {
  id: string
  name: string
  linkedGates: string[]  // Linked gate ID list
  tollAmount: number     // Toll (SUI)
}

interface Route {
  gateIds: string[]
  totalToll: number
  hops: number
}

// Dijkstra shortest path (weighted by toll)
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
    // Find unvisited node with minimum distance
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

  if (dist.get(toId) === Infinity) return null // Unreachable

  // Reconstruct path
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

## Part 3: Route Planner dApp

```tsx
// src/RoutePlannerApp.tsx
import { useState, useEffect } from 'react'
import { useConnection } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { findCheapestRoute } from '../lib/routePlanner'
import { Transaction } from '@mysten/sui/transactions'

const LOGISTICS_PKG = "0x_LOGISTICS_PACKAGE_"

// Gate network topology (usually read from on-chain)
const GATE_NETWORK = new Map([
  ['gate_mining', { id: 'gate_mining', name: 'Mining Entry', linkedGates: ['gate_hub_alpha'], tollAmount: 5 }],
  ['gate_hub_alpha', { id: 'gate_hub_alpha', name: 'Hub Alpha', linkedGates: ['gate_mining', 'gate_trade', 'gate_refinery'], tollAmount: 3 }],
  ['gate_trade', { id: 'gate_trade', name: 'Trade Hub', linkedGates: ['gate_hub_alpha'], tollAmount: 8 }],
  ['gate_refinery', { id: 'gate_refinery', name: 'Refinery', linkedGates: ['gate_hub_alpha', 'gate_manufacturing', 'gate_harbor'], tollAmount: 4 }],
  ['gate_manufacturing', { id: 'gate_manufacturing', name: 'Manufacturing', linkedGates: ['gate_refinery'], tollAmount: 6 }],
  ['gate_harbor', { id: 'gate_harbor', name: 'Safe Harbor', linkedGates: ['gate_refinery'], tollAmount: 2 }],
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

    // Prepare payment (total toll + 5% buffer to prevent price changes)
    const totalSui = Math.ceil(route.totalToll * 1.05) * 1e9
    const [paymentCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(totalSui)])

    // Build gate parameter list
    const gateArgs = route.gateIds.map(id => tx.object(id))

    // Call multi-hop routing contract
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
      setStatus('⏳ Purchasing route pass...')
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ Route purchased successfully! Tx: ${result.digest.slice(0, 12)}...`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="route-planner">
      <h1>🗺 Gate Logistics Route Planner</h1>

      <div className="planner-inputs">
        <div>
          <label>Departure Gate</label>
          <select value={from} onChange={e => setFrom(e.target.value)}>
            <option value="">Select departure...</option>
            {[...GATE_NETWORK.values()].map(g => (
              <option key={g.id} value={g.id}>{g.name}</option>
            ))}
          </select>
        </div>

        <div className="arrow">→</div>

        <div>
          <label>Destination Gate</label>
          <select value={to} onChange={e => setTo(e.target.value)}>
            <option value="">Select destination...</option>
            {[...GATE_NETWORK.values()].map(g => (
              <option key={g.id} value={g.id}>{g.name}</option>
            ))}
          </select>
        </div>

        <button onClick={planRoute} disabled={!from || !to || from === to}>
          📍 Plan Route
        </button>
      </div>

      {route && (
        <div className="route-result">
          <h3>Optimal Route (Lowest Cost)</h3>
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
            <span>🔀 Jumps: {route.hops}</span>
            <span>💰 Total Cost: {route.totalToll} SUI</span>
          </div>
          <button
            className="purchase-btn"
            onClick={purchaseRoute}
            disabled={!isConnected}
          >
            {isConnected ? '🚀 One-Click Purchase Full Route Pass' : 'Please Connect Wallet'}
          </button>
        </div>
      )}

      {route === null && from && to && from !== to && (
        <p className="no-route">⚠️ No route found from {from} to {to}</p>
      )}

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 🎯 Complete Review

```
Contract Layer
├── multi_hop.move
│   ├── purchase_route()      → Two-hop quick version (specifies 4 gate parameters)
│   ├── purchase_route_n_hops() → N-hop general version (vector parameters, max 6 hops)
│   └── LogisticsAuth {}      → Gate extension Witness

Off-Chain Path Planning
└── routePlanner.ts
    └── findCheapestRoute()   → Dijkstra, weighted by toll

dApp Layer
└── RoutePlannerApp.tsx
    ├── Dropdown select departure/destination
    ├── Call Dijkstra to display optimal route
    └── One-click purchase full route pass
```

## 🔧 Extension Exercises

1. **Shortest Hop Routing**: Implement second mode (prioritize reducing hops rather than cost)
2. **Real-Time Congestion Awareness**: Monitor GateJumped events, calculate last 5 minutes traffic per gate, route to avoid congestion
3. **Item Escort Insurance**: Can purchase additional "item loss insurance" NFT when buying route, compensate on failure

---

## 📚 Related Documentation

- [Smart Gate API](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/gate/README.md)
- [Chapter 21: Batch Transactions](./chapter-21.md)
- [Chapter 9: Off-Chain Indexing](./chapter-09.md)
