# 实战案例 5：联盟代币与自动分红系统

> **目标：** 发行联盟专属 Coin（`ALLY Token`），构建一套自动分红合约——联盟运营的设施收入自动按持仓比例分配给代币持有者——并附带治理面板 dApp。

---

> 状态：教学示例。仓库内已有联盟代币、金库和治理源码，重点在理解资金流与治理流如何并存。

## 对应代码目录

- [example-05](./code/example-05)
- [example-05/dapp](./code/example-05/dapp)

## 最小调用链

`发行 ALLY Token -> 收入汇入金库 -> 按持仓分红 -> 发起提案 -> 成员投票`

## 需求分析

**场景：** 你的联盟同时运营多个星门收费站和存储箱市场，收入来自多个渠道。你希望：

- 💎 发行 `ALLY Token`（总量 1,000,000），按贡献分配给联盟成员
- 🏦 所有设施收入统一汇入联盟金库（Treasury）
- 💸 持有 `ALLY Token` 的成员，按持仓比例定期领取分红
- 🗳 Token 持有者可对联盟重大决策（如费率调整）投票
- 📊 治理面板显示金库余额、分红历史、提案列表

---

## 第一部分：联盟代币合约

```move
module ally_dao::ally_token;

use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
use sui::transfer;
use sui::tx_context::TxContext;

/// 一次性见证（One-Time Witness）
public struct ALLY_TOKEN has drop {}

fun init(witness: ALLY_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        6,                          // 精度：6位小数
        b"ALLY",                    // 符号
        b"Alliance Token",          // 名称
        b"Governance and dividend token for Alliance X",
        option::none(),
        ctx,
    );

    // TreasuryCap 赋予联盟 DAO 合约（通过地址或多签）
    transfer::public_transfer(treasury_cap, ctx.sender());
    transfer::public_freeze_object(coin_metadata); // 元数据不可变
}

/// 铸造（由 DAO 合约控制，不直接暴露给外部）
public fun internal_mint(
    treasury: &mut TreasuryCap<ALLY_TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::mint(treasury, amount, ctx);
    transfer::public_transfer(coin, recipient);
}
```

---

## 第二部分：DAO 金库与分红合约

