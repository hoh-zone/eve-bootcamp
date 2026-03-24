# Example 5: Alliance Token & Automatic Dividend System

> **Goal:** Issue alliance-specific Coin (`ALLY Token`), build an automatic dividend contract - alliance facility revenue automatically distributed to token holders by holding ratio - with governance panel dApp.

---

> Status: Teaching example. Repository includes alliance token, treasury, and governance source code, focusing on understanding how capital flow and governance flow coexist.

## Code Directory

- [example-05](./code/example-05)
- [example-05/dapp](./code/example-05/dapp)

## Minimal Call Chain

`Issue ALLY Token -> Revenue flows to treasury -> Distribute dividends by holdings -> Propose -> Members vote`

## Requirements Analysis

**Scenario:** Your alliance operates multiple gate toll stations and storage box markets, with revenue from multiple channels. You want:

- 💎 Issue `ALLY Token` (total supply 1,000,000), distributed to alliance members by contribution
- 🏦 All facility revenue flows to alliance treasury (Treasury)
- 💸 Members holding `ALLY Token` receive periodic dividends based on holding ratio
- 🗳 Token holders can vote on major alliance decisions (like fee adjustments)
- 📊 Governance panel displays treasury balance, dividend history, proposal list

---

## Part 1: Alliance Token Contract

