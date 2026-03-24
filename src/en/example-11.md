# Practical Case 11: Item Rental System (Rent Instead of Sell)

> **Objective:** Build an on-chain item rental marketplace—item owners rent out instead of selling equipment, renters have usage rights during the validity period, and items are automatically returned after expiration (or can be redeemed).

---

> Status: Teaching example. The main text explains the core business flow, complete directory is based on local `book/src/code/example-11/`.

## Corresponding Code Directory

- [example-11](./code/example-11)
- [example-11/dapp](./code/example-11/dapp)

## Minimal Call Chain

`Create listing -> User rents -> Contract mints RentalPass -> Expiration or early return -> Fund settlement`

## Test Loop

- Listing creation: Confirm `is_available == true`, and can be correctly queried by frontend
- Successful rental: Confirm renter receives `RentalPass`, owner receives 70% rent
- Early return: Confirm refund is calculated based on remaining days, remaining deposit correctly flows to owner
- Expiration reclaim: Confirm reclaim fails before expiration, succeeds after expiration

## Requirements Analysis

**Scenario:** High-end ship modules are expensive, most players can't afford them, but can rent them:

- Owner locks module into rental contract, sets daily rent and maximum rental period
- Renter pays rent, receives temporary **usage rights credential NFT** (`RentalPass`)
- Usage rights credential carries expiration timestamp, contract verifies validity when used
- After expiration, owner can reclaim the module (or renew)
- If renter returns early, refund remaining days' rent

---

## Part One: Rental Contract

