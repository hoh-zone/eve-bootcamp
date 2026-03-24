# Practical Case 15: Decentralized Item Insurance

> **Objective:** Build an on-chain item insurance protocol—players purchase PvP battle damage insurance, if items are destroyed in-game they receive automatic compensation through server proof (AdminACL), claims paid from insurance pool.

---

> Status: Teaching example. The main text emphasizes claims process and fund pool design, complete directory is based on `book/src/code/example-15/`.

## Corresponding Code Directory

- [example-15](./code/example-15)
- [example-15/dapp](./code/example-15/dapp)

## Minimal Call Chain

`User purchases policy -> Server issues battle damage proof -> Contract verifies policy and signature -> Insurance pool pays out`

## Test Loop

- Successful purchase: Confirm 70/30 split of `claims_pool` / `reserve` is correct
- Valid claim within period: Confirm payout equals `coverage_amount`
- Expired claim rejection: Confirm expired policies cannot file claims
- Insufficient claims pool: Confirm no negative balance or duplicate deductions

## Requirements Analysis

**Scenario:** Player brings a rare shield worth 500 SUI into PvP combat. They pay 15 SUI for 30-day item insurance, if the shield is destroyed in battle:

1. Game server records death event
2. Player submits claim application + server signature (AdminACL verification)
3. Contract verifies policy is within validity period, automatically pays out (80% payout rate)

---

## Contract

```move
module insurance::pvp_shield;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::table::{Self, Table};
use sui::transfer;
use sui::event;

// ── Constants ──────────────────────────────────────────────────

const COVERAGE_BPS: u64 = 8_000;        // 80% payout rate
const DAY_MS: u64 = 86_400_000;
const MIN_PREMIUM_BPS: u64 = 300;        // Minimum premium: 3% of coverage/month

// ── Data Structures ───────────────────────────────────────────────

/// Insurance pool (shared)
public struct InsurancePool has key {
    id: UID,
    reserve: Balance<SUI>,       // Reserve fund
    total_collected: u64,        // Total premiums collected
    total_paid_out: u64,         // Total payouts
    claims_pool: Balance<SUI>,   // Dedicated claims pool (70% of premiums)
    admin: address,
}

/// Policy NFT
public struct PolicyNFT has key, store {
    id: UID,
    insured_item_id: ID,          // Insured item ObjectID
    insured_value: u64,           // Coverage amount (SUI)
    coverage_amount: u64,         // Maximum payout (= insured_value × 80%)
    valid_until_ms: u64,          // Expiration date
    is_claimed: bool,
    policy_holder: address,
}

// ── Events ──────────────────────────────────────────────────

public struct PolicyIssued has copy, drop {
    policy_id: ID,
    holder: address,
    insured_item_id: ID,
    coverage: u64,
    expires_ms: u64,
}

public struct ClaimPaid has copy, drop {
    policy_id: ID,
    holder: address,
    amount_paid: u64,
}

// ── Initialization ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::share_object(InsurancePool {
        id: object::new(ctx),
        reserve: balance::zero(),
        total_collected: 0,
        total_paid_out: 0,
        claims_pool: balance::zero(),
        admin: ctx.sender(),
    });
}

// ── Purchase Insurance ──────────────────────────────────────────────

public fun purchase_policy(
    pool: &mut InsurancePool,
    insured_item_id: ID,         // Insured item's ObjectID
    insured_value: u64,           // Declared coverage amount
    days: u64,                    // Insurance days (1-90)
    mut premium: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(days >= 1 && days <= 90, EInvalidDuration);

    // Calculate premium: insured_value × monthly rate × days
    let monthly_premium = insured_value * MIN_PREMIUM_BPS / 10_000;
    let required_premium = monthly_premium * days / 30;
    assert!(coin::value(&premium) >= required_premium, EInsufficientPremium);

    let pay = premium.split(required_premium, ctx);
    let premium_amount = coin::value(&pay);

    // 70% to claims pool, 30% to reserve
    let claims_share = premium_amount * 70 / 100;
    let reserve_share = premium_amount - claims_share;

    let mut pay_balance = coin::into_balance(pay);
    let claims_portion = balance::split(&mut pay_balance, claims_share);
    balance::join(&mut pool.claims_pool, claims_portion);
    balance::join(&mut pool.reserve, pay_balance);
    pool.total_collected = pool.total_collected + premium_amount;

    if coin::value(&premium) > 0 {
        transfer::public_transfer(premium, ctx.sender());
    } else { coin::destroy_zero(premium); }

    let coverage = insured_value * COVERAGE_BPS / 10_000;
    let valid_until_ms = clock.timestamp_ms() + days * DAY_MS;

    let policy = PolicyNFT {
        id: object::new(ctx),
        insured_item_id,
        insured_value,
        coverage_amount: coverage,
        valid_until_ms,
        is_claimed: false,
        policy_holder: ctx.sender(),
    };
    let policy_id = object::id(&policy);

    transfer::public_transfer(policy, ctx.sender());

    event::emit(PolicyIssued {
        policy_id,
        holder: ctx.sender(),
        insured_item_id,
        coverage,
        expires_ms: valid_until_ms,
    });
}

// ── File Claim (requires game server signature proving item destruction) ────────────

public fun file_claim(
    pool: &mut InsurancePool,
    policy: &mut PolicyNFT,
    admin_acl: &AdminACL,   // Game server verifies item is actually destroyed
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Verify server signature (i.e., server confirms item has been destroyed)
    verify_sponsor(admin_acl, ctx);

    assert!(!policy.is_claimed, EAlreadyClaimed);
    assert!(clock.timestamp_ms() <= policy.valid_until_ms, EPolicyExpired);
    assert!(policy.policy_holder == ctx.sender(), ENotPolicyHolder);

    // Check if claims pool has sufficient balance
    let payout = policy.coverage_amount;
    assert!(balance::value(&pool.claims_pool) >= payout, EInsufficientClaimsPool);

    // Mark as claimed (prevent duplicate claims)
    policy.is_claimed = true;

    // Payout
    let payout_coin = coin::take(&mut pool.claims_pool, payout, ctx);
    pool.total_paid_out = pool.total_paid_out + payout;
    transfer::public_transfer(payout_coin, ctx.sender());

    event::emit(ClaimPaid {
        policy_id: object::id(policy),
        holder: ctx.sender(),
        amount_paid: payout,
    });
}

/// Admin replenishes claims pool from reserve (when claims pool is insufficient)
public fun replenish_claims_pool(
    pool: &mut InsurancePool,
    amount: u64,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == pool.admin, ENotAdmin);
    assert!(balance::value(&pool.reserve) >= amount, EInsufficientReserve);
    let replenish = balance::split(&mut pool.reserve, amount);
    balance::join(&mut pool.claims_pool, replenish);
}

const EInvalidDuration: u64 = 0;
const EInsufficientPremium: u64 = 1;
const EAlreadyClaimed: u64 = 2;
const EPolicyExpired: u64 = 3;
const ENotPolicyHolder: u64 = 4;
const EInsufficientClaimsPool: u64 = 5;
const ENotAdmin: u64 = 6;
const EInsufficientReserve: u64 = 7;
```

