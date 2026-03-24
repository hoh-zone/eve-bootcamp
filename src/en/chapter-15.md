# Chapter 15: Cross-contract Composability

> **Goal:** Master how to design externally friendly contract interfaces, and how to safely call contracts published by other Builders, building a composable EVE Frontier ecosystem.

---

> Status: Advanced design chapter. Main content focuses on cross-contract interfaces and composability.

## 15.1 The Value of Composability

One of EVE Frontier's most exciting features: **Your contract can directly call others' contracts, without any intermediary**.

```
Builder A: Issued ALLY Token + price oracle
Builder B: Calls A's price oracle, prices items in ALLY Token for sale
Builder C: Lists on B's market, accepts both A's ALLY and SUI payment
```

This creates a truly **open economic protocol stack**.

The real power of composability isn't the slogan "everyone can call each other," but rather:

> Once your protocol is clear enough, others can treat it as building blocks, not as a black box.

This directly changes Builder thinking:

- You're no longer just building a single-point function
- You're deciding whether to become a "terminal product" or "underlying capability"

Many of the most valuable protocols don't do everything themselves, but make a certain capability into a module others are willing to repeatedly integrate.

---

## 15.2 Designing Externally Friendly Move Interfaces

Good Move interface design should follow:

```move
module my_protocol::oracle;

// ── Public view functions (read-only, free to call) ──────────────────────

/// Get ALLY/SUI exchange rate (in MIST)
public fun get_ally_price(oracle: &PriceOracle): u64 {
    oracle.ally_per_sui
}

/// Check if price is within validity period
public fun is_price_fresh(oracle: &PriceOracle, clock: &Clock): bool {
    clock.timestamp_ms() - oracle.last_updated_ms < PRICE_TTL_MS
}

// ── Public composable functions (callable by other contracts) ───────────────────

/// Convert SUI amount to ALLY quantity
public fun sui_to_ally_amount(
    oracle: &PriceOracle,
    sui_amount: u64,
    clock: &Clock,
): u64 {
    assert!(is_price_fresh(oracle, clock), EPriceStale);
    sui_amount * oracle.ally_per_sui / 1_000_000_000
}
```

### Design Principles

| Principle | Implementation |
|------|--------|
| **Read-only views** | `public fun` without `&mut`, zero Gas calls |
| **Composable operations** | Accept Witness parameters, allow authorized callers to execute |
| **Versioning** | Preserve old interfaces, distinguish new interfaces with new function names/type parameters |
| **Event emission** | Emit events for key operations, convenient for monitoring |
| **Documentation** | Complete comments explaining preconditions and return values |

### Standards for good interfaces aren't just "others can call through"

A truly externally friendly interface should at least allow external integrators to quickly answer these questions:

1. Will this function modify state?
2. What objects and permissions must be prepared before calling?
3. What are the most common reasons for call failure?
4. What do return values and events each represent?

If these aren't clear, others can "theoretically call" but integration costs will be absurdly high.

### Three most common mistakes in interface design

#### 1. Directly exposing internal implementation details as external dependencies

Once your interface heavily depends on internal object layout, every refactoring will drag external integrators down with you.

#### 2. Read interfaces and write interfaces mixed too closely

Read-only queries should be as simple and stable as possible. Writable entry points should clearly mark permissions and side effects. When the two are mixed together, integrators easily misuse.

#### 3. Error boundaries unclear

If a function might fail due to:

- Insufficient permissions
- Stale data
- Invalid price
- Object state mismatch

Then these preconditions should ideally be exposed through documentation, naming, or auxiliary read-only interfaces.

---

## 15.3 Calling Other Builders' Contracts

### Adding External Dependencies in Move.toml

```toml
[dependencies]
# Depend on packages already published by other Builders (via Git)
AllyOracle = {
  git = "https://github.com/builder-alice/ally-oracle",
  subdir = "contracts",
  rev = "v1.0.0"
}

# Or directly specify on-chain address (for published packages)
AllyOracleOnChain = { local = "../ally-oracle" }  # For local testing
```

### Calling in Move Code

```move
module my_market::ally_market;

// Import other Builder's modules (need to declare dependency in Move.toml)
use ally_oracle::oracle::{Self, PriceOracle};
use ally_dao::ally_token::ALLY_TOKEN;

public fun buy_with_ally(
    storage_unit: &mut world::storage_unit::StorageUnit,
    character: &Character,
    price_oracle: &PriceOracle,     // External Builder A's price oracle
    ally_payment: Coin<ALLY_TOKEN>, // External Builder A's token
    item_type_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Item {
    // Call external contract's view function
    let price_in_sui = oracle::sui_to_ally_amount(
        price_oracle,
        ITEM_BASE_PRICE_SUI,
        clock,
    );

    assert!(coin::value(&ally_payment) >= price_in_sui, EInsufficientPayment);

    // Process ALLY Token payment (transfer to alliance vault, etc.)
    // ...

    // Withdraw item from own SSU
    storage_unit::withdraw_item(
        storage_unit, character, MyMarketAuth {}, item_type_id, ctx,
    )
}
```

### When depending on others' contracts, what are you really binding to?

Not as simple as "a Git repository address," but simultaneously binding to:

- Their interface stability
- Their upgrade strategy
- Their economic and governance choices
- Your own failure radius

In other words, every external protocol you introduce equals outsourcing part of your stability to others.

### So ask four questions before integrating external protocols

