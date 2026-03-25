# Example 8: Builder Competition System (On-Chain Leaderboard + Automatic Rewards)

> **Goal:** Build an on-chain competition framework: within a fixed time window, players participate by staking points, leaderboard records on-chain, automatically settles on deadline, top three receive NFT trophies and token rewards.

---

> Status: Code skeleton. Repository includes `Move.toml`, `weekly_race.move` and dApp directory, but point reporting authorization, reward asset types, and off-chain settlement sources still need completion based on your competition business.

## Code Directory

- [example-08](./code/example-08)
- [example-08/dapp](./code/example-08/dapp)

## Minimal Call Chain

`Create competition -> Fund prize pool -> Off-chain aggregates points -> Server authorizes point reporting -> Deadline settlement -> Distribute prizes and trophies`

## Off-Chain Responsibility Boundaries

This example's most error-prone area is not the leaderboard itself, but off-chain collaboration boundaries. Recommend separating responsibilities clearly:

- On-chain only handles: Competition lifecycle, prize pool funds, final settlement, trophy minting
- Server handles: Monitor jump events, aggregate scores by season, sign point reports
- Frontend handles: Display current points, trigger admin operations, read settlement results

If you temporarily cannot complete server signatures and point aggregation, don't promote this example as "complete automated competition system"; more accurate description is "competition contract skeleton + leaderboard settlement model".

## Requirements Analysis

**Scenario:** You (Builder) hold weekly "Mining Area Contest", compete on who jumps through your gate most times this week:

- 📅 **Format**: Starts every Sunday 00:00 UTC, ends next Saturday 23:59
- 📊 **Points**: +1 point per jump (reported by monitoring GateJumped events)
- 🏆 **Rewards**:
  - 🥇 First Place: Champion NFT Trophy + 500 ALLY Token
  - 🥈 Second Place: Elite NFT Trophy + 200 ALLY Token
  - 🥉 Third Place: Contender NFT Trophy + 100 ALLY Token
- 💡 **Key**: Top three automatically determined by contract based on on-chain points, no manual intervention

---

## Part 1: Competition Contract

