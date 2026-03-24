# Chapter 14: On-chain Economic System Design

> **Goal:** Learn to design and implement complete on-chain economic systems in EVE Frontier, including custom token issuance, decentralized markets, dynamic pricing, and vault management.

---

> Status: Advanced design chapter. Main content focuses on tokens, markets, vaults, and pricing mechanisms.

## 14.1 EVE Frontier's Economic System

EVE Frontier itself already has two official currencies:

| Currency | Purpose | Features |
|------|------|------|
| **LUX** | In-game mainstream trading currency | Stable, used for daily services and commodity trading |
| **EVE Token** | Ecosystem token | Used for developer incentives, can purchase special assets |

As a Builder, you can:
1. **Accept LUX/SUI as payment methods** (directly use official Coin types)
2. **Issue your own alliance token** (custom Coin module)
3. **Build markets and trading mechanisms** (based on SSU extensions)

The most important thing here isn't the capabilities themselves of "being able to issue tokens and charge fees," but first distinguishing:

> What is your economic system actually selling, why would anyone continue to pay, and under what circumstances will it be arbitraged or drained.

Many on-chain economic designs fail not because the code was wrong, but because they never figured out these things from the start:

- Are you selling one-time items, ongoing services, or access qualifications?
- Is revenue settled immediately or distributed long-term?
- Who determines the price? Fixed, algorithmic, auction, or manual operation?
- Why would players keep assets in your system rather than use and leave?

### First distinguish four most common Builder fee models

| Model | What users buy | Typical scenario | Risk point |
|------|------|------|------|
| **One-time purchase** | An item or one action | Vending machine, gate jump fee | Easily becomes pure price comparison market |
| **Usage rights purchase** | Access or capability for a period | Rental, subscription, pass | Expiration, refund, abuse boundary complex |
| **Matchmaking commission** | Platform traffic and transaction matching | Market, auction, insurance matching | Fake transactions, self-dealing, Sybil volume manipulation |
| **Long-term vault distribution** | Share of system cash flow | Alliance vault, protocol revenue distribution | Complex governance, large distribution disputes |

Before designing an economic system, you'd better first clarify which category you belong to. Because they correspond to completely different object models, event designs, and risk controls.

---

## 14.2 Issuing Custom Tokens (Custom Coin)

Sui's token (Coin) model is very standardized. Through the `sui::coin` module, you can create any Fungible Token:

```move
module my_alliance::alliance_token;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::object::UID;
use sui::transfer;
use sui::tx_context::TxContext;

/// Token's "One-Time Witness"
/// Must match module name (all caps), can only be created during init
public struct ALLIANCE_TOKEN has drop {}

/// Token metadata (name, symbol, decimals)
fun init(witness: ALLIANCE_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        6,                            // Decimals
        b"ALLY",                      // Token symbol
        b"Alliance Token",            // Token full name
        b"The official token of Alliance X",  // Description
        option::none(),               // Icon URL (optional)
        ctx,
    );

    // Transfer TreasuryCap to deployer (minting rights)
    transfer::public_transfer(treasury_cap, ctx.sender());
    // Share CoinMetadata (for DEX, wallet display)
    transfer::public_share_object(coin_metadata);
}

/// Mint tokens (only holder of TreasuryCap can call)
public fun mint(
    treasury: &mut TreasuryCap<ALLIANCE_TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::mint(treasury, amount, ctx);
    transfer::public_transfer(coin, recipient);
}

/// Burn tokens (reduce total supply)
public fun burn(
    treasury: &mut TreasuryCap<ALLIANCE_TOKEN>,
    coin: Coin<ALLIANCE_TOKEN>,
) {
    coin::burn(treasury, coin);
}
```

Issuing tokens is technically simple, but economically most easily misused.

### Three questions to ask before issuing tokens

#### 1. Why does this token exist?

Common reasonable uses include:

- Alliance internal accounting and incentives
- Protocol internal discounts, revenue sharing, or voting credentials
- Some service quota or access layer

If the answer is just "everyone has tokens, so I'll issue one too," it's probably not worth doing.

#### 2. Does this token really need on-chain circulation?

Some points-based systems don't actually need an independent coin, better suited for:

- On-chain scoring objects
- Non-transferable badges
- Vault share records

Because once you make it a truly transferable Coin, you've introduced by default:

