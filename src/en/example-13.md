# Practical Case 13: Subscription Pass (Monthly Unlimited Jumps)

> **Objective:** Establish a subscription pass system—players pay a fixed SUI monthly for unlimited jumping rights in your alliance stargate network, no need to purchase tickets each time.

---

> Status: Teaching example. The main text focuses on subscription model, complete directory is based on `book/src/code/example-13/`.

## Corresponding Code Directory

- [example-13](./code/example-13)
- [example-13/dapp](./code/example-13/dapp)

## Minimal Call Chain

`Select plan -> Pay subscription fee -> Mint/update GatePassNFT -> Stargate verifies pass validity`

## Requirements Analysis

**Scenario:** Your alliance controls 5 stargates and wants to establish a monthly membership system:

- **Monthly Pass**: 30 SUI/month, unlimited jumps through all stargates
- **Quarterly Pass**: 80 SUI/quarter, with discount
- After expiration, renewal required, otherwise downgrade to pay-per-use
- Subscription NFT is transferable (players can trade on secondary market)

---

## Contract

```move
module subscription::gate_pass;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::String;

// ── Constants ──────────────────────────────────────────────────

const MONTH_MS: u64 = 30 * 24 * 60 * 60 * 1000;

/// Plan types
const PLAN_MONTHLY: u8 = 0;
const PLAN_QUARTERLY: u8 = 1;

// ── Data Structures ───────────────────────────────────────────────

/// Subscription manager (shared object)
public struct SubscriptionManager has key {
    id: UID,
    monthly_price: u64,     // Monthly plan price (MIST)
    quarterly_price: u64,   // Quarterly plan price
    revenue: Balance<SUI>,
    admin: address,
    total_subscribers: u64,
}

/// Subscription NFT (transferable, holding grants permission)
public struct GatePassNFT has key, store {
    id: UID,
    plan: u8,
    valid_until_ms: u64,
    subscriber: address,  // Original subscriber
    serial_number: u64,
}

// ── Events ──────────────────────────────────────────────────

public struct PassPurchased has copy, drop {
    pass_id: ID,
    buyer: address,
    plan: u8,
    valid_until_ms: u64,
}

public struct PassRenewed has copy, drop {
    pass_id: ID,
    new_expiry_ms: u64,
}

// ── Initialization ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::share_object(SubscriptionManager {
        id: object::new(ctx),
        monthly_price: 30_000_000_000,   // 30 SUI
        quarterly_price: 80_000_000_000, // 80 SUI (10 SUI cheaper than 3 months)
        revenue: balance::zero(),
        admin: ctx.sender(),
        total_subscribers: 0,
    });
}

// ── Purchase Subscription ──────────────────────────────────────────────

public fun purchase_pass(
    mgr: &mut SubscriptionManager,
    plan: u8,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (price, duration_ms) = if plan == PLAN_MONTHLY {
        (mgr.monthly_price, MONTH_MS)
    } else if plan == PLAN_QUARTERLY {
        (mgr.quarterly_price, 3 * MONTH_MS)
    } else abort EInvalidPlan;

    assert!(coin::value(&payment) >= price, EInsufficientPayment);

    let pay = payment.split(price, ctx);
    balance::join(&mut mgr.revenue, coin::into_balance(pay));

    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else { coin::destroy_zero(payment); }

    mgr.total_subscribers = mgr.total_subscribers + 1;
    let valid_until_ms = clock.timestamp_ms() + duration_ms;

    let pass = GatePassNFT {
        id: object::new(ctx),
        plan,
        valid_until_ms,
        subscriber: ctx.sender(),
        serial_number: mgr.total_subscribers,
    };
    let pass_id = object::id(&pass);

    transfer::public_transfer(pass, ctx.sender());

    event::emit(PassPurchased {
        pass_id,
        buyer: ctx.sender(),
        plan,
        valid_until_ms,
    });
}

/// Renew (extend validity period of existing Pass)
public fun renew_pass(
    mgr: &mut SubscriptionManager,
    pass: &mut GatePassNFT,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (price, duration_ms) = if pass.plan == PLAN_MONTHLY {
        (mgr.monthly_price, MONTH_MS)
    } else {
        (mgr.quarterly_price, 3 * MONTH_MS)
    };

    assert!(coin::value(&payment) >= price, EInsufficientPayment);

    let pay = payment.split(price, ctx);
    balance::join(&mut mgr.revenue, coin::into_balance(pay));
    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else { coin::destroy_zero(payment); }

    // If already expired, start from now, otherwise stack on original expiry time
    let base = if pass.valid_until_ms < clock.timestamp_ms() {
        clock.timestamp_ms()
    } else { pass.valid_until_ms };

    pass.valid_until_ms = base + duration_ms;

    event::emit(PassRenewed {
        pass_id: object::id(pass),
        new_expiry_ms: pass.valid_until_ms,
    });
}

/// Stargate extension: verify Pass validity
public fun is_pass_valid(pass: &GatePassNFT, clock: &Clock): bool {
    clock.timestamp_ms() <= pass.valid_until_ms
}

/// Stargate jump (unlimited jumps with valid Pass)
public fun subscriber_jump(
    gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    pass: &GatePassNFT,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(is_pass_valid(pass, clock), EPassExpired);
    gate::issue_jump_permit(
        gate, dest_gate, character, SubscriberAuth {},
        clock.timestamp_ms() + 30 * 60 * 1000, ctx,
    );
}

public struct SubscriberAuth has drop {}

/// Admin withdraw revenue
public fun withdraw_revenue(
    mgr: &mut SubscriptionManager,
    amount: u64,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == mgr.admin, ENotAdmin);
    let coin = coin::take(&mut mgr.revenue, amount, ctx);
    transfer::public_transfer(coin, mgr.admin);
}

const EInvalidPlan: u64 = 0;
const EInsufficientPayment: u64 = 1;
const EPassExpired: u64 = 2;
const ENotAdmin: u64 = 3;
```