```move
module ally_dao::treasury;

use ally_dao::ally_token::ALLY_TOKEN;
use sui::coin::{Self, Coin, TreasuryCap};
use sui::balance::{Self, Balance};
use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::event;
use sui::transfer;
use sui::tx_context::TxContext;
use sui::sui::SUI;

// ── 数据结构 ──────────────────────────────────────────────

/// 联盟金库
public struct AllianceTreasury has key {
    id: UID,
    sui_balance: Balance<SUI>,          // 等待分配的 SUI
    total_distributed: u64,             // 历史累计分红总额
    distribution_index: u64,            // 当前分红轮次
    total_ally_supply: u64,             // 当前 ALLY Token 流通总量
}

/// 分红领取凭证（记录每个持有者已领到哪一轮）
public struct DividendClaim has key, store {
    id: UID,
    holder: address,
    last_claimed_index: u64,
}

/// 提案（治理）
public struct Proposal has key {
    id: UID,
    proposer: address,
    description: vector<u8>,
    vote_yes: u64,      // 赞成票（ALLY Token 数量加权）
    vote_no: u64,       // 反对票
    deadline_ms: u64,
    executed: bool,
}

/// 分红快照（每次分红创建一个）
public struct DividendSnapshot has store {
    amount_per_token: u64,  // 每个 ALLY Token 对应的 SUI 数量（以最小精度计）
    total_supply_at_snapshot: u64,
}

// ── 事件 ──────────────────────────────────────────────────

public struct DividendDistributed has copy, drop {
    treasury_id: ID,
    total_amount: u64,
    per_token_amount: u64,
    distribution_index: u64,
}

public struct DividendClaimed has copy, drop {
    holder: address,
    amount: u64,
    rounds: u64,
}

// ── 初始化 ────────────────────────────────────────────────

public entry fun create_treasury(
    total_ally_supply: u64,
    ctx: &mut TxContext,
) {
    let treasury = AllianceTreasury {
        id: object::new(ctx),
        sui_balance: balance::zero(),
        total_distributed: 0,
        distribution_index: 0,
        total_ally_supply,
    };
    transfer::share_object(treasury);
}

// ── 收入存入 ──────────────────────────────────────────────

/// 任何合约（星门、市场等）都可以向金库存入收入
public fun deposit_revenue(treasury: &mut AllianceTreasury, coin: Coin<SUI>) {
    balance::join(&mut treasury.sui_balance, coin::into_balance(coin));
}

// ── 触发分红 ──────────────────────────────────────────────

/// 管理员触发：将当前金库余额按比例准备分红
/// 需要存储每轮的快照
public entry fun trigger_distribution(
    treasury: &mut AllianceTreasury,
    ctx: &TxContext,
) {
    let total = balance::value(&treasury.sui_balance);
    assert!(total > 0, ENoBalance);
    assert!(treasury.total_ally_supply > 0, ENoSupply);

    // 每个 Token 分到多少（以最小精度，即乘以 1e6 避免精度损失）
    let per_token_scaled = total * 1_000_000 / treasury.total_ally_supply;

    treasury.distribution_index = treasury.distribution_index + 1;
    treasury.total_distributed = treasury.total_distributed + total;

    // 存储快照到动态字段
    sui::dynamic_field::add(
        &mut treasury.id,
        treasury.distribution_index,
        DividendSnapshot {
            amount_per_token: per_token_scaled,
            total_supply_at_snapshot: treasury.total_ally_supply,
        }
    );

    event::emit(DividendDistributed {
        treasury_id: object::id(treasury),
        total_amount: total,
        per_token_amount: per_token_scaled,
        distribution_index: treasury.distribution_index,
    });
}

// ── 持有者领取分红 ────────────────────────────────────────

/// 持有者提供自己的 ALLY Token（不消耗，只读取数量）来领取分红
public entry fun claim_dividends(
    treasury: &mut AllianceTreasury,
    ally_coin: &Coin<ALLY_TOKEN>,    // 持有者的 ALLY Token（只读）
    claim_record: &mut DividendClaim,
    ctx: &mut TxContext,
) {
    assert!(claim_record.holder == ctx.sender(), ENotHolder);

    let holder_balance = coin::value(ally_coin);
    assert!(holder_balance > 0, ENoAllyTokens);

    let from_index = claim_record.last_claimed_index + 1;
    let to_index = treasury.distribution_index;
    assert!(from_index <= to_index, ENothingToClaim);

    let mut total_claim: u64 = 0;
    let mut i = from_index;

    while (i <= to_index) {
        let snapshot: &DividendSnapshot = sui::dynamic_field::borrow(
            &treasury.id, i
        );
        // 按持仓比例计算（反缩放）
        total_claim = total_claim + (holder_balance * snapshot.amount_per_token / 1_000_000);
        i = i + 1;
    };

    assert!(total_claim > 0, ENothingToClaim);

    claim_record.last_claimed_index = to_index;
    let payout = sui::coin::take(&mut treasury.sui_balance, total_claim, ctx);
    transfer::public_transfer(payout, ctx.sender());

    event::emit(DividendClaimed {
        holder: ctx.sender(),
        amount: total_claim,
        rounds: to_index - from_index + 1,
    });
}

/// 创建领取凭证（每个持有者创建一次）
public entry fun create_claim_record(ctx: &mut TxContext) {
    let record = DividendClaim {
        id: object::new(ctx),
        holder: ctx.sender(),
        last_claimed_index: 0,
    };
    transfer::transfer(record, ctx.sender());
}

const ENoBalance: u64 = 0;
const ENoSupply: u64 = 1;
const ENotHolder: u64 = 2;
const ENoAllyTokens: u64 = 3;
const ENothingToClaim: u64 = 4;
```

---

## 第三部分：治理投票合约