- Secondary markets
- Hoarding and speculation
- Liquidity expectations
- Higher compliance and operational burden

#### 3. Who controls supply, how does supply grow?

`TreasuryCap` technically represents minting rights, economically represents monetary sovereignty. As long as the supply strategy is vague, it's easy to evolve into:

- Builder arbitrarily inflating
- Early users being diluted
- Price and expectations rapidly collapsing

### What does One-Time Witness solve and not solve?

It solves:

- Coin type creation identity uniqueness
- Initialization path standardization
- Metadata and TreasuryCap creation process security

It doesn't solve:

- Whether your supply curve is reasonable
- Whether the coin has demand
- Whether the coin price is stable

In other words, the language ensures "coins won't be randomly forged," but won't ensure "you issued a good coin."

---

## 14.3 Building Decentralized Markets

Based on Smart Storage Unit, you can build decentralized item markets:

```move
module my_market::item_market;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::object::{Self, ID};
use sui::event;

/// Market extension Witness
public struct MarketAuth has drop {}

/// Item listing information
public struct Listing has store {
    seller: address,
    item_type_id: u64,
    price: u64,           // In MIST (SUI's smallest unit)
    expiry_ms: u64,       // 0 = never expires
}

/// Market registry
public struct Market has key {
    id: UID,
    storage_unit_id: ID,
    listings: Table<u64, Listing>,  // item_type_id -> Listing
    fee_rate_bps: u64,              // Fee (basis points, 100 bps = 1%)
    fee_balance: Balance<SUI>,
}

/// Events
public struct ItemListed has copy, drop {
    market_id: ID,
    seller: address,
    item_type_id: u64,
    price: u64,
}

public struct ItemSold has copy, drop {
    market_id: ID,
    buyer: address,
    seller: address,
    item_type_id: u64,
    price: u64,
    fee: u64,
}

/// List item
public fun list_item(
    market: &mut Market,
    storage_unit: &mut StorageUnit,
    character: &Character,
    item_type_id: u64,
    price: u64,
    expiry_ms: u64,
    ctx: &mut TxContext,
) {
    // Withdraw item from storage box, store in market's dedicated temporary warehouse
    // (Implementation detail: use MarketAuth{} to call SSU's withdraw_item)
    // ...

    // Record listing information
    table::add(&mut market.listings, item_type_id, Listing {
        seller: ctx.sender(),
        item_type_id,
        price,
        expiry_ms,
    });

    event::emit(ItemListed {
        market_id: object::id(market),
        seller: ctx.sender(),
        item_type_id,
        price,
    });
}

/// Buy item
public fun buy_item(
    market: &mut Market,
    storage_unit: &mut StorageUnit,
    character: &Character,
    item_type_id: u64,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Item {
    let listing = table::borrow(&market.listings, item_type_id);

    // Check expiration
    if listing.expiry_ms > 0 {
        assert!(clock.timestamp_ms() < listing.expiry_ms, EListingExpired);
    }

    // Verify payment amount
    assert!(coin::value(&payment) >= listing.price, EInsufficientPayment);

    // Deduct fee
    let fee = listing.price * market.fee_rate_bps / 10_000;
    let seller_amount = listing.price - fee;

    // Split coins: fee + seller revenue + change
    let fee_coin = payment.split(fee, ctx);
    let seller_coin = payment.split(seller_amount, ctx);
    let change = payment;  // Remaining change

    balance::join(&mut market.fee_balance, coin::into_balance(fee_coin));
    transfer::public_transfer(seller_coin, listing.seller);
    transfer::public_transfer(change, ctx.sender());

    let seller_addr = listing.seller;
    let price = listing.price;

    // Remove listing record
    table::remove(&mut market.listings, item_type_id);

    event::emit(ItemSold {
        market_id: object::id(market),
        buyer: ctx.sender(),
        seller: seller_addr,
        item_type_id,
        price,
        fee,
    });

    // Withdraw item from SSU to buyer
    storage_unit::withdraw_item(
        storage_unit, character, MarketAuth {}, item_type_id, ctx,
    )
}
```

This market example already illustrates the basic structure, but for real design you need to think through a few more things.

### What are the minimum four layers a market contains?

1. **Order layer**
   What seller provides, what price, when expires
2. **Custody layer**
   Who holds items and funds, when are they actually transferred