---

## dApp

```tsx
// PassShop.tsx
import { useState } from 'react'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const SUB_PKG = "0x_SUBSCRIPTION_PACKAGE_"
const MGR_ID = "0x_MANAGER_ID_"

const PLANS = [
  { id: 0, name: 'Monthly Plan', price: 30, duration: '30 days', badge: 'Standard' },
  { id: 1, name: 'Quarterly Plan', price: 80, duration: '90 days', badge: 'Save 10 SUI', popular: true },
]

export function PassShop() {
  const dAppKit = useDAppKit()
  const [status, setStatus] = useState('')

  const purchase = async (plan: number, priceInSUI: number) => {
    const tx = new Transaction()
    const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(priceInSUI * 1e9)])
    tx.moveCall({
      target: `${SUB_PKG}::gate_pass::purchase_pass`,
      arguments: [tx.object(MGR_ID), tx.pure.u8(plan), payment, tx.object('0x6')],
    })
    try {
      setStatus('Purchasing...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('Subscription successful! GatePassNFT sent to your wallet')
    } catch (e: any) { setStatus(`${e.message}`) }
  }

  return (
    <div className="pass-shop">
      <h1>Stargate Subscription Pass</h1>
      <p>Unlimited jumps through all alliance stargates with valid pass</p>
      <div className="plan-grid">
        {PLANS.map(plan => (
          <div key={plan.id} className={`plan-card ${plan.popular ? 'popular' : ''}`}>
            {plan.popular && <div className="popular-badge">Recommended</div>}
            <h3>{plan.name}</h3>
            <div className="plan-price">
              <span className="price">{plan.price}</span>
              <span className="unit">SUI</span>
            </div>
            <div className="plan-duration">Valid for {plan.duration}</div>
            <div className="plan-badge">{plan.badge}</div>
            <button className="buy-btn" onClick={() => purchase(plan.id, plan.price)}>
              Purchase {plan.name}
            </button>
          </div>
        ))}
      </div>
      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## Related Documentation
- [Chapter 13: NFT Design and TransferPolicy](./chapter-13.md)
- [Example 2: Stargate Toll Station](./example-02.md)