```move
module ally_dao::governance;

use ally_dao::ally_token::ALLY_TOKEN;
use sui::coin::Coin;
use sui::object::{Self, UID};
use sui::clock::Clock;
use sui::transfer;
use sui::event;

public struct Proposal has key {
    id: UID,
    proposer: address,
    description: vector<u8>,
    vote_yes: u64,
    vote_no: u64,
    deadline_ms: u64,
    executed: bool,
}

/// 创建提案（需要持有最少 1000 ALLY Token）
public entry fun create_proposal(
    ally_coin: &Coin<ALLY_TOKEN>,
    description: vector<u8>,
    voting_duration_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 需要持有足够代币才能发起提案
    assert!(sui::coin::value(ally_coin) >= 1_000_000_000, EInsufficientToken); // 1000 ALLY

    let proposal = Proposal {
        id: object::new(ctx),
        proposer: ctx.sender(),
        description,
        vote_yes: 0,
        vote_no: 0,
        deadline_ms: clock.timestamp_ms() + voting_duration_ms,
        executed: false,
    };

    transfer::share_object(proposal);
}

/// 投票（用 ALLY Token 数量加权）
public entry fun vote(
    proposal: &mut Proposal,
    ally_coin: &Coin<ALLY_TOKEN>,
    support: bool,
    clock: &Clock,
    _ctx: &TxContext,
) {
    assert!(clock.timestamp_ms() < proposal.deadline_ms, EVotingEnded);

    let weight = sui::coin::value(ally_coin);
    if support {
        proposal.vote_yes = proposal.vote_yes + weight;
    } else {
        proposal.vote_no = proposal.vote_no + weight;
    };
}

const EInsufficientToken: u64 = 0;
const EVotingEnded: u64 = 1;
```

---

## 第四部分：治理面板 dApp

