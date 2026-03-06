# 实战案例 12：联盟招募系统（申请→投票→批准）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 构建完整的联盟加入流程：候选人提交申请 → 现有成员投票 → 达到阈值自动批准并发放成员 NFT；也可设置创始人一票否决权。

---

## 需求分析

**场景：** 联盟"死亡先锋"有 20 名成员，每次接纳新人需要：

1. 申请人押金 10 SUI（防止刷申请，批准后退还）
2. 现有成员 72 小时内投票（匿名，链上记录）
3. 支持票 ≥ 60% 则自动批准，发放 MemberNFT
4. 创始人有一票否决权（`veto`）
5. 拒绝时押金被没收，进联盟金库

---

## 第一部分：联盟招募合约

```move
module alliance::recruitment;

use sui::table::{Self, Table};
use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::String;

// ── 常量 ──────────────────────────────────────────────────

const VOTE_WINDOW_MS: u64 = 72 * 60 * 60 * 1000; // 72 小时
const APPROVAL_THRESHOLD_BPS: u64 = 6_000;         // 60%
const APPLICATION_DEPOSIT: u64 = 10_000_000_000;   // 10 SUI

// ── 数据结构 ───────────────────────────────────────────────

public struct AllianceDAO has key {
    id: UID,
    name: String,
    founder: address,
    members: vector<address>,
    treasury: Balance<SUI>,
    pending_applications: Table<address, Application>,
    total_accepted: u64,
}

public struct Application has store {
    applicant: address,
    applied_at_ms: u64,
    votes_for: u64,
    votes_against: u64,
    voters: vector<address>,  // 防止重复投票
    deposit: Balance<SUI>,
    status: u8,  // 0=pending, 1=approved, 2=rejected, 3=vetoed
}

/// 成员 NFT
public struct MemberNFT has key, store {
    id: UID,
    alliance_name: String,
    member: address,
    joined_at_ms: u64,
    serial_number: u64,
}

public struct FounderCap has key, store { id: UID }

// ── 事件 ──────────────────────────────────────────────────

public struct ApplicationSubmitted has copy, drop { applicant: address, alliance_id: ID }
public struct VoteCast has copy, drop { applicant: address, voter: address, approve: bool }
public struct ApplicationResolved has copy, drop {
    applicant: address,
    approved: bool,
    votes_for: u64,
    votes_total: u64,
}

// ── 初始化 ────────────────────────────────────────────────

public entry fun create_alliance(
    name: vector<u8>,
    ctx: &mut TxContext,
) {
    let mut dao = AllianceDAO {
        id: object::new(ctx),
        name: std::string::utf8(name),
        founder: ctx.sender(),
        members: vector[ctx.sender()],
        treasury: balance::zero(),
        pending_applications: table::new(ctx),
        total_accepted: 0,
    };

    // 创始人获得 MemberNFT（编号 #1）
    let founder_nft = MemberNFT {
        id: object::new(ctx),
        alliance_name: dao.name,
        member: ctx.sender(),
        joined_at_ms: 0,
        serial_number: 1,
    };
    dao.total_accepted = 1;

    let founder_cap = FounderCap { id: object::new(ctx) };

    transfer::share_object(dao);
    transfer::public_transfer(founder_nft, ctx.sender());
    transfer::public_transfer(founder_cap, ctx.sender());
}

// ── 申请加入 ──────────────────────────────────────────────

public entry fun apply(
    dao: &mut AllianceDAO,
    mut deposit: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let applicant = ctx.sender();
    assert!(!vector::contains(&dao.members, &applicant), EAlreadyMember);
    assert!(!table::contains(&dao.pending_applications, applicant), EAlreadyApplied);
    assert!(coin::value(&deposit) >= APPLICATION_DEPOSIT, EInsufficientDeposit);

    let deposit_balance = deposit.split(APPLICATION_DEPOSIT, ctx);
    if coin::value(&deposit) > 0 {
        transfer::public_transfer(deposit, applicant);
    } else { coin::destroy_zero(deposit); }

    table::add(&mut dao.pending_applications, applicant, Application {
        applicant,
        applied_at_ms: clock.timestamp_ms(),
        votes_for: 0,
        votes_against: 0,
        voters: vector::empty(),
        deposit: coin::into_balance(deposit_balance),
        status: 0,
    });

    event::emit(ApplicationSubmitted { applicant, alliance_id: object::id(dao) });
}

// ── 成员投票 ──────────────────────────────────────────────

public entry fun vote(
    dao: &mut AllianceDAO,
    applicant: address,
    approve: bool,
    _member_nft: &MemberNFT,  // 持有 NFT 才能投票
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(vector::contains(&dao.members, &ctx.sender()), ENotMember);
    assert!(table::contains(&dao.pending_applications, applicant), ENoApplication);

    let app = table::borrow_mut(&mut dao.pending_applications, applicant);
    assert!(app.status == 0, EApplicationClosed);
    assert!(clock.timestamp_ms() <= app.applied_at_ms + VOTE_WINDOW_MS, EVoteWindowClosed);
    assert!(!vector::contains(&app.voters, &ctx.sender()), EAlreadyVoted);

    vector::push_back(&mut app.voters, ctx.sender());
    if approve {
        app.votes_for = app.votes_for + 1;
    } else {
        app.votes_against = app.votes_against + 1;
    };

    event::emit(VoteCast { applicant, voter: ctx.sender(), approve });

    // 若票数已足够，尝试自动结算
    try_resolve(dao, applicant, clock, ctx);
}

fun try_resolve(
    dao: &mut AllianceDAO,
    applicant: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let app = table::borrow(&dao.pending_applications, applicant);
    let total_votes = app.votes_for + app.votes_against;
    let member_count = vector::length(&dao.members);

    // 提前结算条件：赞成 >= 60% 且至少 3 票，或反对 > 40% 且覆盖全员
    let approve_pct = total_votes * 10_000 / member_count;
    let enough_approval = app.votes_for * 10_000 / member_count >= APPROVAL_THRESHOLD_BPS
                          && total_votes >= 3;
    let definite_rejection = app.votes_against * 10_000 / member_count > 4_000
                             && total_votes == member_count;

    let time_expired = clock.timestamp_ms() > app.applied_at_ms + VOTE_WINDOW_MS;

    if enough_approval || time_expired || definite_rejection {
        resolve_application(dao, applicant, ctx);
    }
}

fun resolve_application(
    dao: &mut AllianceDAO,
    applicant: address,
    ctx: &mut TxContext,
) {
    let app = table::borrow_mut(&mut dao.pending_applications, applicant);
    let total_votes = app.votes_for + app.votes_against;
    let approved = total_votes > 0
        && app.votes_for * 10_000 / (total_votes) >= APPROVAL_THRESHOLD_BPS;

    if approved {
        app.status = 1;
        // 退还押金
        let deposit = balance::withdraw_all(&mut app.deposit);
        transfer::public_transfer(coin::from_balance(deposit, ctx), applicant);

        // 加入成员列表并发放 NFT
        vector::push_back(&mut dao.members, applicant);
        dao.total_accepted = dao.total_accepted + 1;

        let nft = MemberNFT {
            id: object::new(ctx),
            alliance_name: dao.name,
            member: applicant,
            joined_at_ms: 0, // clock 无法传进内部函数，简化处理
            serial_number: dao.total_accepted,
        };
        transfer::public_transfer(nft, applicant);
    } else {
        app.status = 2;
        // 没收押金入金库
        let deposit = balance::withdraw_all(&mut app.deposit);
        balance::join(&mut dao.treasury, deposit);
    };

    event::emit(ApplicationResolved {
        applicant,
        approved,
        votes_for: app.votes_for,
        votes_total: total_votes,
    });
}

/// 创始人一票否决
public entry fun veto(
    dao: &mut AllianceDAO,
    applicant: address,
    _cap: &FounderCap,
    ctx: &mut TxContext,
) {
    assert!(table::contains(&dao.pending_applications, applicant), ENoApplication);
    let app = table::borrow_mut(&mut dao.pending_applications, applicant);
    assert!(app.status == 0, EApplicationClosed);
    app.status = 3;
    // 没收押金
    let deposit = balance::withdraw_all(&mut app.deposit);
    balance::join(&mut dao.treasury, deposit);
}

// ── 错误码 ────────────────────────────────────────────────

const EAlreadyMember: u64 = 0;
const EAlreadyApplied: u64 = 1;
const EInsufficientDeposit: u64 = 2;
const ENotMember: u64 = 3;
const ENoApplication: u64 = 4;
const EApplicationClosed: u64 = 5;
const EVoteWindowClosed: u64 = 6;
const EAlreadyVoted: u64 = 7;
```

