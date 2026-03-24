# Example 3: On-Chain Auction House (Smart Storage Unit + Dutch Auction)

> **Goal:** Transform a Smart Storage Unit into a Dutch auction (price decreases over time), items automatically transfer to bidders, fully implementing auction contract + bidder dApp + Owner management panel.

---

> Status: Includes contract, dApp, and Move test files. The main content is nearly a complete example, suitable as a "pricing strategy + frontend countdown" demonstration.

## Code Directory

- [example-03](./code/example-03)
- [example-03/dapp](./code/example-03/dapp)

## Minimal Call Chain

`Owner creates auction -> Price decreases over time -> Buyer pays current price -> Auction settles -> Item transfers`

## Requirements Analysis

**Scenario:** You control a smart storage box containing rare ore. Instead of a fixed price, you want to maximize sales revenue through a Dutch auction (price descends from high to low) with more transparent price discovery:

- 🕐 Auction starts at **5000 LUX**
- 📉 Drops **500 LUX** every 10 minutes
- 🏆 **Minimum price is 500 LUX**, price stops dropping
- ⚡ Anyone can buy at the current price at any time, item immediately transfers
- 📊 dApp displays real-time countdown and current price

---

## Part 1: Move Contract

### Directory Structure

```
dutch-auction/
├── Move.toml
└── sources/
    ├── dutch_auction.move    # Dutch auction logic
    └── auction_manager.move  # Auction management (create/end)
```

### Core Contract: `dutch_auction.move`

```move
module dutch_auction::auction;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::object::{Self, UID, ID};
use sui::event;
use sui::transfer;

/// SSU Extension Witness
public struct AuctionAuth has drop {}

/// Auction State
public struct DutchAuction has key {
    id: UID,
    storage_unit_id: ID,        // Bound storage box
    item_type_id: u64,          // Item type being auctioned
    start_price: u64,           // Starting price (MIST)
    end_price: u64,             // Minimum price
    start_time_ms: u64,         // Auction start time
    price_drop_interval_ms: u64, // Price drop interval (milliseconds)
    price_drop_amount: u64,     // Price drop amount per interval
    is_active: bool,            // Whether still ongoing
    proceeds: Balance<SUI>,     // Auction proceeds
    owner: address,             // Auction creator
}

/// Events
public struct AuctionCreated has copy, drop {
    auction_id: ID,
    item_type_id: u64,
    start_price: u64,
    end_price: u64,
}

public struct AuctionSettled has copy, drop {
    auction_id: ID,
    winner: address,
    final_price: u64,
    item_type_id: u64,
}

// ── Calculate Current Price ─────────────────────────────────────────

public fun current_price(auction: &DutchAuction, clock: &Clock): u64 {
    if !auction.is_active {
        return auction.end_price
    }

    let elapsed_ms = clock.timestamp_ms() - auction.start_time_ms;
    let drops = elapsed_ms / auction.price_drop_interval_ms;
    let total_drop = drops * auction.price_drop_amount;

    if total_drop >= auction.start_price - auction.end_price {
        auction.end_price  // Already at minimum price
    } else {
        auction.start_price - total_drop
    }
}

/// Calculate time remaining until next price drop (milliseconds)
public fun ms_until_next_drop(auction: &DutchAuction, clock: &Clock): u64 {
    let elapsed = clock.timestamp_ms() - auction.start_time_ms;
    let interval = auction.price_drop_interval_ms;
    let next_drop_at = (elapsed / interval + 1) * interval;
    next_drop_at - elapsed
}

// ── Create Auction ─────────────────────────────────────────────

public fun create_auction(
    storage_unit: &StorageUnit,
    item_type_id: u64,
    start_price: u64,
    end_price: u64,
    price_drop_interval_ms: u64,
    price_drop_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(start_price > end_price, EInvalidPricing);
    assert!(price_drop_amount > 0, EInvalidDropAmount);
    assert!(price_drop_interval_ms >= 60_000, EIntervalTooShort); // Minimum 1 minute

    let auction = DutchAuction {
        id: object::new(ctx),
        storage_unit_id: object::id(storage_unit),
        item_type_id,
        start_price,
        end_price,
        start_time_ms: clock.timestamp_ms(),
        price_drop_interval_ms,
        price_drop_amount,
        is_active: true,
        proceeds: balance::zero(),
        owner: ctx.sender(),
    };

    event::emit(AuctionCreated {
        auction_id: object::id(&auction),
        item_type_id,
        start_price,
        end_price,
    });

    transfer::share_object(auction);
}

// ── Bid: Pay Current Price to Get Item ──────────────────────────

public fun buy_now(
    auction: &mut DutchAuction,
    storage_unit: &mut StorageUnit,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Item {
    assert!(auction.is_active, EAuctionEnded);

    let price = current_price(auction, clock);
    assert!(coin::value(&payment) >= price, EInsufficientPayment);

    // Return overpayment
    let change_amount = coin::value(&payment) - price;
    if change_amount > 0 {
        let change = payment.split(change_amount, ctx);
        transfer::public_transfer(change, ctx.sender());
    }

    // Revenue goes to auction treasury
    balance::join(&mut auction.proceeds, coin::into_balance(payment));
    auction.is_active = false;

    event::emit(AuctionSettled {
        auction_id: object::id(auction),
        winner: ctx.sender(),
        final_price: price,
        item_type_id: auction.item_type_id,
    });

    // Withdraw item from SSU
    storage_unit::withdraw_item(
        storage_unit,
        character,
        AuctionAuth {},
        auction.item_type_id,
        ctx,
    )
}

// ── Owner: Withdraw Auction Proceeds ──────────────────────────────────

public fun withdraw_proceeds(
    auction: &mut DutchAuction,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == auction.owner, ENotOwner);
    assert!(!auction.is_active, EAuctionStillActive);

    let amount = balance::value(&auction.proceeds);
    let coin = coin::take(&mut auction.proceeds, amount, ctx);
    transfer::public_transfer(coin, ctx.sender());
}

// ── Owner: Cancel Auction ──────────────────────────────────────

public fun cancel_auction(
    auction: &mut DutchAuction,
    storage_unit: &mut StorageUnit,
    character: &Character,
    ctx: &mut TxContext,
): Item {
    assert!(ctx.sender() == auction.owner, ENotOwner);
    assert!(auction.is_active, EAuctionAlreadyEnded);

    auction.is_active = false;

    // Return item to Owner
    storage_unit::withdraw_item(
        storage_unit, character, AuctionAuth {}, auction.item_type_id, ctx,
    )
}

// Error codes
const EInvalidPricing: u64 = 0;
const EInvalidDropAmount: u64 = 1;
const EIntervalTooShort: u64 = 2;
const EAuctionEnded: u64 = 3;
const EInsufficientPayment: u64 = 4;
const EAuctionStillActive: u64 = 5;
const EAuctionAlreadyEnded: u64 = 6;
const ENotOwner: u64 = 7;
```