```move
module competition::weekly_race;

use sui::table::{Self, Table};
use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::event;
use sui::transfer;
use std::string::{Self, String, utf8};

// Note: This example omits actual project's `AdminACL` / `verify_sponsor`
// imports and off-chain leaderboard aggregation logic, example only shows contract modeling approach.

// ── Constants ──────────────────────────────────────────────────

const WEEK_DURATION_MS: u64 = 7 * 24 * 60 * 60 * 1000; // 7 days

// ── Data Structures ───────────────────────────────────────────────

/// Competition (create new one each week)
public struct Race has key {
    id: UID,
    season: u64,              // Season number
    start_time_ms: u64,
    end_time_ms: u64,
    scores: Table<address, u64>,  // Player address → points
    top3: vector<address>,        // Top three (filled after settlement)
    is_settled: bool,
    prize_pool_sui: Balance<SUI>,
    admin: address,
}

/// Trophy NFT
public struct TrophyNFT has key, store {
    id: UID,
    season: u64,
    rank: u8,      // 1, 2, 3
    score: u64,
    winner: address,
    image_url: String,
}

public struct RaceAdminCap has key, store { id: UID }

// ── Events ──────────────────────────────────────────────────

public struct ScoreUpdated has copy, drop {
    race_id: ID,
    player: address,
    new_score: u64,
}

public struct RaceSettled has copy, drop {
    race_id: ID,
    season: u64,
    winner: address,
    second: address,
    third: address,
}

// ── Initialization ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::transfer(RaceAdminCap { id: object::new(ctx) }, ctx.sender());
}

/// Create new competition
public fun create_race(
    _cap: &RaceAdminCap,
    season: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let start = clock.timestamp_ms();
    let race = Race {
        id: object::new(ctx),
        season,
        start_time_ms: start,
        end_time_ms: start + WEEK_DURATION_MS,
        scores: table::new(ctx),
        top3: vector::empty(),
        is_settled: false,
        prize_pool_sui: balance::zero(),
        admin: ctx.sender(),
    };
    transfer::share_object(race);
}

/// Fund prize pool
public fun fund_prize_pool(
    race: &mut Race,
    _cap: &RaceAdminCap,
    coin: Coin<SUI>,
) {
    balance::join(&mut race.prize_pool_sui, coin::into_balance(coin));
}

// ── Score Reporting (called by competition server or turret/gate extension) ────────────

public fun report_score(
    race: &mut Race,
    player: address,
    score_delta: u64,    // Points added this time
    clock: &Clock,
    admin_acl: &AdminACL, // Requires game server signature
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);         // Verify authorized server
    assert!(!race.is_settled, ERaceEnded);
    assert!(clock.timestamp_ms() <= race.end_time_ms, ERaceEnded);

    if !table::contains(&race.scores, player) {
        table::add(&mut race.scores, player, 0u64);
    };

    let score = table::borrow_mut(&mut race.scores, player);
    *score = *score + score_delta;

    event::emit(ScoreUpdated {
        race_id: object::id(race),
        player,
        new_score: *score,
    });
}

// ── Settlement (requires off-chain calculation of top three then passed in)────────────────────────

public fun settle_race(
    race: &mut Race,
    _cap: &RaceAdminCap,
    first: address,
    second: address,
    third: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(!race.is_settled, EAlreadySettled);
    assert!(clock.timestamp_ms() >= race.end_time_ms, ERaceNotEnded);

    // Verify on-chain scores (prevent fake rankings)
    let s1 = *table::borrow(&race.scores, first);
    let s2 = *table::borrow(&race.scores, second);
    let s3 = *table::borrow(&race.scores, third);
    assert!(s1 >= s2 && s2 >= s3, EInvalidRanking);

    race.is_settled = true;
    race.top3 = vector[first, second, third];

    // Distribute prize pool: 50% to first, 30% to second, 20% to third
    let total = balance::value(&race.prize_pool_sui);
    let prize1 = coin::take(&mut race.prize_pool_sui, total * 50 / 100, ctx);
    let prize2 = coin::take(&mut race.prize_pool_sui, total * 30 / 100, ctx);
    let prize3 = coin::take(&mut race.prize_pool_sui, balance::value(&race.prize_pool_sui), ctx);

    transfer::public_transfer(prize1, first);
    transfer::public_transfer(prize2, second);
    transfer::public_transfer(prize3, third);

    // Mint trophy NFTs
    mint_trophy(race.season, 1, s1, first, ctx);
    mint_trophy(race.season, 2, s2, second, ctx);
    mint_trophy(race.season, 3, s3, third, ctx);

    event::emit(RaceSettled {
        race_id: object::id(race),
        season: race.season,
        winner: first,
        second,
        third,
    });
}

fun mint_trophy(
    season: u64,
    rank: u8,
    score: u64,
    winner: address,
    ctx: &mut TxContext,
) {
    let (name, image_url) = match(rank) {
        1 => (b"Champion Trophy", b"https://assets.example.com/trophies/gold.png"),
        2 => (b"Elite Trophy", b"https://assets.example.com/trophies/silver.png"),
        _ => (b"Contender Trophy", b"https://assets.example.com/trophies/bronze.png"),
    };

    let trophy = TrophyNFT {
        id: object::new(ctx),
        season,
        rank,
        score,
        winner,
        image_url: utf8(image_url),
    };

    transfer::public_transfer(trophy, winner);
}

const ERaceEnded: u64 = 0;
const EAlreadySettled: u64 = 1;
const ERaceNotEnded: u64 = 2;
const EInvalidRanking: u64 = 3;
```

---

## Part 2: Settlement Script (Off-Chain Ranking + On-Chain Settlement)

```typescript
// scripts/settle-race.ts
import { SuiClient } from "@mysten/sui/client"
import { Transaction } from "@mysten/sui/transactions"
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519"

const RACE_PKG = "0x_COMPETITION_PACKAGE_"
const RACE_ID = "0x_RACE_ID_"

async function settleRace() {
  const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" })
  const adminKeypair = Ed25519Keypair.fromSecretKey(/* ... */)

  // 1. Read all scores from on-chain (aggregate via ScoreUpdated events)
  const scoreMap = new Map<string, number>()
  let cursor = null

  do {
    const page = await client.queryEvents({
      query: { MoveEventType: `${RACE_PKG}::weekly_race::ScoreUpdated` },
      cursor,
      limit: 200,
    })

    for (const event of page.data) {
      const { player, new_score } = event.parsedJson as any
      scoreMap.set(player, Number(new_score)) // Take latest value
    }

    cursor = page.nextCursor
  } while (cursor)

  // 2. Sort to find top three
  const sorted = [...scoreMap.entries()]
    .sort((a, b) => b[1] - a[1])

  if (sorted.length < 3) {
    console.log("Insufficient participants, cannot settle")
    return
  }

  const [first, second, third] = sorted.slice(0, 3).map(([addr]) => addr)
  console.log(`First: ${first} (${sorted[0][1]} points)`)
  console.log(`Second: ${second} (${sorted[1][1]} points)`)
  console.log(`Third: ${third} (${sorted[2][1]} points)`)

  // 3. Submit settlement transaction
  const tx = new Transaction()
  tx.moveCall({
    target: `${RACE_PKG}::weekly_race::settle_race`,
    arguments: [
      tx.object(RACE_ID),
      tx.object("ADMIN_CAP_ID"),
      tx.pure.address(first),
      tx.pure.address(second),
      tx.pure.address(third),
      tx.object("0x6"), // Clock
    ],
  })

  const result = await client.signAndExecuteTransaction({
    signer: adminKeypair,
    transaction: tx,
  })
  console.log("Settlement successful! Trophies distributed. Tx:", result.digest)
}

settleRace()
```