```move
module rental::equipment_rental;

use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::String;

// ── Constants ──────────────────────────────────────────────────

const DAY_MS: u64 = 86_400_000;

// ── Data Structures ───────────────────────────────────────────────

/// Rental listing (locks item)
public struct RentalListing has key {
    id: UID,
    item_id: ID,              // Rented item object ID
    item_name: String,
    owner: address,
    daily_rate_sui: u64,      // Daily rent (MIST)
    max_days: u64,            // Maximum rental period
    deposited_balance: Balance<SUI>, // Owner's pre-deposited security deposit (optional)
    is_available: bool,
    current_renter: option::Option<address>,
    lease_expires_ms: u64,
}

/// Rental pass NFT (held by renter)
public struct RentalPass has key, store {
    id: UID,
    listing_id: ID,
    item_name: String,
    renter: address,
    expires_ms: u64,
    prepaid_days: u64,
    refundable_balance: Balance<SUI>, // Refundable balance (for early return)
}

// ── Events ──────────────────────────────────────────────────

public struct ItemRented has copy, drop {
    listing_id: ID,
    renter: address,
    days: u64,
    total_paid: u64,
    expires_ms: u64,
}

public struct ItemReturned has copy, drop {
    listing_id: ID,
    renter: address,
    early: bool,
    refund_amount: u64,
}

// ── Owner Operations ────────────────────────────────────────────

/// Create rental listing
public fun create_listing(
    item_name: vector<u8>,
    tracked_item_id: ID,       // Item's Object ID (contract tracks, actual item in SSU)
    daily_rate_sui: u64,
    max_days: u64,
    ctx: &mut TxContext,
) {
    let listing = RentalListing {
        id: object::new(ctx),
        item_id: tracked_item_id,
        item_name: std::string::utf8(item_name),
        owner: ctx.sender(),
        daily_rate_sui,
        max_days,
        deposited_balance: balance::zero(),
        is_available: true,
        current_renter: option::none(),
        lease_expires_ms: 0,
    };
    transfer::share_object(listing);
}

/// Delist (can only withdraw when item is not rented)
public fun delist(
    listing: &mut RentalListing,
    ctx: &TxContext,
) {
    assert!(listing.owner == ctx.sender(), ENotOwner);
    assert!(listing.is_available, EItemCurrentlyRented);
    listing.is_available = false;
}

// ── Renter Operations ────────────────────────────────────────────

/// Rent item
public fun rent_item(
    listing: &mut RentalListing,
    days: u64,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(listing.is_available, ENotAvailable);
    assert!(days >= 1 && days <= listing.max_days, EInvalidDays);

    let total_cost = listing.daily_rate_sui * days;
    assert!(coin::value(&payment) >= total_cost, EInsufficientPayment);

    let expires_ms = clock.timestamp_ms() + days * DAY_MS;

    // Deduct rent
    let rent_payment = payment.split(total_cost, ctx);
    // Send 70% to owner, remaining 30% locked in RentalPass as deposit (refunded on early return)
    let owner_share = rent_payment.split(total_cost * 70 / 100, ctx);
    transfer::public_transfer(owner_share, listing.owner);

    // Update listing state
    listing.is_available = false;
    listing.current_renter = option::some(ctx.sender());
    listing.lease_expires_ms = expires_ms;

    // Issue RentalPass NFT
    let pass = RentalPass {
        id: object::new(ctx),
        listing_id: object::id(listing),
        item_name: listing.item_name,
        renter: ctx.sender(),
        expires_ms,
        prepaid_days: days,
        refundable_balance: coin::into_balance(rent_payment), // Remaining 30%
    };

    // Return change
    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else { coin::destroy_zero(payment); }

    transfer::public_transfer(pass, ctx.sender());

    event::emit(ItemRented {
        listing_id: object::id(listing),
        renter: ctx.sender(),
        days,
        total_paid: total_cost,
        expires_ms,
    });
}

/// Verify rental validity when using item
public fun verify_rental(
    pass: &RentalPass,
    listing_id: ID,
    clock: &Clock,
): bool {
    pass.listing_id == listing_id
        && clock.timestamp_ms() <= pass.expires_ms
}

/// Early return (refund deposit)
public fun return_early(
    listing: &mut RentalListing,
    mut pass: RentalPass,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(pass.listing_id == object::id(listing), EWrongListing);
    assert!(pass.renter == ctx.sender(), ENotRenter);
    assert!(clock.timestamp_ms() < pass.expires_ms, EAlreadyExpired);

    // Calculate refund for remaining days
    let remaining_ms = pass.expires_ms - clock.timestamp_ms();
    let remaining_days = remaining_ms / DAY_MS;
    let refund = if remaining_days > 0 {
        balance::value(&pass.refundable_balance) * remaining_days / pass.prepaid_days
    } else { 0 };

    // Refund
    if refund > 0 {
        let refund_coin = coin::take(&mut pass.refundable_balance, refund, ctx);
        transfer::public_transfer(refund_coin, ctx.sender());
    };

    // Destroy remaining deposit to owner
    let remaining_bal = balance::withdraw_all(&mut pass.refundable_balance);
    if balance::value(&remaining_bal) > 0 {
        transfer::public_transfer(coin::from_balance(remaining_bal, ctx), listing.owner);
    } else { balance::destroy_zero(remaining_bal); }

    // Return listing availability
    listing.is_available = true;
    listing.current_renter = option::none();

    let RentalPass { id, refundable_balance, .. } = pass;
    balance::destroy_zero(refundable_balance);
    id.delete();

    event::emit(ItemReturned {
        listing_id: object::id(listing),
        renter: ctx.sender(),
        early: true,
        refund_amount: refund,
    });
}

/// After rental expires, owner reclaims control
public fun reclaim_after_expiry(
    listing: &mut RentalListing,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(listing.owner == ctx.sender(), ENotOwner);
    assert!(!listing.is_available, EAlreadyAvailable);
    assert!(clock.timestamp_ms() > listing.lease_expires_ms, ELeaseNotExpired);

    listing.is_available = true;
    listing.current_renter = option::none();
}

// ── Error Codes ────────────────────────────────────────────────
const ENotOwner: u64 = 0;
const EItemCurrentlyRented: u64 = 1;
const ENotAvailable: u64 = 2;
const EInvalidDays: u64 = 3;
const EInsufficientPayment: u64 = 4;
const EWrongListing: u64 = 5;
const ENotRenter: u64 = 6;
const EAlreadyExpired: u64 = 7;
const EAlreadyAvailable: u64 = 8;
const ELeaseNotExpired: u64 = 9;
```

---

## Part Two: Rental Market dApp

