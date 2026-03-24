# Practical Case 10: Space Resource Warfare (Comprehensive Practice)

> **Objective:** Integrate all knowledge from this course to build a miniature complete game: two alliances competing for control of a mining area, including turret offense/defense, stargate tolls, item storage, token rewards, and real-time battle report dApp.

---

> Status: Comprehensive case. The main text integrates multiple modules and is the best case to verify whether you've truly connected the first half of the book.

## Corresponding Code Directory

- [example-10](./code/example-10)
- [example-10/dapp](./code/example-10/dapp)

## Minimal Call Chain

`Issue faction NFT -> Stargate/Turret faction verification -> Player mining rewards -> WAR Token distribution -> dApp displays battle status`

## Project Overview

```
┌─────────────────────────────────────────────┐
│          Space Resource Warfare              │
│                                             │
│    Alliance A           Alliance B          │
│    Territory (Turret ×2)  Territory (Turret ×2)│
│         ↑                       ↑           │
│    ┌─[Gate A1]─── Neutral Mining Area ───[Gate B1]─┐   │
│    │           (Storage Box + Resources)         │   │
│    └─────────────────────────────────────┘  │
│                                             │
│  Battle Rules:                              │
│  • Entering neutral mining area requires passing opponent's turret check │
│  • Must hold "Faction NFT" to pass own stargate    │
│  • Mining area resources refresh hourly, first come first served │
│  • Each mining operation earns WAR Token (alliance token) │
└─────────────────────────────────────────────┘
```

---

## Contract Architecture Design

```
war_game/
├── Move.toml
└── sources/
    ├── faction_nft.move    # Faction NFT (alliance membership credential)
    ├── war_token.move      # WAR Token (war token)
    ├── faction_gate.move   # Stargate extension (faction check)
    ├── faction_turret.move # Turret extension (enemy detection)
    ├── mining_depot.move   # Mining area storage box extension (resource collection)
    └── war_registry.move   # Game registry (global state)
```

---

## Part One: Core Contracts

### `faction_nft.move`

```move
module war_game::faction_nft;

use sui::object::{Self, UID};
use sui::transfer;
use std::string::{Self, String, utf8};

public struct FACTION_NFT has drop {}

/// Faction enumeration
const FACTION_ALPHA: u8 = 0;
const FACTION_BETA: u8 = 1;

/// Faction NFT (alliance membership proof)
public struct FactionNFT has key, store {
    id: UID,
    faction: u8,                // 0 = Alpha, 1 = Beta
    member_since_ms: u64,
    name: String,
}

public struct WarAdminCap has key, store { id: UID }

public fun enlist(
    _admin: &WarAdminCap,
    faction: u8,
    member_name: vector<u8>,
    recipient: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction == FACTION_ALPHA || faction == FACTION_BETA, EInvalidFaction);
    let nft = FactionNFT {
        id: object::new(ctx),
        faction,
        member_since_ms: clock.timestamp_ms(),
        name: utf8(member_name),
    };
    transfer::public_transfer(nft, recipient);
}

public fun get_faction(nft: &FactionNFT): u8 { nft.faction }
public fun is_alpha(nft: &FactionNFT): bool { nft.faction == FACTION_ALPHA }
public fun is_beta(nft: &FactionNFT): bool { nft.faction == FACTION_BETA }

const EInvalidFaction: u64 = 0;
```

### `war_token.move`

```move
module war_game::war_token;

/// WAR Token (standard Coin design, see Chapter 14)
public struct WAR_TOKEN has drop {}

fun init(witness: WAR_TOKEN, ctx: &mut TxContext) {
    let (treasury, metadata) = sui::coin::create_currency(
        witness, 6, b"WAR", b"War Token",
        b"Earned through combat and mining in the Space Resource War",
        option::none(), ctx,
    );
    transfer::public_transfer(treasury, ctx.sender());
    transfer::public_freeze_object(metadata);
}
```

### `faction_gate.move` (Stargate Extension)

```move
module war_game::faction_gate;

use war_game::faction_nft::{Self, FactionNFT};
use world::gate::{Self, Gate};
use world::character::Character;
use sui::clock::Clock;
use sui::tx_context::TxContext;

public struct AlphaGateAuth has drop {}
public struct BetaGateAuth has drop {}

/// Alpha alliance stargate: only allows Alpha members to pass
public fun alpha_gate_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    faction_nft: &FactionNFT,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction_nft::is_alpha(faction_nft), EWrongFaction);
    gate::issue_jump_permit(
        source_gate, dest_gate, character, AlphaGateAuth {},
        clock.timestamp_ms() + 30 * 60 * 1000, ctx,
    );
}

/// Beta alliance stargate
public fun beta_gate_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    faction_nft: &FactionNFT,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction_nft::is_beta(faction_nft), EWrongFaction);
    gate::issue_jump_permit(
        source_gate, dest_gate, character, BetaGateAuth {},
        clock.timestamp_ms() + 30 * 60 * 1000, ctx,
    );
}

const EWrongFaction: u64 = 0;
```