1. Are this protocol's core interfaces stable?
2. Will it break my current usage when upgrading?
3. If it pauses or fails, do I have a fallback path?
4. Can I converge key dependencies to read-only interfaces, rather than deep write coupling?

---

## 15.4 Interface Versioning & Protocol Standards

When your contract is widely used, upgrading interfaces must ensure backward compatibility:

```move
module my_protocol::market_v2;

// Use types to mark versions
public struct V1 has drop {}
public struct V2 has drop {}

// V1 interface (always preserved)
public fun get_price_v1(market: &Market, _: V1): u64 {
    market.price
}

// V2 interface (new, supports dynamic pricing)
public fun get_price_v2(
    market: &Market,
    clock: &Clock,
    _: V2,
): u64 {
    calculate_dynamic_price(market, clock)
}
```

### Defining Cross-contract Interface Standards (Similar to ERC Standards)

In the EVE Frontier ecosystem, interface standards can be agreed upon through documentation, allowing multiple Builders' contracts to be compatible:

```move
// ── Unofficial "Market Interface" Standard Proposal ────────────────────────────
// Any Builder's contract wanting to integrate into aggregated markets should implement the following interfaces:

/// List items: return currently selling item types and prices
public fun list_items(market: &T): vector<(u64, u64)>  // (type_id, price_sui)

/// Query whether specific item is available for purchase
public fun is_available(market: &T, item_type_id: u64): bool

/// Purchase (return item)
public fun purchase<Auth: drop>(
    market: &mut T,
    buyer: &Character,
    item_type_id: u64,
    payment: &mut Coin<SUI>,
    auth: Auth,
    ctx: &mut TxContext,
): Item
```

### Why must version control be considered from the first version?

Because once others start depending on you, "changing interfaces" is no longer just your internal matter.

You must simultaneously consider:

- Whether old callers can still survive
- Whether new features can be gradually introduced
- Whether frontends, scripts, aggregators need to migrate synchronously

Many protocols don't die from insufficient features, but from "version two breaking everything in version one."

### Where standardized interfaces are most valuable

Not looking professional, but catalyzing secondary ecosystems:

- Aggregators easier to integrate
- Price comparison tools easier to build
- Third-party frontends easier to reuse
- Other Builders more willing to build on top of you

---

## 15.5 Practice: Aggregated Price Comparator

```typescript
// Aggregate multiple Builders' market prices in dApp
async function getAggregatedPrices(
  itemTypeId: number,
  marketIds: string[],
  client: SuiClient,
): Promise<Array<{ marketId: string; price: number; builder: string }>> {

  // Batch read all market states
  const markets = await client.multiGetObjects({
    ids: marketIds,
    options: { showContent: true },
  });

  const prices = markets
    .map((market, i) => {
      const fields = (market.data?.content as any)?.fields;
      if (!fields) return null;

      // Read price from listings Table (simplified)
      const listing = fields.listings?.fields?.contents?.find(
        (entry: any) => Number(entry.fields?.key) === itemTypeId
      );

      if (!listing) return null;

      return {
        marketId: marketIds[i],
        price: Number(listing.fields.value.fields.price),
        builder: fields.owner ?? "Unknown",
      };
    })
    .filter(Boolean)
    .sort((a, b) => a!.price - b!.price); // Sort by price ascending

  return prices as any[];
}
```

This example is well-suited to illustrate one reality:

> The value of composability is often amplified off-chain.

In other words, as long as on-chain protocols design interfaces and events clearly, off-chain can create:

- Price comparators
- Aggregators
- Recommendation routing
- Strategy orchestration

So when designing contracts, don't just think about "whether another on-chain contract will call me," also think "whether off-chain tools will be willing to consume me."

---

## 15.6 Composability Risks & Defense

| Risk | Description | Defense |
|------|------|------|
| **Dependent contract upgrade** | External contract upgrade may break your calls | Lock to specific version (rev = "v1.0.0") |
| **External contract pause** | Dependent contract revoked or modified | Design fallback paths (fallback logic) |
| **Reentrancy attacks** | External contract callbacks to your contract | Move naturally defends through ownership system |
| **Price manipulation** | Dependent oracle manipulated | Use multiple oracles, take median |

### Three more very common risks in real projects

| Risk | Description | Defense |
|------|------|------|
| **Interface semantic drift** | Function name unchanged, but behavior calibration changed | Constrain together with version numbers, documentation, and event semantics |
| **External protocol alive, but data quality declines** | Oracle not broken, just updates slower or price abnormal | Add freshness / sanity checks |
| **Missing fallback path** | When external dependency unavailable, own main process directly paralyzed | Preset fallback, pause switches, manual takeover paths |

### Composition isn't better the deeper it goes

The deeper the composition layers, the more capabilities you gain, but also the harder to maintain.

A practical principle is:

- Prioritize depending on stable, read-only, verifiable external capabilities
- Cautiously depend on deeply coupled, strong state-writing external processes

Because when the former breaks, it's usually just "data gets worse," when the latter breaks it might directly interrupt your core business chain.

---

## Chapter Summary

| Knowledge Point | Core Points |
|--------|--------|
| Composability value | Your contract can be called by others, forming protocol stack |
| Interface design | Read-only views + Witness authorization + documentation comments |
| Reference external packages | Move.toml dependencies + `use` statements |
| Version control | Preserve old interfaces + type-marked versions |
| Aggregated dApp | Batch read multi-contract data, frontend aggregated display |

## Further Reading

- [EVE World Explainer](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/eve-frontier-world-explainer.md)
- [Move Book: Package System](https://move-book.com/programmability/packages.html)