---

## Part 3: Real-Time Leaderboard dApp

```tsx
// src/LeaderboardApp.tsx
import { useEffect, useState } from 'react'
import { useRealtimeEvents } from './hooks/useRealtimeEvents'

const RACE_PKG = "0x_COMPETITION_PACKAGE_"

interface ScoreEntry {
  rank: number
  address: string
  score: number
}

export function LeaderboardApp() {
  const [scores, setScores] = useState<Map<string, number>>(new Map())
  const [timeLeft, setTimeLeft] = useState('')
  const raceEnd = new Date('2026-03-08T00:00:00Z').getTime()

  // Real-time subscribe to score updates
  const events = useRealtimeEvents<{ player: string; new_score: string }>(
    `${RACE_PKG}::weekly_race::ScoreUpdated`
  )

  useEffect(() => {
    const updated = new Map(scores)
    for (const e of events) {
      updated.set(e.player, Number(e.new_score))
    }
    setScores(updated)
  }, [events])

  // Countdown
  useEffect(() => {
    const timer = setInterval(() => {
      const diff = raceEnd - Date.now()
      if (diff <= 0) { setTimeLeft('Ended'); return }
      const d = Math.floor(diff / 86400000)
      const h = Math.floor((diff % 86400000) / 3600000)
      const m = Math.floor((diff % 3600000) / 60000)
      setTimeLeft(`${d}d ${h}h ${m}m`)
    }, 1000)
    return () => clearInterval(timer)
  }, [])

  const sorted: ScoreEntry[] = [...scores.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([address, score], i) => ({ rank: i + 1, address, score }))

  const medals = ['🥇', '🥈', '🥉']

  return (
    <div className="leaderboard">
      <header>
        <h1>🏆 First Gate Jump Competition</h1>
        <div className="countdown">
          ⏳ Time Remaining: <strong>{timeLeft}</strong>
        </div>
      </header>

      <table className="ranking-table">
        <thead>
          <tr><th>Rank</th><th>Player</th><th>Jump Count</th></tr>
        </thead>
        <tbody>
          {sorted.map(({ rank, address, score }) => (
            <tr key={address} className={rank <= 3 ? 'top3' : ''}>
              <td>{medals[rank - 1] ?? rank}</td>
              <td>{address.slice(0, 6)}...{address.slice(-4)}</td>
              <td><strong>{score}</strong> times</td>
            </tr>
          ))}
          {sorted.length === 0 && (
            <tr><td colSpan={3}>No data yet, waiting for first jump...</td></tr>
          )}
        </tbody>
      </table>
    </div>
  )
}
```

---

## 🎯 Complete Review

```
Contract Layer
├── weekly_race.move
│   ├── Race (shared object, one per season)
│   ├── TrophyNFT (trophy object)
│   ├── create_race()     ← Admin creates
│   ├── fund_prize_pool() ← Admin funds prize pool
│   ├── report_score()    ← Server reports points (AdminACL verification)
│   └── settle_race()     ← Admin passes in top three, contract verifies and settles

Settlement Script
└── settle-race.ts
    ├── QueryEvents aggregates all points
    ├── Sort to calculate top three
    └── Submit settle_race() transaction

dApp Layer
└── LeaderboardApp.tsx
    ├── subscribeEvent real-time updates leaderboard
    └── Competition countdown
```

## 🔧 Extension Exercises

1. **Anti-Score Farming**: Rate limit in `report_score` (each player max 60 points per minute)
2. **Public Verification**: Store hash of raw data for each score report on-chain, allow anyone to verify final ranking
3. **Season System**: Admin cannot end current competition early, contract enforces timeline

---

## 📚 Related Documentation

- [Chapter 8: Sponsored Transactions & Server Integration](./chapter-08.md)
- [Chapter 9: Off-Chain Indexing](./chapter-09.md)
- [Chapter 13: NFT Design](./chapter-13.md)