---

## Part 2: Unit Tests

```move
#[test_only]
module dutch_auction::auction_tests;

use dutch_auction::auction;
use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;

#[test]
fun test_price_decreases_over_time() {
    let mut scenario = test_scenario::begin(@0xOwner);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Set to time 0
    clock.set_for_testing(0);

    // Create mock auction object to test price calculation
    let auction = auction::create_test_auction(
        5000,   // start_price
        500,    // end_price
        600_000, // 10 minutes (ms)
        500,    // Drop 500 each time
        &clock,
        scenario.ctx(),
    );

    // Time 0: Price should be 5000
    assert!(auction::current_price(&auction, &clock) == 5000, 0);

    // After 10 minutes: Price should be 4500
    clock.set_for_testing(600_000);
    assert!(auction::current_price(&auction, &clock) == 4500, 0);

    // After 90 minutes (9 drops × 500 = 4500, but minimum 500): Price should be 500
    clock.set_for_testing(5_400_000);
    assert!(auction::current_price(&auction, &clock) == 500, 0);

    clock.destroy_for_testing();
    auction.destroy_test_auction();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = auction::EInsufficientPayment)]
fun test_underpayment_fails() {
    // ...Test failure path when payment is insufficient
}
```

---

## Part 3: Bidder dApp

```tsx
// src/AuctionApp.tsx
import { useState, useEffect, useCallback } from 'react'
import { useConnection, getObjectWithJson } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

const DUTCH_PACKAGE = "0x_DUTCH_PACKAGE_"
const AUCTION_ID = "0x_AUCTION_ID_"
const STORAGE_UNIT_ID = "0x..."
const CHARACTER_ID = "0x..."
const CLOCK_OBJECT_ID = "0x6"

interface AuctionState {
  start_price: string
  end_price: string
  start_time_ms: string
  price_drop_interval_ms: string
  price_drop_amount: string
  is_active: boolean
  item_type_id: string
}

function calculateCurrentPrice(state: AuctionState): number {
  if (!state.is_active) return Number(state.end_price)

  const now = Date.now()
  const elapsed = now - Number(state.start_time_ms)
  const drops = Math.floor(elapsed / Number(state.price_drop_interval_ms))
  const totalDrop = drops * Number(state.price_drop_amount)
  const maxDrop = Number(state.start_price) - Number(state.end_price)

  if (totalDrop >= maxDrop) return Number(state.end_price)
  return Number(state.start_price) - totalDrop
}

function msUntilNextDrop(state: AuctionState): number {
  const now = Date.now()
  const elapsed = now - Number(state.start_time_ms)
  const interval = Number(state.price_drop_interval_ms)
  return interval - (elapsed % interval)
}

export function AuctionApp() {
  const { isConnected, handleConnect } = useConnection()
  const dAppKit = useDAppKit()
  const [auctionState, setAuctionState] = useState<AuctionState | null>(null)
  const [currentPrice, setCurrentPrice] = useState(0)
  const [countdown, setCountdown] = useState(0)
  const [status, setStatus] = useState('')
  const [isBuying, setIsBuying] = useState(false)

  // Load auction state
  const loadAuction = useCallback(async () => {
    const obj = await getObjectWithJson(AUCTION_ID)
    if (obj?.content?.dataType === 'moveObject') {
      const fields = obj.content.fields as AuctionState
      setAuctionState(fields)
    }
  }, [])

  useEffect(() => {
    loadAuction()
  }, [loadAuction])

  // Update price countdown every second
  useEffect(() => {
    if (!auctionState) return
    const timer = setInterval(() => {
      setCurrentPrice(calculateCurrentPrice(auctionState))
      setCountdown(msUntilNextDrop(auctionState))
    }, 1000)
    return () => clearInterval(timer)
  }, [auctionState])

  const handleBuyNow = async () => {
    if (!isConnected) { setStatus('Please connect wallet first'); return }
    setIsBuying(true)
    setStatus('⏳ Submitting transaction...')

    try {
      const tx = new Transaction()
      const [paymentCoin] = tx.splitCoins(tx.gas, [
        tx.pure.u64(currentPrice + 1_000) // Slightly more than current price, prevent last-second price changes
      ])

      tx.moveCall({
        target: `${DUTCH_PACKAGE}::auction::buy_now`,
        arguments: [
          tx.object(AUCTION_ID),
          tx.object(STORAGE_UNIT_ID),
          tx.object(CHARACTER_ID),
          paymentCoin,
          tx.object(CLOCK_OBJECT_ID),
        ],
      })

      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`🏆 Bid successful! Tx: ${result.digest.slice(0, 12)}...`)
      await loadAuction()
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    } finally {
      setIsBuying(false)
    }
  }

  const countdownSec = Math.ceil(countdown / 1000)
  const priceInSui = (currentPrice / 1e9).toFixed(2)
  const nextPriceSui = (
    Math.max(Number(auctionState?.end_price ?? 0), currentPrice - Number(auctionState?.price_drop_amount ?? 0)) / 1e9
  ).toFixed(2)

  return (
    <div className="auction-app">
      <header>
        <h1>🔨 Dutch Auction House</h1>
        {!isConnected
          ? <button onClick={handleConnect}>Connect Wallet</button>
          : <span className="connected">✅ Connected</span>
        }
      </header>

      {auctionState ? (
        <div className="auction-board">
          <div className="current-price">
            <span className="label">Current Price</span>
            <span className="price">{priceInSui} SUI</span>
          </div>

          <div className="countdown">
            <span className="label">⏳ Drops to {nextPriceSui} SUI in {countdownSec}s</span>
            <span className="next-price">{nextPriceSui} SUI</span>
          </div>

          <div className="info-row">
            <span>Starting Price: {(Number(auctionState.start_price) / 1e9).toFixed(2)} SUI</span>
            <span>Minimum Price: {(Number(auctionState.end_price) / 1e9).toFixed(2)} SUI</span>
          </div>

          {auctionState.is_active ? (
            <button
              className="buy-btn"
              onClick={handleBuyNow}
              disabled={isBuying || !isConnected}
            >
              {isBuying ? '⏳ Buying...' : `💰 Buy Now ${priceInSui} SUI`}
            </button>
          ) : (
            <div className="sold-banner">🎉 Sold</div>
          )}

          {status && <p className="tx-status">{status}</p>}
        </div>
      ) : (
        <div>Loading auction info...</div>
      )}
    </div>
  )
}
```

---

## 🎯 Complete Review

```
Contract Layer
├── create_auction() → Creates shared DutchAuction object
├── current_price()  → Calculates current price based on time (pure calculation, no state modification)
├── buy_now()        → Payment → Revenue to treasury → Withdraw item from SSU → Emit event
├── cancel_auction() → Owner cancels, returns item
└── withdraw_proceeds() → Owner withdraws auction proceeds

dApp Layer
├── Recalculates price every second (pure frontend, no Gas consumption)
├── Countdown display for next price drop
└── One-click purchase, automatically attaches current price
```

---

## 🔧 Extension Exercises

1. Support batch auctions: Auction multiple item types simultaneously, each with independent countdown
2. Scheduled purchase: Players set target price, automatically trigger purchase when reached (off-chain monitoring + scheduled submission)
3. Transaction history: Monitor `AuctionSettled` events to display recent transaction data

---

## 📚 Related Documentation

- [Chapter 12: Event System](./chapter-12.md#74-event-system-events)
- [Chapter 14: Pricing Strategies](./chapter-14.md#84-dynamic-pricing-strategies)
- [Smart Storage Unit](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/storage-unit/README.md)