---

## 第二部分：招募管理 dApp

```tsx
// src/RecruitmentPanel.tsx
import { useState } from 'react'
import { useSuiClient, useCurrentAccount } from '@mysten/dapp-kit'
import { useQuery } from '@tanstack/react-query'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const RECRUIT_PKG = "0x_RECRUIT_PACKAGE_"
const DAO_ID = "0x_DAO_ID_"

interface PendingApp {
  applicant: string
  applied_at_ms: string
  votes_for: string
  votes_against: string
  status: string
}

export function RecruitmentPanel({ isMember, isFounder }: {
  isMember: boolean, isFounder: boolean
}) {
  const client = useSuiClient()
  const dAppKit = useDAppKit()
  const account = useCurrentAccount()
  const [status, setStatus] = useState('')

  const { data: dao, refetch } = useQuery({
    queryKey: ['dao', DAO_ID],
    queryFn: async () => {
      const obj = await client.getObject({ id: DAO_ID, options: { showContent: true } })
      return (obj.data?.content as any)?.fields
    },
    refetchInterval: 15_000,
  })

  const handleApply = async () => {
    const tx = new Transaction()
    const [deposit] = tx.splitCoins(tx.gas, [tx.pure.u64(10_000_000_000)])
    tx.moveCall({
      target: `${RECRUIT_PKG}::recruitment::apply`,
      arguments: [tx.object(DAO_ID), deposit, tx.object('0x6')],
    })
    try {
      setStatus('⏳ 提交申请...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('✅ 申请已提交！等待成员投票（72小时内）')
      refetch()
    } catch (e: any) { setStatus(`❌ ${e.message}`) }
  }

  const handleVote = async (applicant: string, approve: boolean) => {
    const tx = new Transaction()
    tx.moveCall({
      target: `${RECRUIT_PKG}::recruitment::vote`,
      arguments: [
        tx.object(DAO_ID),
        tx.pure.address(applicant),
        tx.pure.bool(approve),
        tx.object('MEMBER_NFT_ID'),
        tx.object('0x6'),
      ],
    })
    try {
      setStatus('⏳ 提交投票...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ 已投票：${approve ? '赞成' : '反对'}`)
      refetch()
    } catch (e: any) { setStatus(`❌ ${e.message}`) }
  }

  const pendingApps = dao?.pending_applications?.fields?.contents ?? []
  const memberCount = dao?.members?.length ?? 0

  return (
    <div className="recruitment-panel">
      <header>
        <h1>⚔️ {dao?.name ?? '...'} — 招募中心</h1>
        <div className="stats">
          <span>👥 成员数：{memberCount}</span>
          <span>📋 待审申请：{pendingApps.filter((a: any) => a.fields?.value?.fields?.status === '0').length}</span>
        </div>
      </header>

      {/* 申请入盟 */}
      {!isMember && (
        <section className="apply-section">
          <h3>申请加入联盟</h3>
          <p>需要押金 10 SUI（批准后退还）。现有成员将在 72 小时内投票。</p>
          <button className="apply-btn" onClick={handleApply}>
            📝 提交申请（押金 10 SUI）
          </button>
        </section>
      )}

      {/* 待审列表（仅成员可见） */}
      {isMember && (
        <section className="pending-section">
          <h3>待审申请</h3>
          {pendingApps.map((entry: any) => {
            const app = entry.fields?.value?.fields
            if (!app || app.status !== '0') return null
            const hoursLeft = Math.max(0,
              Math.ceil((Number(app.applied_at_ms) + 72*3600_000 - Date.now()) / 3_600_000)
            )
            const totalVotes = Number(app.votes_for) + Number(app.votes_against)
            const pct = memberCount > 0 ? Math.round(Number(app.votes_for) * 100 / memberCount) : 0

            return (
              <div key={entry.fields?.key} className="application-card">
                <div className="applicant-info">
                  <strong>{entry.fields?.key?.slice(0, 8)}...</strong>
                  <span className="time-left">⏳ 剩余 {hoursLeft}h</span>
                </div>
                <div className="vote-bar">
                  <div className="vote-fill" style={{ width: `${pct}%` }} />
                  <span>{app.votes_for} 赞成 / {app.votes_against} 反对（{totalVotes}/{memberCount} 人投票）</span>
                </div>
                <div className="vote-buttons">
                  <button className="btn-approve" onClick={() => handleVote(entry.fields?.key, true)}>
                    👍 赞成
                  </button>
                  <button className="btn-reject" onClick={() => handleVote(entry.fields?.key, false)}>
                    👎 反对
                  </button>
                  {isFounder && (
                    <button className="btn-veto" onClick={() => {}}>
                      🚫 否决
                    </button>
                  )}
                </div>
              </div>
            )
          })}
        </section>
      )}

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 🎯 关键设计亮点

| 机制 | 实现方式 |
|------|---------|
| 防刷申请 | 押金 10 SUI，被拒没收 |
| 防重复投票 | `voters` vector 追踪已投成员 |
| 自动结算 | 每次投票后检查是否达到阈值 |
| 一票否决 | `FounderCap` 授权的 `veto()` |
| 成员凭证 | `MemberNFT` 作为投票和权限载体 |

## 📚 关联文档
- [Chapter 6：所有权模型](./chapter-06.md)
- [Chapter 8：经济系统与金库](./chapter-08.md)
- [Example 5：联盟 DAO](./example-05.md)
