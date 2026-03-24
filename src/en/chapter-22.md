# Chapter 22: Advanced Move Patterns — Upgrade Compatibility Design

> **Objective:** Master production-grade Move contract upgrade compatibility architecture, including versioned APIs, data migration, Policy control, and smooth upgrades without service interruption.

---

> Status: Advanced design chapter. Main content focuses on upgrade compatibility, migration, and timelock control.

##  22.1 The Essence of Upgrade Compatibility Issues

Move contract upgrades face two core constraints:

```
Constraint 1: Struct definitions cannot be modified (cannot add/remove fields, cannot change field types)
Constraint 2: Function signatures cannot be modified (parameters and return values cannot change)

BUT:
✅ Can add new functions
✅ Can add new modules
✅ Can modify function internal logic (without changing signature)
✅ Can add new structs
```

**Challenge**: If your contract v1 has a `Market` struct and v2 wants to add an `expiry_ms` field, you cannot modify it directly.

What this upgrade compatibility chapter really needs to solve is not "how to release a new version," but:

> How to keep a system that's already depended upon by objects, frontends, scripts, and users alive.

So the upgrade problem is essentially a four-layer compatibility problem:

- On-chain object compatibility
- On-chain interface compatibility
- Frontend parsing compatibility
- Operations process compatibility

---

##  22.2 Extension Pattern: Use Dynamic Fields to Add "Future Fields"

**Best Practice**: Reserve extension space for future fields in advance:

```move
module my_market::market_v1;

/// Current fields
public struct Market has key {
    id: UID,
    toll: u64,
    owner: address,
    // Note: Don't try to predict future needed fields — because you can't change them
    // Instead, rely on dynamic fields for extension
}

// V1 → V2: Add expiry_ms via dynamic field
// (Called in migration script after package upgrade)
public fun add_expiry_field(
    market: &mut Market,
    expiry_ms: u64,
) {
    // Only add if this field doesn't exist yet
    if !df::exists_(&market.id, b"expiry_ms") {
        df::add(&mut market.id, b"expiry_ms", expiry_ms);
    }
}

/// V2 version reads expiry (backward compatible: returns default when old objects lack this field)
public fun get_expiry(market: &Market): u64 {
    if df::exists_(&market.id, b"expiry_ms") {
        *df::borrow<vector<u8>, u64>(&market.id, b"expiry_ms")
    } else {
        0  // Default: never expires
    }
}
```

### Why do dynamic fields become an upgrade escape hatch?

Because they let you supplement old objects with new semantics without changing the original struct layout.

But they also have boundaries:

- Suitable for appending fields
- Not suitable for cramming all future complex structures in

If a version upgrade requires patching many temporary fields onto objects, that usually means you should rethink the model, not rely infinitely on patch-style extensions.

---

##  22.3 Versioned API Design

When you need to change function behavior, keep the old version and add a new version:

```move
module my_market::market;

/// V1 API (always maintain backward compatibility)
public fun buy_item_v1(
    market: &mut Market,
    payment: Coin<SUI>,
    item_type_id: u64,
    ctx: &mut TxContext,
): Item {
    // Original logic
}

/// V2 API (new feature: supports discount codes)
public fun buy_item_v2(
    market: &mut Market,
    payment: Coin<SUI>,
    item_type_id: u64,
    discount_code: Option<vector<u8>>,  // New parameter
    clock: &Clock,                       // New parameter (time validation)
    ctx: &mut TxContext,
): Item {
    // New logic (includes discount processing)
    let effective_price = apply_discount(market, item_type_id, discount_code, clock);
    // ...
}
```

**dApp Adaptation**: Check contract version on TypeScript side, choose which function to call:

```typescript
async function buyItem(useV2: boolean, ...) {
  const tx = new Transaction();

  if (useV2) {
    tx.moveCall({ target: `${PKG}::market::buy_item_v2`, ... });
  } else {
    tx.moveCall({ target: `${PKG}::market::buy_item_v1`, ... });
  }
}
```

### Why "keeping old entry points" is often more stable than "forcing complete migration"?

Because callers of production systems are never just yourself:

- Old frontend still running
- User scripts may still be using
- Third-party aggregators may not have upgraded yet

So the most stable upgrade path is often not "one-cut replacement," but:

1. Old and new coexist
2. Give migration window
3. Gradually retire old interfaces

---

##  22.4 Upgrade Locking Strategy

For high-value contracts, you can add timelocks on UpgradeCap:

