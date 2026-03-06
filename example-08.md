# 实战案例 8：Builder 竞赛系统（链上排行榜 + 自动奖励）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 构建一套链上竞赛框架：在固定时间窗口内，玩家通过质押积分参与竞赛，排行榜记录链上，到时间自动结算，前三名获得 NFT 奖杯和代币奖励。

---

## 需求分析

**场景：** 你（Builder）每周举办"矿区争夺赛"，比谁在本周通过你的星门跳跃最多次：

- 📅 **赛制**：每周日 00:00 UTC 开始，下周六 23:59 结束
- 📊 **积分**：每次跳跃 +1 积分（通过监听 GateJumped 事件上报）
- 🏆 **奖励**：
  - 🥇 第一名：Champion NFT 奖杯 + 500 ALLY Token
  - 🥈 第二名：Elite NFT 奖杯 + 200 ALLY Token
  - 🥉 第三名：Contender NFT 奖杯 + 100 ALLY Token
- 💡 **关键**：前三名由合约根据链上积分自动决定，不可人工干预

---

## 第一部分：竞赛合约

```move
module competition::weekly_race;

use sui::table::{Self, Table};
use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use sui::transfer;
use std::string::utf8;

// ── 常量 ──────────────────────────────────────────────────

const WEEK_DURATION_MS: u64 = 7 * 24 * 60 * 60 * 1000; // 7 天

// ── 数据结构 ───────────────────────────────────────────────

/// 竞赛（每周创建一个新的）
public struct Race has key {
    id: UID,
    season: u64,              // 第几届
    start_time_ms: u64,
    end_time_ms: u64,
    scores: Table<address, u64>,  // 玩家地址 → 积分
    top3: vector<address>,        // 前三名（结算后填充）
    is_settled: bool,
    prize_pool_sui: Balance<SUI>,
    admin: address,
}

/// 奖杯 NFT
public struct TrophyNFT has key, store {
    id: UID,
    season: u64,
    rank: u8,      // 1, 2, 3
    score: u64,
    winner: address,
    image_url: String,
}

public struct RaceAdminCap has key, store { id: UID }

// ── 事件 ──────────────────────────────────────────────────

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

// ── 初始化 ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::transfer(RaceAdminCap { id: object::new(ctx) }, ctx.sender());
}

/// 创建新一届竞赛
public entry fun create_race(
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

/// 充值奖池
public entry fun fund_prize_pool(
    race: &mut Race,
    _cap: &RaceAdminCap,
    coin: Coin<SUI>,
) {
    balance::join(&mut race.prize_pool_sui, coin::into_balance(coin));
}

// ── 积分上报（由赛事服务器或炮塔/星门扩展调用） ────────────

public entry fun report_score(
    race: &mut Race,
    player: address,
    score_delta: u64,    // 本次增加的积分
    clock: &Clock,
    admin_acl: &AdminACL, // 需要游戏服务器签名
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);         // 验证是授权服务器
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

// ── 结算（需要链下算出前三名后传入）────────────────────────

public entry fun settle_race(
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

    // 验证链上积分（防止传入假排名）
    let s1 = *table::borrow(&race.scores, first);
    let s2 = *table::borrow(&race.scores, second);
    let s3 = *table::borrow(&race.scores, third);
    assert!(s1 >= s2 && s2 >= s3, EInvalidRanking);

    race.is_settled = true;
    race.top3 = vector[first, second, third];

    // 分发奖池：50% 给第一，30% 给第二，20% 给第三
    let total = balance::value(&race.prize_pool_sui);
    let prize1 = coin::take(&mut race.prize_pool_sui, total * 50 / 100, ctx);
    let prize2 = coin::take(&mut race.prize_pool_sui, total * 30 / 100, ctx);
    let prize3 = coin::take(&mut race.prize_pool_sui, balance::value(&race.prize_pool_sui), ctx);

    transfer::public_transfer(prize1, first);
    transfer::public_transfer(prize2, second);
    transfer::public_transfer(prize3, third);

    // 铸造奖杯 NFT
    mint_trophy(race.season, 1, s1, first, ctx);
    mint_trophy(race.season, 2, s2, second, ctx);
    mint_trophy(race.season, 3, s3, third, ctx);

    event::emit(RaceSettled {
        race_id: object::id(race),
        season: race.season,
        winner: first, second, third,
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

## 第二部分：结算脚本（链下排名 + 链上结算）

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

  // 1. 从链上读取所有积分（通过 ScoreUpdated 事件聚合）
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
      scoreMap.set(player, Number(new_score)) // 取最新值
    }

    cursor = page.nextCursor
  } while (cursor)

  // 2. 排序找出前三名
  const sorted = [...scoreMap.entries()]
    .sort((a, b) => b[1] - a[1])

  if (sorted.length < 3) {
    console.log("参与人数不足，无法结算")
    return
  }

  const [first, second, third] = sorted.slice(0, 3).map(([addr]) => addr)
  console.log(`第一：${first}（${sorted[0][1]} 积分）`)
  console.log(`第二：${second}（${sorted[1][1]} 积分）`)
  console.log(`第三：${third}（${sorted[2][1]} 积分）`)

  // 3. 提交结算交易
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
  console.log("结算成功！奖杯已发放。Tx:", result.digest)
}

settleRace()
```