### `mining_depot.move` (Mining Area Core)

```move
module war_game::mining_depot;

use war_game::faction_nft::{Self, FactionNFT};
use war_game::war_token::WAR_TOKEN;
use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use sui::coin::{Self, TreasuryCap};
use sui::clock::Clock;
use sui::object::{Self, UID};
use sui::event;

public struct MiningAuth has drop {}

/// Mining area state
public struct MiningDepot has key {
    id: UID,
    resource_count: u64,       // Current available quantity
    last_refresh_ms: u64,      // Last refresh time
    refresh_amount: u64,       // Amount replenished per refresh
    refresh_interval_ms: u64,  // Refresh interval
    alpha_total_mined: u64,
    beta_total_mined: u64,
}

public struct ResourceMined has copy, drop {
    miner: address,
    faction: u8,
    amount: u64,
    faction_total: u64,
}

/// Mining (checks faction NFT and distributes WAR Token reward)
public fun mine(
    depot: &mut MiningDepot,
    storage_unit: &mut StorageUnit,
    character: &Character,
    faction_nft: &FactionNFT,       // Requires faction authentication
    war_treasury: &mut TreasuryCap<WAR_TOKEN>,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Auto refresh resources
    maybe_refresh(depot, clock);

    assert!(amount > 0 && amount <= depot.resource_count, EInsufficientResource);

    depot.resource_count = depot.resource_count - amount;

    // Update statistics based on faction
    let faction = faction_nft::get_faction(faction_nft);
    if faction == 0 {
        depot.alpha_total_mined = depot.alpha_total_mined + amount;
    } else {
        depot.beta_total_mined = depot.beta_total_mined + amount;
    };

    // Withdraw resources (from SSU)
    // storage_unit::withdraw_batch(storage_unit, character, MiningAuth {}, RESOURCE_TYPE_ID, amount, ctx)

    // Distribute WAR Token reward (10 WAR per resource unit)
    let war_reward = amount * 10_000_000; // 10 WAR per unit, 6 decimals
    let war_coin = sui::coin::mint(war_treasury, war_reward, ctx);
    sui::transfer::public_transfer(war_coin, ctx.sender());

    event::emit(ResourceMined {
        miner: ctx.sender(),
        faction,
        amount,
        faction_total: if faction == 0 { depot.alpha_total_mined } else { depot.beta_total_mined },
    });
}

fun maybe_refresh(depot: &mut MiningDepot, clock: &Clock) {
    let now = clock.timestamp_ms();
    if now >= depot.last_refresh_ms + depot.refresh_interval_ms {
        depot.resource_count = depot.resource_count + depot.refresh_amount;
        depot.last_refresh_ms = now;
    }
}

const EInsufficientResource: u64 = 0;
```

---

## Part Two: Real-time Battle Report dApp