---

## dApp (Purchase and Claims)

```tsx
// InsuranceApp.tsx
import { useState } from 'react'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const INS_PKG = "0x_INSURANCE_PACKAGE_"
const POOL_ID = "0x_POOL_ID_"

export function InsuranceApp() {
  const dAppKit = useDAppKit()
  const [value, setValue] = useState(500) // Coverage amount (SUI)
  const [days, setDays] = useState(30)
  const [status, setStatus] = useState('')

  // Premium calculation
  const premium = (value * 0.03 * days / 30).toFixed(2)
  const coverage = (value * 0.8).toFixed(2)

  const purchase = async () => {
    const tx = new Transaction()
    const premiumMist = BigInt(Math.ceil(Number(premium) * 1e9))
    const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(premiumMist)])
    tx.moveCall({
      target: `${INS_PKG}::pvp_shield::purchase_policy`,
      arguments: [
        tx.object(POOL_ID),
        tx.pure.id('0x_ITEM_OBJECT_ID_'),
        tx.pure.u64(value * 1e9),
        tx.pure.u64(days),
        payment,
        tx.object('0x6'),
      ],
    })
    try {
      setStatus('Purchasing insurance...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('Policy activated! PolicyNFT sent to wallet')
    } catch (e: any) { setStatus(`${e.message}`) }
  }

  return (
    <div className="insurance-app">
      <h1>PvP Item Battle Damage Insurance</h1>
      <div className="config-section">
        <label>Coverage Amount (SUI)</label>
        <input type="range" min={100} max={5000} step={50}
          value={value} onChange={e => setValue(Number(e.target.value))} />
        <span>{value} SUI</span>

        <label>Insurance Days</label>
        {[7, 14, 30, 60, 90].map(d => (
          <button key={d} className={days === d ? 'selected' : ''} onClick={() => setDays(d)}>
            {d} days
          </button>
        ))}
      </div>

      <div className="summary-card">
        <div className="summary-row">
          <span>Coverage</span><strong>{value} SUI</strong>
        </div>
        <div className="summary-row">
          <span>Maximum Payout</span><strong>{coverage} SUI</strong>
        </div>
        <div className="summary-row">
          <span>Premium</span><strong>{premium} SUI</strong>
        </div>
        <div className="summary-row">
          <span>Valid Period</span><strong>{days} days</strong>
        </div>
      </div>

      <button className="purchase-btn" onClick={purchase}>
        Purchase Insurance ({premium} SUI)
      </button>
      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## Related Documentation
- [Chapter 8: Sponsored Transactions and AdminACL Verification](./chapter-08.md)
- [Chapter 14: Economic System and Fund Pools](./chapter-14.md)