```move
module my_gov::upgrade_timelock;

use sui::package::UpgradeCap;
use sui::clock::Clock;

public struct TimelockWrapper has key {
    id: UID,
    upgrade_cap: UpgradeCap,
    delay_ms: u64,           // Wait time required before upgrade announcement
    announced_at_ms: u64,    // Announcement time (0 = not announced)
}

/// Step 1: Announce upgrade intent (start timer)
public fun announce_upgrade(
    wrapper: &mut TimelockWrapper,
    _admin: &AdminCap,
    clock: &Clock,
) {
    assert!(wrapper.announced_at_ms == 0, EAlreadyAnnounced);
    wrapper.announced_at_ms = clock.timestamp_ms();
}

/// Step 2: Can only execute upgrade after delay period
public fun authorize_upgrade(
    wrapper: &mut TimelockWrapper,
    clock: &Clock,
): &mut UpgradeCap {
    assert!(wrapper.announced_at_ms > 0, ENotAnnounced);
    assert!(
        clock.timestamp_ms() >= wrapper.announced_at_ms + wrapper.delay_ms,
        ETimelockNotExpired,
    );
    // Reset, next upgrade requires re-announcement
    wrapper.announced_at_ms = 0;
    &mut wrapper.upgrade_cap
}
```

### TimeLock truly protects not code, but trust relationships

It gives community, collaborators, and users an observation window, so upgrades don't become "admin can change whatever they want tonight."

This is very critical in high-value protocols, because upgrade risks are often not technical bugs, but governance risks.

---

##  22.5 Large-Scale Data Migration Strategy

When needing to rebuild storage structure, adopt "incremental migration" rather than "one-time migration":

```move
// Scenario: Migrate ListingsV1 (vector) to ListingsV2 (Table)
module migration::market_migration;

public struct MigrationState has key {
    id: UID,
    migrated_count: u64,
    total_count: u64,
    is_complete: bool,
}

/// Migrate one batch at a time (avoid exceeding computation limit in one transaction)
public fun migrate_batch(
    old_market: &mut MarketV1,
    new_market: &mut MarketV2,
    state: &mut MigrationState,
    batch_size: u64,         // Process batch_size records each time
    ctx: &TxContext,
) {
    let start = state.migrated_count;
    let end = min(start + batch_size, state.total_count);
    let mut i = start;

    while (i < end) {
        let listing = get_listing_v1(old_market, i);
        insert_listing_v2(new_market, listing);
        i = i + 1;
    };

    state.migrated_count = end;
    if end == state.total_count {
        state.is_complete = true;
    };
}
```

**Migration Script: Auto-loop execution until complete**

```typescript
async function runMigration(stateId: string) {
  let isComplete = false;
  let batchNum = 0;

  while (!isComplete) {
    const tx = new Transaction();
    tx.moveCall({
      target: `${MIGRATION_PKG}::market_migration::migrate_batch`,
      arguments: [/* ... */, tx.pure.u64(100)], // 100 per batch
    });

    const result = await client.signAndExecuteTransaction({ signer: adminKeypair, transaction: tx });
    console.log(`Batch ${++batchNum} done:`, result.digest);

    // Check migration state
    const state = await client.getObject({ id: stateId, options: { showContent: true } });
    isComplete = (state.data?.content as any)?.fields?.is_complete;

    await new Promise(r => setTimeout(r, 1000)); // 1 second interval
  }

  console.log("Migration complete!");
}
```

### Why is incremental migration better than all-at-once?

Because in real production systems, you typically need to balance simultaneously:

- Computation limits
- Risk control
- Failure recovery
- Service can continue running during migration

The biggest problem with one-time migration is not that it can't be written, but:

- Hard to recover from mid-failure
- State easily becomes half-old half-new after failure
- Transaction too large simply can't be sent

---

##  22.6 Complete Upgrade Workflow

```
① Develop new version contract (local + testnet validation)
② Announce upgrade intent (TimeLock starts timer, notify community)
③ Community review period (72 hours)
④ After TimeLock expires, execute sui client upgrade --upgrade-capability <CAP_ID>
⑤ Run data migration scripts (if necessary)
⑥ Update dApp configuration (new Package ID, new interface version)
⑦ Announce upgrade complete
```

### A mature team views upgrades as "controlled release events"

That is, besides on-chain actions themselves, you should also synchronously prepare:

- Upgrade announcement
- Frontend switch plan
- Rollback or downtime contingency
- Post-upgrade observation metrics

Otherwise "on-chain upgrade complete" doesn't equal "system has stably completed upgrade."

---

## 🔖 Chapter Summary

| Knowledge Point | Core Takeaway |
|--------|--------|
| Upgrade constraints | Struct/function signatures unchangeable, but can add new functions/modules |
| Dynamic field extension | `df::add()` adds "future fields" at runtime |
| Versioned API | `buy_v1()` / `buy_v2()` coexist, dApp chooses by version |
| TimeLock upgrade | Announcement + waiting period → community review → can execute |
| Incremental migration | `migrate_batch()` processes in batches, avoid exceeding computation limit |

## 📚 Further Reading

- [Sui Package Upgrades](https://docs.sui.io/guides/developer/packages/upgrade)
- [Chapter 17: Security Auditing](./chapter-17.md)
- [EVE Builder Constraints](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
