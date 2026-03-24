# Practical Case 12: Alliance Recruitment System (Application → Voting → Approval)

> **Objective:** Build a complete alliance joining process: candidates submit applications → existing members vote → approval when threshold is reached and member NFT is issued; can also set founder veto power.

---

> Status: Teaching example. The main text shows the minimum business loop for alliance recruitment, complete code is based on `book/src/code/example-12/`.

## Corresponding Code Directory

- [example-12](./code/example-12)
- [example-12/dapp](./code/example-12/dapp)

## Minimal Call Chain

`User applies -> Members vote -> Vote count reaches threshold -> Issue MemberNFT or confiscate deposit`

## Requirements Analysis

**Scenario:** Alliance "Death Vanguard" has 20 members, each time accepting new members requires:

1. Applicant deposits 10 SUI (prevents spam applications, refunded on approval)
2. Existing members vote within 72 hours (anonymous, recorded on-chain)
3. Automatically approve if supporting votes ≥ 60%, issue MemberNFT
4. Founder has veto power (`veto`)
5. When rejected, deposit is confiscated and goes to alliance treasury

---

## Part One: Alliance Recruitment Contract

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

// ── Constants ──────────────────────────────────────────────────

const VOTE_WINDOW_MS: u64 = 72 * 60 * 60 * 1000; // 72 hours
const APPROVAL_THRESHOLD_BPS: u64 = 6_000;         // 60%
const APPLICATION_DEPOSIT: u64 = 10_000_000_000;   // 10 SUI

// ── Data Structures ───────────────────────────────────────────────

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
    voters: vector<address>,  // Prevent duplicate voting
    deposit: Balance<SUI>,
    status: u8,  // 0=pending, 1=approved, 2=rejected, 3=vetoed
}

/// Member NFT
public struct MemberNFT has key, store {
    id: UID,
    alliance_name: String,
    member: address,
    joined_at_ms: u64,
    serial_number: u64,
}

public struct FounderCap has key, store { id: UID }

// ── Events ──────────────────────────────────────────────────

public struct ApplicationSubmitted has copy, drop { applicant: address, alliance_id: ID }
public struct VoteCast has copy, drop { applicant: address, voter: address, approve: bool }
public struct ApplicationResolved has copy, drop {
    applicant: address,
    approved: bool,
    votes_for: u64,
    votes_total: u64,
}

// ── Initialization ────────────────────────────────────────────────

public fun create_alliance(
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

    // Founder gets MemberNFT (serial #1)
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

// ── Apply for Membership ──────────────────────────────────────────────

public fun apply(
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

// ── Member Voting ──────────────────────────────────────────────

public fun vote(
    dao: &mut AllianceDAO,
    applicant: address,
    approve: bool,
    _member_nft: &MemberNFT,  // Must hold NFT to vote
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

    // Try auto-settlement if votes are sufficient
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

    // Early settlement condition: approval >= 60% with at least 3 votes, or rejection > 40% covering all members
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
        // Refund deposit
        let deposit = balance::withdraw_all(&mut app.deposit);
        transfer::public_transfer(coin::from_balance(deposit, ctx), applicant);

        // Add to member list and issue NFT
        vector::push_back(&mut dao.members, applicant);
        dao.total_accepted = dao.total_accepted + 1;

        let nft = MemberNFT {
            id: object::new(ctx),
            alliance_name: dao.name,
            member: applicant,
            joined_at_ms: 0, // clock cannot be passed to internal function, simplified handling
            serial_number: dao.total_accepted,
        };
        transfer::public_transfer(nft, applicant);
    } else {
        app.status = 2;
        // Confiscate deposit to treasury
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

/// Founder veto
public fun veto(
    dao: &mut AllianceDAO,
    applicant: address,
    _cap: &FounderCap,
    ctx: &mut TxContext,
) {
    assert!(table::contains(&dao.pending_applications, applicant), ENoApplication);
    let app = table::borrow_mut(&mut dao.pending_applications, applicant);
    assert!(app.status == 0, EApplicationClosed);
    app.status = 3;
    // Confiscate deposit
    let deposit = balance::withdraw_all(&mut app.deposit);
    balance::join(&mut dao.treasury, deposit);
}

// ── Error Codes ────────────────────────────────────────────────

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

## Part Two: Recruitment Management dApp

```tsx
// src/RecruitmentPanel.tsx
import { useState } from 'react'
import { useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react'
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
  const client = useCurrentClient()
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
      setStatus('Submitting application...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('Application submitted! Waiting for member votes (within 72 hours)')
      refetch()
    } catch (e: any) { setStatus(`${e.message}`) }
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
      setStatus('Submitting vote...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`Voted: ${approve ? 'Approve' : 'Reject'}`)
      refetch()
    } catch (e: any) { setStatus(`${e.message}`) }
  }

  const pendingApps = dao?.pending_applications?.fields?.contents ?? []
  const memberCount = dao?.members?.length ?? 0

  return (
    <div className="recruitment-panel">
      <header>
        <h1>{dao?.name ?? '...'} — Recruitment Center</h1>
        <div className="stats">
          <span>Members: {memberCount}</span>
          <span>Pending Applications: {pendingApps.filter((a: any) => a.fields?.value?.fields?.status === '0').length}</span>
        </div>
      </header>

      {/* Apply for Membership */}
      {!isMember && (
        <section className="apply-section">
          <h3>Apply to Join Alliance</h3>
          <p>Requires 10 SUI deposit (refunded on approval). Existing members will vote within 72 hours.</p>
          <button className="apply-btn" onClick={handleApply}>
            Submit Application (10 SUI deposit)
          </button>
        </section>
      )}

      {/* Pending Applications (Members Only) */}
      {isMember && (
        <section className="pending-section">
          <h3>Pending Applications</h3>
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
                  <span className="time-left">{hoursLeft}h remaining</span>
                </div>
                <div className="vote-bar">
                  <div className="vote-fill" style={{ width: `${pct}%` }} />
                  <span>{app.votes_for} Approve / {app.votes_against} Reject ({totalVotes}/{memberCount} voted)</span>
                </div>
                <div className="vote-buttons">
                  <button className="btn-approve" onClick={() => handleVote(entry.fields?.key, true)}>
                    Approve
                  </button>
                  <button className="btn-reject" onClick={() => handleVote(entry.fields?.key, false)}>
                    Reject
                  </button>
                  {isFounder && (
                    <button className="btn-veto" onClick={() => {}}>
                      Veto
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

## Key Design Highlights

| Mechanism | Implementation |
|------|---------|
| Prevent spam applications | 10 SUI deposit, confiscated on rejection |
| Prevent duplicate voting | `voters` vector tracks members who voted |
| Auto settlement | Check if threshold is reached after each vote |
| Veto power | `FounderCap` authorized `veto()` |
| Member credential | `MemberNFT` as voting and permission carrier |

## Related Documentation
- [Chapter 11: Ownership Model](./chapter-11.md)
- [Chapter 14: Economic System and Treasury](./chapter-14.md)
- [Example 5: Alliance DAO](./example-05.md)