```tsx
// src/WarDashboard.tsx
import { useState, useEffect } from 'react'
import { useRealtimeEvents } from './hooks/useRealtimeEvents'
import { useCurrentClient } from '@mysten/dapp-kit-react'
import { useConnection } from '@evefrontier/dapp-kit'

const WAR_PKG = "0x_WAR_PACKAGE_"
const DEPOT_ID = "0x_DEPOT_ID_"

interface DepotState {
  resource_count: string
  alpha_total_mined: string
  beta_total_mined: string
  last_refresh_ms: string
}

interface MiningEvent {
  miner: string
  faction: string
  amount: string
  faction_total: string
}

const FACTION_COLOR = { '0': '#3B82F6', '1': '#EF4444' } // Alpha=blue, Beta=red
const FACTION_NAME = { '0': 'Alpha Alliance', '1': 'Beta Alliance' }

export function WarDashboard() {
  const { isConnected, currentAddress } = useConnection()
  const client = useCurrentClient()
  const [depot, setDepot] = useState<DepotState | null>(null)
  const [nextRefreshIn, setNextRefreshIn] = useState(0)

  // Load mining area state
  const loadDepot = async () => {
    const obj = await client.getObject({ id: DEPOT_ID, options: { showContent: true } })
    if (obj.data?.content?.dataType === 'moveObject') {
      setDepot(obj.data.content.fields as DepotState)
    }
  }

  useEffect(() => { loadDepot() }, [])

  // Refresh countdown
  useEffect(() => {
    if (!depot) return
    const timer = setInterval(() => {
      const refreshInterval = 60 * 60 * 1000 // 1 hour
      const nextRefresh = Number(depot.last_refresh_ms) + refreshInterval
      setNextRefreshIn(Math.max(0, nextRefresh - Date.now()))
    }, 1000)
    return () => clearInterval(timer)
  }, [depot])

  // Real-time battle report
  const miningEvents = useRealtimeEvents<MiningEvent>(
    `${WAR_PKG}::mining_depot::ResourceMined`,
    { maxEvents: 20 }
  )

  useEffect(() => {
    if (miningEvents.length > 0) loadDepot() // Refresh mining area state when mining events occur
  }, [miningEvents])

  // Calculate territory control percentage
  const alpha = Number(depot?.alpha_total_mined ?? 0)
  const beta = Number(depot?.beta_total_mined ?? 0)
  const total = alpha + beta
  const alphaPct = total > 0 ? Math.round(alpha * 100 / total) : 50

  return (
    <div className="war-dashboard">
      <h1>Space Resource Warfare</h1>

      {/* Faction control rate */}
      <section className="control-bar-section">
        <div className="control-labels">
          <span style={{ color: FACTION_COLOR['0'] }}>
            Alpha {alphaPct}%
          </span>
          <span style={{ color: FACTION_COLOR['1'] }}>
            {100 - alphaPct}% Beta
          </span>
        </div>
        <div className="control-bar">
          <div
            className="alpha-bar"
            style={{ width: `${alphaPct}%`, background: FACTION_COLOR['0'] }}
          />
        </div>
      </section>

      {/* Mining area status */}
      <section className="depot-status">
        <div className="stat-card">
          <span>Remaining Resources</span>
          <strong>{depot?.resource_count ?? '-'}</strong>
        </div>
        <div className="stat-card">
          <span>Next Refresh</span>
          <strong>{Math.ceil(nextRefreshIn / 60000)} minutes</strong>
        </div>
        <div className="stat-card alpha">
          <span style={{ color: FACTION_COLOR['0'] }}>Alpha Total Mined</span>
          <strong>{depot?.alpha_total_mined ?? '-'}</strong>
        </div>
        <div className="stat-card beta">
          <span style={{ color: FACTION_COLOR['1'] }}>Beta Total Mined</span>
          <strong>{depot?.beta_total_mined ?? '-'}</strong>
        </div>
      </section>

      {/* Real-time battle report */}
      <section className="battle-log">
        <h3>Real-time Battle Report</h3>
        {miningEvents.length === 0 ? (
          <p className="quiet">Mining area is quiet...</p>
        ) : (
          <ul>
            {miningEvents.map((e, i) => (
              <li
                key={i}
                style={{ borderLeftColor: FACTION_COLOR[e.faction as '0' | '1'] }}
              >
                <span className="faction-tag" style={{ color: FACTION_COLOR[e.faction as '0' | '1'] }}>
                  [{FACTION_NAME[e.faction as '0' | '1']}]
                </span>
                {e.miner.slice(0, 8)}... collected {e.amount} units of resources
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
```

---

## Complete Deployment Process

```bash
# 1. Compile and publish contracts
cd war_game
sui move build
sui client publish --gas-budget 200000000

# 2. Initialize game objects
# Run scripts/init-game.ts: create MiningDepot, register stargate/turret extensions

# 3. Test player enlistment
# scripts/enlist-player.ts: issue FactionNFT to test players

# 4. Start dApp
cd dapp
npm run dev
```

---

## Knowledge Integration

| Course Knowledge Point | Application in This Example |
|-----------|-----------|
| Chapter 3: Witness Pattern | `MiningAuth`, `AlphaGateAuth`, `BetaGateAuth` |
| Chapter 4: Component Extension Registration | Turret + Stargate + Storage box all have independent extensions |
| Chapter 5: dApp + Hooks | `useRealtimeEvents` drives real-time battle report updates |
| Chapter 11: OwnerCap | Alliance Leader holds OwnerCap of each component |
| Chapter 12: Event System | `ResourceMined` event drives dApp |
| Chapter 14: Token Economy | WAR Token as mining reward |
| Chapter 17: Security Audit | Permission verification + resource deduction without exceeding |
| Chapter 23: Publishing Process | Multiple contracts published simultaneously + initialization scripts |
| Chapter 8: Sponsored Transactions | Turret attack verification requires server signature |
| Chapter 9: GraphQL | Real-time query of mining area and battle status |
| Chapter 15: Cross-contract | mining_depot calls faction_nft read-only view |
| Chapter 13: NFT | FactionNFT Display shows faction information |

---

## Advanced Challenges

1. **Alliance Expulsion**: Leader can revoke FactionNFT of inactive members (transfer back to Admin or destroy)
2. **Resource Market**: Deploy SSU near mining area, players can sell mined resources back to alliance for more WAR Token
3. **War Settlement**: After 7 days, the alliance with the most total mining automatically receives the prize pool, contract auto-settles dividends

---

## Congratulations! You've Completed All Practical Cases

At this point, you have:
- Written 10 different types of contracts in Move from scratch
- Built 10 complete frontend dApps
- Mastered the complete tech stack from NFT, marketplace to DAO, competitions
- Understood chain-on and off-chain collaborative design patterns

**You now possess all the technical capabilities to build complete commercial products in EVE Frontier.**

---

## Related Documentation for Full Course

- [EVE Frontier Official Documentation](https://github.com/evefrontier/builder-documentation)
- [Sui Developer Documentation](https://docs.sui.io)
- [Move Book](https://move-book.com)
- [builder-scaffold](https://github.com/evefrontier/builder-scaffold)