```tsx
// src/GovernanceDashboard.tsx
import { useState, useEffect } from 'react'
import { useConnection, getObjectWithJson, executeGraphQLQuery } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

const DAO_PACKAGE = "0x_DAO_PACKAGE_"
const TREASURY_ID = "0x_TREASURY_ID_"

interface TreasuryInfo {
  sui_balance: string
  total_distributed: string
  distribution_index: string
  total_ally_supply: string
}

interface Proposal {
  id: string
  description: string
  vote_yes: string
  vote_no: string
  deadline_ms: string
  executed: boolean
}

export function GovernanceDashboard() {
  const { isConnected, handleConnect, currentAddress } = useConnection()
  const dAppKit = useDAppKit()
  const [treasury, setTreasury] = useState<TreasuryInfo | null>(null)
  const [proposals, setProposals] = useState<Proposal[]>([])
  const [allyBalance, setAllyBalance] = useState<number>(0)
  const [claimRecordId, setClaimRecordId] = useState<string | null>(null)
  const [status, setStatus] = useState('')

  // 加载金库数据
  useEffect(() => {
    getObjectWithJson(TREASURY_ID).then(obj => {
      if (obj?.content?.dataType === 'moveObject') {
        setTreasury(obj.content.fields as TreasuryInfo)
      }
    })
  }, [])

  // 领取分红
  const claimDividends = async () => {
    if (!claimRecordId) {
      setStatus('⚠️ 请先创建领取凭证')
      return
    }
    const tx = new Transaction()
    tx.moveCall({
      target: `${DAO_PACKAGE}::treasury::claim_dividends`,
      arguments: [
        tx.object(TREASURY_ID),
        tx.object('ALLY_COIN_ID'), // 用户的 ALLY Coin 对象 ID
        tx.object(claimRecordId),
      ],
    })
    try {
      const r = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ 分红已领取！ ${r.digest.slice(0, 12)}...`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  // 投票
  const vote = async (proposalId: string, support: boolean) => {
    const tx = new Transaction()
    tx.moveCall({
      target: `${DAO_PACKAGE}::governance::vote`,
      arguments: [
        tx.object(proposalId),
        tx.object('ALLY_COIN_ID'), // 用户的 ALLY Coin 对象 ID
        tx.pure.bool(support),
        tx.object('0x6'), // Clock
      ],
    })
    try {
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ 投票成功`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="governance-dashboard">
      <header>
        <h1>🏛 联盟 DAO 治理中心</h1>
        {!isConnected
          ? <button onClick={handleConnect}>连接钱包</button>
          : <span>✅ {currentAddress?.slice(0, 8)}...</span>
        }
      </header>

      {/* 金库状态 */}
      <section className="treasury-panel">
        <h2>💰 联盟金库</h2>
        <div className="stats-grid">
          <div className="stat">
            <span className="label">当前余额</span>
            <span className="value">
              {((Number(treasury?.sui_balance ?? 0)) / 1e9).toFixed(2)} SUI
            </span>
          </div>
          <div className="stat">
            <span className="label">历史分红总额</span>
            <span className="value">
              {((Number(treasury?.total_distributed ?? 0)) / 1e9).toFixed(2)} SUI
            </span>
          </div>
          <div className="stat">
            <span className="label">分红轮次</span>
            <span className="value">{treasury?.distribution_index ?? '-'}</span>
          </div>
          <div className="stat">
            <span className="label">你的 ALLY 持仓</span>
            <span className="value">{(allyBalance / 1e6).toFixed(2)} ALLY</span>
          </div>
        </div>
        <button className="claim-btn" onClick={claimDividends} disabled={!isConnected}>
          💸 领取待领分红
        </button>
      </section>

      {/* 治理提案 */}
      <section className="proposals-panel">
        <h2>🗳 当前提案</h2>
        {proposals.length === 0
          ? <p>暂无进行中的提案</p>
          : proposals.map(p => {
            const total = Number(p.vote_yes) + Number(p.vote_no)
            const yesPct = total > 0 ? Math.round(Number(p.vote_yes) * 100 / total) : 0
            const expired = Date.now() > Number(p.deadline_ms)
            return (
              <div key={p.id} className="proposal-card">
                <p className="proposal-desc">{p.description}</p>
                <div className="vote-bar">
                  <div className="yes-bar" style={{ width: `${yesPct}%` }} />
                </div>
                <div className="vote-stats">
                  <span>✅ {(Number(p.vote_yes) / 1e6).toFixed(0)} ALLY</span>
                  <span>❌ {(Number(p.vote_no) / 1e6).toFixed(0)} ALLY</span>
                </div>
                {!expired && !p.executed && (
                  <div className="vote-actions">
                    <button onClick={() => vote(p.id, true)}>👍 支持</button>
                    <button onClick={() => vote(p.id, false)}>👎 反对</button>
                  </div>
                )}
                {expired && <span className="badge">投票结束</span>}
              </div>
            )
          })
        }
      </section>

      {status && <div className="status-bar">{status}</div>}
    </div>
  )
}
```

---

## 🎯 完整回顾

```
Move 合约层
├── ally_token.move          → 发行 ALLY_TOKEN（总量受 TreasuryCap 控制）
├── treasury.move
│   ├── AllianceTreasury     → 共享金库对象，接收多渠道收入
│   ├── DividendClaim        → 持有者的领取凭证（记录已领轮次）
│   ├── deposit_revenue()    ← 星门/市场合约调用
│   ├── trigger_distribution() ← 管理员触发，按快照准备分红
│   └── claim_dividends()    ← 持有者自助领取
└── governance.move
    ├── Proposal             → 治理提案共享对象
    ├── create_proposal()    ← 持有 1000+ ALLY 才能发起
    └── vote()               ← ALLY 持量加权投票

与其他设施集成
└── 在 example-02 的 toll_gate.move 中调用
    treasury::deposit_revenue(alliance_treasury, fee_coin)
    → 星门收费直接进入联盟金库

dApp 层
└── GovernanceDashboard.tsx
    ├── 金库余额与分红历史统计
    ├── 一键领取分红
    └── 提案列表 + 投票
```

---

## 🔧 扩展练习

1. **防双投**：一次分红周期内每个地址只能投一票（在 proposal 上维护 `voted_addresses: Table<address, bool>`）
2. **锁仓增益**：持仓超过 30 天的地址，分红加权 1.2x（需要存储持仓时间戳）
3. **多资产支持**：金库同时接受 SUI 和 LUX，分红也按比例两种代币发放
4. **自动执行提案**：提案通过后，合约自动执行修改费率等操作（需 Governor 多签）

---

## 📚 关联文档

- [Chapter 8：链上经济系统设计](./chapter-08.md)
- [Chapter 7：动态字段与事件](./chapter-07.md)
- [Sui Coin 标准](https://docs.sui.io/guides/developer/sui-101/create-coin)
- [Example 2: 星门收费站](./example-02.md)（收入来源）