3. **Settlement layer**
   How are fees, seller revenue, change distributed
4. **Index layer**
   How does frontend query current buyable list, not just historical events

Missing any of these four layers, you can "write code" but can't write a stable market.

### Most easily missed boundaries in market design

#### 1. When listing, is the item actually locked?

If only `Listing` is recorded, but the item itself isn't securely held:

- Seller might have already moved the item
- Frontend still shows "available for purchase"
- Buyer pays and finds out delivery is impossible

#### 2. Are payment and delivery in the same atomic transaction?

If payment succeeds but delivery fails, or delivery succeeds but payment fails, both cause serious experience and asset issues. One core value of on-chain markets is putting these two actions into the same atomic transaction.

#### 3. Are delist, expiration, re-listing paths closed?

Many markets don't have problems with listing and purchasing, but rather:

- Expired entries still in list
- Inventory doesn't return after delisting
- Re-listing causes state confusion

---

## 14.4 Dynamic Pricing Strategies

### Strategy One: Fixed Price

Simplest pricing, Owner sets price, players buy at price (like the market example above).

### Strategy Two: Dutch Auction (Decreasing Price)

```move
public fun get_current_price(
    start_price: u64,
    end_price: u64,
    start_time_ms: u64,
    duration_ms: u64,
    clock: &Clock,
): u64 {
    let elapsed = clock.timestamp_ms() - start_time_ms;
    if elapsed >= duration_ms {
        return end_price  // Reached minimum price
    }

    // Linear decrease
    let price_drop = (start_price - end_price) * elapsed / duration_ms;
    start_price - price_drop
}
```

### Strategy Three: Supply-Demand Dynamic Pricing (AMM Style)

Based on **constant product formula** `x * y = k`:

```move
public struct LiquidityPool has key {
    id: UID,
    reserve_sui: Balance<SUI>,
    reserve_item_count: u64,
    k_constant: u64,  // x * y = k
}

/// Calculate how much SUI is needed to buy n items
public fun get_buy_price(pool: &LiquidityPool, buy_count: u64): u64 {
    let new_item_count = pool.reserve_item_count - buy_count;
    let new_sui_reserve = pool.k_constant / new_item_count;
    new_sui_reserve - balance::value(&pool.reserve_sui)
}
```

### Strategy Four: Member Discounts

```move
public fun calculate_price(
    base_price: u64,
    buyer: address,
    member_registry: &Table<address, MemberTier>,
): u64 {
    if table::contains(member_registry, buyer) {
        let tier = table::borrow(member_registry, buyer);
        match (tier) {
            MemberTier::Gold => base_price * 80 / 100,   // 20% off
            MemberTier::Silver => base_price * 90 / 100, // 10% off
            _ => base_price,
        }
    } else {
        base_price
    }
}
```

Choosing pricing strategy is essentially balancing three things:

- **Revenue maximization**
- **User predictability**
- **Anti-manipulation capability**

### Why will fixed pricing never go out of style?

Because it's easiest to understand and easiest to operate.

Suited for:

- Low-frequency goods
- Services with stable price expectations
- Products just launched, haven't grasped real demand curve yet

Many Builders want to implement complex pricing from the start, but actually the more stable path is usually:

1. First use fixed pricing to establish real demand
2. Then decide based on data whether to introduce dynamic mechanisms

### What is Dutch auction suited for?

It's suited for:

- Scarce resource initial sale
- You're uncertain of market psychological price point
- Want price to automatically fall back over time

But you must accept one reality:

- It's better suited for "single sale"
- Not necessarily suited for long-term stable operating stores

### Why is AMM style both dangerous and powerful?

Powerful because:

- Continuously tradable
- Doesn't depend on manual individual listings
- Price can automatically respond to inventory changes

Dangerous because:

- Players will be amplified by slippage and curve effects
- Easy to be arbitraged when parameters aren't stable
- When pool depth is insufficient, price will look very bad

So if you're not building a system that truly needs "continuous liquidity curves," you don't necessarily need AMM.

---

## 14.5 Vault Management Patterns

Every commercial facility should have a vault to manage revenue:

```move
module my_finance::vault;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;

/// Multi-asset vault
public struct MultiVault has key {
    id: UID,
    sui_balance: Balance<SUI>,
    total_deposited: u64,   // Historical total deposited
    total_withdrawn: u64,   // Historical total withdrawn
}

/// Deposit funds
public fun deposit(vault: &mut MultiVault, coin: Coin<SUI>) {
    let amount = coin::value(&coin);
    vault.total_deposited = vault.total_deposited + amount;
    balance::join(&mut vault.sui_balance, coin::into_balance(coin));
}

/// Distribute proportionally to multiple addresses
public fun distribute(
    vault: &mut MultiVault,
    recipients: vector<address>,
    shares: vector<u64>,  // Shares (percentage, total must equal 100)
    ctx: &mut TxContext,
) {
    assert!(vector::length(&recipients) == vector::length(&shares), EMismatch);

    let total = balance::value(&vault.sui_balance);
    let len = vector::length(&recipients);
    let mut i = 0;

    while (i < len) {
        let share = *vector::borrow(&shares, i);
        let payout = total * share / 100;
        let coin = coin::take(&mut vault.sui_balance, payout, ctx);
        transfer::public_transfer(coin, *vector::borrow(&recipients, i));
        vault.total_withdrawn = vault.total_withdrawn + payout;
        i = i + 1;
    };
}
```

The focus of vault design has never been "putting money in," but rather:

> How revenue settles, who can move it, when to distribute, can you still audit after distribution.

### A stable vault must answer at least these questions

1. What asset is revenue denominated in?
2. Are funds distributed in real-time or first settled then allocated?
3. Who can withdraw? Who can pause? Who can change revenue share ratios?
4. How to handle remainders and rounding errors during distribution?
5. In case of disputes, can on-chain records be traced?

### Trade-offs between "immediate distribution" and "vault first then settlement"

#### Immediate distribution

Pros:

- Logic intuitive
- Revenue immediately to all parties

Cons:

- Each transaction heavier
- More revenue paths, larger failure surface

#### Vault first then settlement

Pros:

- Main transaction lighter
- Revenue sharing, withdrawal, auditing easier to separate

Cons:

- Need to additionally handle withdrawal permissions and settlement timing

In most real products, the latter will be more stable.

---

## 14.6 Economic System Design Principles

| Principle | Practical advice |
|------|--------|
| **Sustainability** | Design buyback mechanisms (such as using revenue to buyback and burn tokens) to avoid inflation |
| **Transparency** | All economic parameters queryable on-chain, record every transaction through events |
| **Anti-manipulation** | Avoid single-point price control, introduce AMM or Dutch auction |
| **Incentive alignment** | Make service providers (Builders) and users' interests aligned |
| **Upgrade retention** | Key parameters (fee rates, prices) designed to be updatable, avoid contract lock-in |

### Three more most underestimated principles

| Principle | Why important |
|------|------|
| **Anti-volume manipulation** | As long as your system has fee rebates, activity incentives, or leaderboards, someone will manipulate volume |
| **Exit path** | Whether players can unsubscribe, retrieve deposits, delist assets determines system trustworthiness |
| **Parameter interpretability** | When players can't understand where prices and fees come from, they naturally distrust your protocol |

### Attack surfaces you must proactively ask about during design

- Can players trade with themselves to farm rewards?
- Can whales instantly drain liquidity or manipulate prices?
- Can discounts and rebates be arbitraged in loops?
- During vault revenue distribution, can it be front-run or claimed multiple times?

If you write these questions out during the design phase, many vulnerabilities won't make it into code.

---

## Chapter Summary

| Knowledge Point | Core Points |
|--------|--------|
| Custom token | `ALLIANCE_TOKEN` one-time witness + `coin::create_currency()` |
| Decentralized market | SSU extension + Listing Table + fee mechanism |
| Pricing strategies | Fixed price / Dutch auction / AMM constant product / member discounts |
| Vault management | `Balance<T>` as internal ledger, proportional distribution |
| Economic design principles | Sustainable + transparent + anti-manipulation + upgradeable |

## Further Reading

- [Sui Coin Standard](https://docs.sui.io/guides/developer/sui-101/create-coin)
- [Move Book: Coin Module](https://move-book.com/programmability/coin.html)
- [EVE Frontier Economic Design](https://github.com/evefrontier/builder-documentation/blob/main/README.md)
- [Chapter 12: Table & Dynamic Fields](./chapter-12.md)