```tsx
// src/RentalMarket.tsx
import { useState } from 'react'
import { useCurrentClient } from '@mysten/dapp-kit-react'
import { useQuery } from '@tanstack/react-query'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const RENTAL_PKG = "0x_RENTAL_PACKAGE_"

interface Listing {
  id: string
  item_name: string
  owner: string
  daily_rate_sui: string
  max_days: string
  is_available: boolean
  lease_expires_ms: string
}

function DaysLeftBadge({ expireMs }: { expireMs: number }) {
  const remaining = Math.max(0, expireMs - Date.now())
  const days = Math.ceil(remaining / 86400000)
  if (days === 0) return <span className="badge badge--expired">Expired</span>
  return <span className="badge badge--active">{days} days remaining</span>
}

export function RentalMarket() {
  const client = useCurrentClient()
  const dAppKit = useDAppKit()
  const [rentDays, setRentDays] = useState(1)
  const [status, setStatus] = useState('')

  const { data: listings } = useQuery({
    queryKey: ['rental-listings'],
    queryFn: async () => {
      // Teaching example: directly read current listing objects.
      // Real projects should maintain "rentable listing" view through indexer, rather than reverse listing from rental events.
      const objects = await client.getOwnedObjects({
        owner: '0x_RENTAL_REGISTRY_OWNER_',
        filter: { StructType: `${RENTAL_PKG}::equipment_rental::RentalListing` },
        options: { showContent: true },
      })
      return objects.data.map(obj => (obj.data?.content as any)?.fields).filter(Boolean) as Listing[]
    },
  })

  const handleRent = async (listingId: string, dailyRate: number) => {
    const tx = new Transaction()
    const totalCost = BigInt(dailyRate * rentDays)
    const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(totalCost)])

    tx.moveCall({
      target: `${RENTAL_PKG}::equipment_rental::rent_item`,
      arguments: [
        tx.object(listingId),
        tx.pure.u64(rentDays),
        payment,
        tx.object('0x6'),
      ],
    })

    try {
      setStatus('Submitting rental transaction...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('Rental successful! RentalPass sent to your wallet')
    } catch (e: any) {
      setStatus(`${e.message}`)
    }
  }

  return (
    <div className="rental-market">
      <h1>Equipment Rental Market</h1>
      <p className="subtitle">Rent instead of buy, flexibly use high-end equipment</p>

      <div className="rent-days-selector">
        <label>Rental Period:</label>
        {[1, 3, 7, 14, 30].map(d => (
          <button
            key={d}
            className={rentDays === d ? 'selected' : ''}
            onClick={() => setRentDays(d)}
          >
            {d} days
          </button>
        ))}
      </div>

      <div className="listings-grid">
        {listings?.map(listing => (
          <div key={listing.id} className="listing-card">
            <h3>{listing.item_name}</h3>
            <div className="listing-meta">
              <span>{Number(listing.daily_rate_sui) / 1e9} SUI/day</span>
              <span>Max {listing.max_days} days</span>
            </div>
            <div className="listing-cost">
              Rent {rentDays} days total: <strong>{Number(listing.daily_rate_sui) * rentDays / 1e9} SUI</strong>
            </div>
            {listing.is_available ? (
              <button
                className="rent-btn"
                onClick={() => handleRent(listing.id, Number(listing.daily_rate_sui))}
              >
                Rent Now
              </button>
            ) : (
              <DaysLeftBadge expireMs={Number(listing.lease_expires_ms)} />
            )}
          </div>
        ))}
      </div>

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## Key Design Highlights

| Mechanism | Implementation |
|------|---------|
| Time control | `RentalPass.expires_ms` + `clock.timestamp_ms()` real-time verification |
| Deposit management | 30% rent locked in `RentalPass.refundable_balance` |
| Early return | Refund based on remaining days proportion, rest goes to owner |
| Expiration reclaim | `reclaim_after_expiry()` called by owner after expiration |
| Double rental prevention | `is_available` flag ensures only one renter at a time |

## Related Documentation
- [Chapter 12: Dynamic Fields and Balance Management](./chapter-12.md)
- [Chapter 14: Economic System Design](./chapter-14.md)