```move
module ally_dao::ally_token;

use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
use sui::transfer;
use sui::tx_context::TxContext;

/// One-Time Witness
public struct ALLY_TOKEN has drop {}

fun init(witness: ALLY_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        6,                          // Decimals: 6 decimal places
        b"ALLY",                    // Symbol
        b"Alliance Token",          // Name
        b"Governance and dividend token for Alliance X",
        option::none(),
        ctx,
    );

    // TreasuryCap given to alliance DAO contract (via address or multisig)
    transfer::public_transfer(treasury_cap, ctx.sender());
    transfer::public_freeze_object(coin_metadata); // Metadata immutable
}

/// Mint (controlled by DAO contract, not directly exposed to public)
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

## Part 2: DAO Treasury & Dividend Contract

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

// ── Data Structures ──────────────────────────────────────────────

/// Alliance Treasury
public struct AllianceTreasury has key {
    id: UID,
    sui_balance: Balance<SUI>,          // SUI awaiting distribution
    total_distributed: u64,             // Total historical dividends distributed
    distribution_index: u64,            // Current dividend round
    total_ally_supply: u64,             // Current ALLY Token circulating supply
}

/// Dividend claim voucher (records which round each holder claimed to)
public struct DividendClaim has key, store {
    id: UID,
    holder: address,
    last_claimed_index: u64,
}

/// Proposal (governance)
public struct Proposal has key {
    id: UID,
    proposer: address,
    description: vector<u8>,
    vote_yes: u64,      // Yes votes (ALLY Token quantity weighted)
    vote_no: u64,       // No votes
    deadline_ms: u64,
    executed: bool,
}

/// Dividend snapshot (create one per distribution)
public struct DividendSnapshot has store {
    amount_per_token: u64,  // SUI amount per ALLY Token (in minimum precision)
    total_supply_at_snapshot: u64,
}

// ── Events ──────────────────────────────────────────────────

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

// ── Initialization ────────────────────────────────────────────────

public fun create_treasury(
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

// ── Deposit Revenue ──────────────────────────────────────────────

/// Any contract (gate, market, etc.) can deposit revenue to treasury
public fun deposit_revenue(treasury: &mut AllianceTreasury, coin: Coin<SUI>) {
    balance::join(&mut treasury.sui_balance, coin::into_balance(coin));
}

// ── Trigger Distribution ──────────────────────────────────────────

/// Admin triggers: prepare dividend distribution from current treasury balance by ratio
/// Need to store snapshot for each round
public fun trigger_distribution(
    treasury: &mut AllianceTreasury,
    ctx: &TxContext,
) {
    let total = balance::value(&treasury.sui_balance);
    assert!(total > 0, ENoBalance);
    assert!(treasury.total_ally_supply > 0, ENoSupply);

    // Amount per token (in minimum precision, multiply by 1e6 to avoid precision loss)
    let per_token_scaled = total * 1_000_000 / treasury.total_ally_supply;

    treasury.distribution_index = treasury.distribution_index + 1;
    treasury.total_distributed = treasury.total_distributed + total;

    // Store snapshot to dynamic field
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

// ── Holder Claims Dividends ────────────────────────────────────────

/// Holder provides their ALLY Token (not consumed, only read quantity) to claim dividends
public fun claim_dividends(
    treasury: &mut AllianceTreasury,
    ally_coin: &Coin<ALLY_TOKEN>,    // Holder's ALLY Token (read-only)
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
        // Calculate by holding ratio (reverse scaling)
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

/// Create claim record (each holder creates once)
public fun create_claim_record(ctx: &mut TxContext) {
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

## Part 3: Governance Voting Contract

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

/// Create proposal (requires holding at least 1000 ALLY Token)
public fun create_proposal(
    ally_coin: &Coin<ALLY_TOKEN>,
    description: vector<u8>,
    voting_duration_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Must hold enough tokens to propose
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

/// Vote (weighted by ALLY Token quantity)
public fun vote(
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

## Part 4: Governance Dashboard dApp

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

  // Load treasury data
  useEffect(() => {
    getObjectWithJson(TREASURY_ID).then(obj => {
      if (obj?.content?.dataType === 'moveObject') {
        setTreasury(obj.content.fields as TreasuryInfo)
      }
    })
  }, [])

  // Claim dividends
  const claimDividends = async () => {
    if (!claimRecordId) {
      setStatus('⚠️ Please create claim record first')
      return
    }
    const tx = new Transaction()
    tx.moveCall({
      target: `${DAO_PACKAGE}::treasury::claim_dividends`,
      arguments: [
        tx.object(TREASURY_ID),
        tx.object('ALLY_COIN_ID'), // User's ALLY Coin object ID
        tx.object(claimRecordId),
      ],
    })
    try {
      const r = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ Dividends claimed! ${r.digest.slice(0, 12)}...`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  // Vote
  const vote = async (proposalId: string, support: boolean) => {
    const tx = new Transaction()
    tx.moveCall({
      target: `${DAO_PACKAGE}::governance::vote`,
      arguments: [
        tx.object(proposalId),
        tx.object('ALLY_COIN_ID'), // User's ALLY Coin object ID
        tx.pure.bool(support),
        tx.object('0x6'), // Clock
      ],
    })
    try {
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ Vote successful`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="governance-dashboard">
      <header>
        <h1>🏛 Alliance DAO Governance Center</h1>
        {!isConnected
          ? <button onClick={handleConnect}>Connect Wallet</button>
          : <span>✅ {currentAddress?.slice(0, 8)}...</span>
        }
      </header>

      {/* Treasury Status */}
      <section className="treasury-panel">
        <h2>💰 Alliance Treasury</h2>
        <div className="stats-grid">
          <div className="stat">
            <span className="label">Current Balance</span>
            <span className="value">
              {((Number(treasury?.sui_balance ?? 0)) / 1e9).toFixed(2)} SUI
            </span>
          </div>
          <div className="stat">
            <span className="label">Total Distributed</span>
            <span className="value">
              {((Number(treasury?.total_distributed ?? 0)) / 1e9).toFixed(2)} SUI
            </span>
          </div>
          <div className="stat">
            <span className="label">Distribution Rounds</span>
            <span className="value">{treasury?.distribution_index ?? '-'}</span>
          </div>
          <div className="stat">
            <span className="label">Your ALLY Holdings</span>
            <span className="value">{(allyBalance / 1e6).toFixed(2)} ALLY</span>
          </div>
        </div>
        <button className="claim-btn" onClick={claimDividends} disabled={!isConnected}>
          💸 Claim Pending Dividends
        </button>
      </section>

      {/* Governance Proposals */}
      <section className="proposals-panel">
        <h2>🗳 Current Proposals</h2>
        {proposals.length === 0
          ? <p>No active proposals</p>
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
                    <button onClick={() => vote(p.id, true)}>👍 Support</button>
                    <button onClick={() => vote(p.id, false)}>👎 Oppose</button>
                  </div>
                )}
                {expired && <span className="badge">Voting Ended</span>}
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

## 🎯 Complete Review

```
Move Contract Layer
├── ally_token.move          → Issue ALLY_TOKEN (total supply controlled by TreasuryCap)
├── treasury.move
│   ├── AllianceTreasury     → Shared treasury object, receives multi-channel revenue
│   ├── DividendClaim        → Holder's claim voucher (records claimed rounds)
│   ├── deposit_revenue()    ← Gate/market contracts call
│   ├── trigger_distribution() ← Admin triggers, prepares dividends by snapshot
│   └── claim_dividends()    ← Holders self-claim
└── governance.move
    ├── Proposal             → Governance proposal shared object
    ├── create_proposal()    ← Must hold 1000+ ALLY to propose
    └── vote()               ← ALLY holdings weighted voting

Integration with Other Facilities
└── In example-02's toll_gate.move call
    treasury::deposit_revenue(alliance_treasury, fee_coin)
    → Gate toll goes directly to alliance treasury

dApp Layer
└── GovernanceDashboard.tsx
    ├── Treasury balance and dividend history stats
    ├── One-click claim dividends
    └── Proposal list + voting
```

---

## 🔧 Extension Exercises

1. **Prevent Double Voting**: Each address can only vote once per distribution period (maintain `voted_addresses: Table<address, bool>` on proposal)
2. **Lockup Bonus**: Addresses holding for over 30 days get 1.2x dividend weight (need to store holding timestamp)
3. **Multi-Asset Support**: Treasury accepts both SUI and LUX, dividends also distributed proportionally in both tokens
4. **Auto-Execute Proposals**: After proposal passes, contract automatically executes fee rate changes (requires Governor multisig)

---

## 📚 Related Documentation

- [Chapter 14: On-Chain Economic System Design](./chapter-14.md)
- [Chapter 12: Dynamic Fields & Events](./chapter-12.md)
- [Sui Coin Standard](https://docs.sui.io/guides/developer/sui-101/create-coin)
- [Example 2: Gate Toll Station](./example-02.md) (revenue source)