---

## 第三部分：实时排行榜 dApp

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

  // 实时订阅积分更新
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

  // 倒计时
  useEffect(() => {
    const timer = setInterval(() => {
      const diff = raceEnd - Date.now()
      if (diff <= 0) { setTimeLeft('已结束'); return }
      const d = Math.floor(diff / 86400000)
      const h = Math.floor((diff % 86400000) / 3600000)
      const m = Math.floor((diff % 3600000) / 60000)
      setTimeLeft(`${d}天 ${h}时 ${m}分`)
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
        <h1>🏆 第一届星门跳跃竞赛</h1>
        <div className="countdown">
          ⏳ 剩余时间：<strong>{timeLeft}</strong>
        </div>
      </header>

      <table className="ranking-table">
        <thead>
          <tr><th>排名</th><th>玩家</th><th>跳跃次数</th></tr>
        </thead>
        <tbody>
          {sorted.map(({ rank, address, score }) => (
            <tr key={address} className={rank <= 3 ? 'top3' : ''}>
              <td>{medals[rank - 1] ?? rank}</td>
              <td>{address.slice(0, 6)}...{address.slice(-4)}</td>
              <td><strong>{score}</strong> 次</td>
            </tr>
          ))}
          {sorted.length === 0 && (
            <tr><td colSpan={3}>暂无数据，等待第一次跳跃...</td></tr>
          )}
        </tbody>
      </table>
    </div>
  )
}
```

---

## 🎯 完整回顾

```
合约层
├── weekly_race.move
│   ├── Race（共享对象，每届一个）
│   ├── TrophyNFT（奖杯对象）
│   ├── create_race()     ← Admin 创建
│   ├── fund_prize_pool() ← Admin 充奖池
│   ├── report_score()    ← 服务器上报积分（AdminACL 验证）
│   └── settle_race()     ← Admin 传入前三名，合约验证并结算

结算脚本
└── settle-race.ts
    ├── QueryEvents 聚合所有积分
    ├── 排序计算前三名
    └── 提交 settle_race() 交易

dApp 层
└── LeaderboardApp.tsx
    ├── subscribeEvent 实时更新排行榜
    └── 竞赛倒计时
```

## 🔧 扩展练习

1. **防刷分**：在 `report_score` 中限速（每个玩家每分钟最多上报 60 积分）
2. **公开验证**：将每次积分上报的原始数据哈希也存链上，让任何人可以验算最终排名
3. **赛季制**：Admin 无法提前结束当届竞赛，合约强制执行时间轴

---

## 📚 关联文档

- [Chapter 11：赞助交易与服务端集成](./chapter-11.md)
- [Chapter 12：链下索引](./chapter-12.md)
- [Chapter 14：NFT 设计](./chapter-14.md)
