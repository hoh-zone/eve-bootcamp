# Chapter 17: Testing, Debugging, and Security Auditing

> **Goal:** Write comprehensive unit tests for Move contracts, identify common security vulnerabilities, and formulate contract upgrade strategies.

---

> Status: Engineering assurance chapter. Main focus on testing, security, and upgrade risk control.

## 17.1 Why Security Testing is Critical?

Once on-chain contracts are deployed, assets are real. Here are common loss scenarios:
- Price calculation overflow, leading to items sold at 0 price
- Missing permission checks, anyone can call "Owner only" functions
- Reentrancy vulnerabilities (less common in Move but still needs attention)
- Upgrade failures cause old data to be unreadable by new contracts

**Defense Strategy:** Test first, then publish.

The most valuable concept to establish here isn't the platitude "testing is important," but:

> The goal of on-chain contract testing isn't to prove it can run, but to prove it won't lose control under wrong inputs, wrong sequences, and wrong permissions.

Many beginners write tests only verifying "normal path succeeds." But real asset losses usually come from three other types of paths:

- Calls that shouldn't succeed but do
- Boundary value inputs that push the system into abnormal states
- After upgrades or maintenance, old objects and new logic are no longer compatible

So for Builders, testing isn't finishing work, it's part of design work.

---

## 17.2 Move Unit Testing Basics

Move has a built-in testing framework, test code is written in the same `.move` file, marked with `#[test]` annotation:

```move
module my_package::my_module;

// ... normal contract code ...

// Test module: only compiled in test environment
#[test_only]
module my_package::my_module_tests;

use my_package::my_module;
use sui::test_scenario::{Self, Scenario};
use sui::coin;
use sui::sui::SUI;
use sui::clock;

// ── Basic Test ─────────────────────────────────────────────

#[test]
fun test_deposit_and_withdraw() {
    // Initialize test scenario (simulates blockchain state)
    let mut scenario = test_scenario::begin(@0xALICE);

    // Test step 1: Alice deploys contract
    {
        let ctx = scenario.ctx();
        my_module::init_for_testing(ctx);  // Test-specific init
    };

    // Test step 2: Alice deposits item
    scenario.next_tx(@0xALICE);
    {
        let mut vault = scenario.take_shared<my_module::Vault>();
        let ctx = scenario.ctx();

        my_module::deposit(&mut vault, 100, ctx);
        assert!(my_module::balance(&vault) == 100, 0);

        test_scenario::return_shared(vault);
    };

    // Test step 3: Bob tries to withdraw (should fail)
    scenario.next_tx(@0xBOB);
    {
        let mut vault = scenario.take_shared<my_module::Vault>();
        // Expect this call to fail (abort)
        // Use #[test, expected_failure] to test failure paths
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// ── Test Failure Paths ────────────────────────────────────────

#[test]
#[expected_failure(abort_code = my_module::ENotOwner)]
fun test_unauthorized_withdraw_fails() {
    let mut scenario = test_scenario::begin(@0xALICE);

    // Deploy
    { my_module::init_for_testing(scenario.ctx()); };

    // Bob tries to operate as Alice (should abort)
    scenario.next_tx(@0xBOB);
    {
        let mut vault = scenario.take_shared<my_module::Vault>();
        my_module::owner_withdraw(&mut vault, scenario.ctx()); // should abort
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// ── Test Time-Related Logic with Clock ─────────────────────────

#[test]
fun test_time_based_pricing() {
    let mut scenario = test_scenario::begin(@0xALICE);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Set current time
    clock.set_for_testing(1_000_000);

    {
        let price = my_module::get_dutch_price(
            1000,  // starting price
            100,   // minimum price
            0,     // start time
            2_000_000,  // duration (2 seconds)
            &clock,
        );
        // After half the time, price should be middle value
        assert!(price == 550, 0);
    };

    clock.destroy_for_testing();
    scenario.end();
}
```

Running tests:
```bash
# Run all tests
sui move test

# Run only specific test
sui move test test_deposit_and_withdraw

# Show verbose output
sui move test --verbose
```

### When Writing Tests, First Categorize into Four Scenarios

A practical test stratification is:

1. **Normal Path**
   Under valid inputs, does the system complete as expected
2. **Permission Failure Path**
   Without permissions, does it stably abort
3. **Boundary Value Path**
   Are 0, max value, expiry, empty collection, last entry scenarios correct
4. **State Evolution Path**
   After completing one step, then the next, is the system still consistent

If your tests only have the first type, it's not really enough to be called "tested."

### What is `test_scenario` Really Suited For?

It's best suited to simulate:

- Multiple addresses taking turns initiating transactions
- Shared object state changes across multiple transactions
- Behavior changes after time progression
- Complete lifecycle of object creation, retrieval, return

This happens to be exactly where EVE Builder projects' most common risk concentrations are.

### Tests Aren't Better When More Fragmented

Some tests are too fragmented, ultimately only proving "small functions work literally," but don't cover real business loops.

A more valuable approach is usually:

- Keep a few key unit tests
- Then write several end-to-end business scenario tests

For example, in a rental system, rather than only testing `calc_refund()`, more important is testing:

1. Create listing
2. Successfully rent
3. Return early
4. Expire and reclaim

Whether this complete chain is closed.

---

## 17.3 Common Security Vulnerabilities and Defenses

### Vulnerability One: Integer Overflow/Underflow

```move
// ❌ Dangerous: u64 subtraction underflow will abort, but if logic is wrong might calculate huge value
fun unsafe_calc(a: u64, b: u64): u64 {
    a - b  // If b > a, directly aborts (Move checks)
}

// ✅ Safe: Check before operating
fun safe_calc(a: u64, b: u64): u64 {
    assert!(a >= b, EInsufficientBalance);
    a - b
}

// ✅ For intentionally allowed underflow, use checked calculation
fun safe_pct(total: u64, bps: u64): u64 {
    // bps max 10000, prevent total * bps overflow
    assert!(bps <= 10_000, EInvalidBPS);
    total * bps / 10_000  // Move u64 max 1.8e19, need to watch large numbers
}
```

> ✅ **Move's Advantage**: Move checks u64 operation overflow by default, aborts on overflow rather than silently returning wrong values (unlike early Solidity versions).

But note, Move solves "machine-level overflow safety" for you, not "business math correctness."

For example, these problems the type system won't think about for you:

- Should fees be calculated then deducted, or deducted then profit-shared
- Should percentages round down or round to nearest
- After multi-address profit sharing, should remainder stay in vault or return to user

Many economic bugs ultimately aren't "hacker-level vulnerabilities," but settlement caliber itself designed wrong.

### Vulnerability Two: Missing Permission Checks

```move
// ❌ Dangerous: Doesn't verify caller
public fun withdraw_all(treasury: &mut Treasury, ctx: &mut TxContext) {
    let all = coin::take(&mut treasury.balance, balance::value(&treasury.balance), ctx);
    transfer::public_transfer(all, ctx.sender()); // Anyone can withdraw funds!
}

// ✅ Safe: Require OwnerCap
public fun withdraw_all(
    treasury: &mut Treasury,
    _cap: &TreasuryOwnerCap,  // Check caller holds OwnerCap
    ctx: &mut TxContext,
) {
    let all = coin::take(&mut treasury.balance, balance::value(&treasury.balance), ctx);
    transfer::public_transfer(all, ctx.sender());
}
```

The easiest mistake in permission checks is only verifying "some permission exists," but not verifying:

- Is this permission for this object
- Is this call allowed in the current scenario
- Should this permission only be used in certain time periods or certain paths

### Vulnerability Three: Capability Not Properly Bound

```move
// ❌ Dangerous: OwnerCap doesn't verify corresponding object ID
public fun admin_action(vault: &mut Vault, _cap: &OwnerCap) {
    // Any OwnerCap can control any Vault!
}

// ✅ Safe: Verify OwnerCap and object binding relationship
public fun admin_action(vault: &mut Vault, cap: &OwnerCap) {
    assert!(cap.authorized_object_id == object::id(vault), ECapMismatch);
    // ...
}
```

### Vulnerability Four: Timestamp Manipulation

```move
// ❌ Not recommended: Directly rely on ctx.epoch() as precise time
// epoch granularity is about 24 hours, not suitable for fine granularity timing

// ✅ Recommended: Use Clock object
public fun check_expiry(expiry_ms: u64, clock: &Clock): bool {
    clock.timestamp_ms() < expiry_ms
}
```

### Vulnerability Five: Shared Object Race Conditions

Shared objects can be accessed by multiple transactions concurrently. When multiple transactions simultaneously rush to buy the same item:

```move
// ❌ Has race condition problem: Two transactions might both pass check
public fun buy_item(market: &mut Market, ...) {
    let listing = table::borrow(&market.listings, item_type_id);
    assert!(listing.amount > 0, EOutOfStock);
    // ← Another TX might pass the same check here
    // ... then both execute purchase, causing overselling
}

// ✅ Sui's solution: Write locks on shared objects ensure serialization
// Sui's Move executor guarantees: transactions writing to the same shared object execute sequentially
// So the above code is actually safe on Sui! But ensure your logic correctly handles negative stock
public fun buy_item(market: &mut Market, ...) {
    // This check is atomic, other TXs will wait
    assert!(table::contains(&market.listings, item_type_id), ENotListed);
    let listing = table::remove(&mut market.listings, item_type_id);  // Atomic removal
    // ...
}
```

Although Sui serializes writes to shared objects, this doesn't mean you can ignore business race conditions.

You still need to test:

- Same item purchased in rapid succession
- Object delisted then purchased
- Price updates and purchases happening in adjacent transactions

In other words, the underlying executor solves part of concurrent safety for you, but doesn't design complete business consistency.

---

## 17.4 Using Move Prover for Formal Verification

Move Prover is a formal verification tool that can mathematically prove certain properties always hold:

```move
// spec block: formal specification
spec fun total_supply_conserved(treasury: TreasuryCap<TOKEN>): bool {
    // Declare: total supply increases by exact amount after minting
    ensures result == old(total_supply(treasury)) + amount;
}

#[verify_only]
spec module {
    // Invariant: vault balance never exceeds a certain limit
    invariant forall vault: Vault:
        balance::value(vault.balance) <= MAX_VAULT_SIZE;
}
```

Running verification:
```bash
sui move prove
```

### When Is Move Prover Worth It?

Not all projects need to do formal verification from the start. A more practical strategy is usually:

- Normal cases and small-medium projects: First get unit tests and failure path coverage done well
- High-value vaults, liquidation, permission systems: Then introduce Prover to prove key invariants

Most suitable places for Prover usually include:

- Total supply conservation
- Balance never goes negative
- Certain permissions cannot be exceeded
- A certain state machine won't jump to illegal states

---

## 17.5 Contract Upgrade Strategies

Move packages once published are **immutable**, but can publish new versions through upgrade mechanism:

```bash
# First publish
sui client publish
# Get UpgradeCap object (upgrade capability)

# Upgrade (requires UpgradeCap)
sui client upgrade \
  --upgrade-capability <UPGRADE_CAP_ID> \

```

### Upgrade Compatibility Rules

| Change Type | Allowed |
|---------|---------|
| Add new function | ✅ Allowed |
| Add new module | ✅ Allowed |
| Modify function logic (same signature) | ✅ Allowed |
| Modify function signature | ❌ Not allowed |
| Delete function | ❌ Not allowed |
| Modify struct fields | ❌ Not allowed |
| Add struct fields | ❌ Not allowed |

### What's Really Hard About Upgrades Isn't the Command, But Data Staying Alive

Many people doing upgrades for the first time focus on "how to publish new package." But what users really care about is:

- Can old objects still be used
- Can old frontend still read
- How to interpret old events and new objects together

In other words, upgrades are essentially maintaining a still-running system, not restarting the server.

### Four Questions You Must Ask Before Upgrading

1. Can old objects still be safely read by the new version?
2. Does the new version require additional migration scripts?
3. Does the frontend need to synchronously update field parsing?
4. Once upgraded, if issues are found, is there a rollback or damage control path?

### Data Migration Patterns

When needing to change data structures, use "old-new coexistence" strategy:

```move
// v1: Old storage structure
public struct MarketV1 has key {
    id: UID,
    price: u64,
}

// v2: New version adds fields (cannot directly modify V1)
// Instead use dynamic fields to extend
public fun get_expiry_v2(market: &MarketV1): Option<u64> {
    if df::exists_(&market.id, b"expiry") {
        option::some(*df::borrow<vector<u8>, u64>(&market.id, b"expiry"))
    } else {
        option::none()
    }
}

// Add new field to old object (migration script)
public fun migrate_add_expiry(
    market: &mut MarketV1,
    expiry_ms: u64,
    ctx: &mut TxContext,
) {
    df::add(&mut market.id, b"expiry", expiry_ms);
}
```

---

## 17.6 EVE Frontier-Specific Security Constraints

Quoting key constraints from official documentation:

| Constraint | Details |
|------|------|
| **Object Size** | Move objects max 250KB |
| **Dynamic Fields** | Single transaction can access max 1024 |
| **Struct Fields** | Single struct max 32 fields |
| **Transaction Compute Limit** | Exceeding compute limit will directly abort |
| **Certain Admin Operations** | Limited to game server signatures |

Don't just treat these constraints as "documentation knowledge points." They will directly affect your modeling approach.

For example:

- Objects have size limits, you can't stuff all state into one giant object
- Dynamic fields have access limits, you can't assume one transaction can scan the entire market
- Some operations depend on server signatures, you can't design the system as purely user-driven

---

## 17.7 Security Checklist

Before publishing contracts, check each item:

```
Permission Control
✅ Do all write functions have permission verification?
✅ Does OwnerCap verify authorized_object_id?
✅ Do AdminACL-protected functions have sponsor verification?

Math Operations
✅ Can all multiplications overflow? (u64 max about 1.8 × 10^19)
✅ Do percentage calculations use bps (basis points) to avoid precision loss?
✅ Is a >= b checked before subtraction?

State Consistency
✅ Are deposit and withdrawal logic completely symmetric?
✅ Are hot potato objects always consumed?
✅ Are atomic operations on shared objects correct?

Upgrade Compatibility
✅ Is UpgradeCap storage planned securely?
✅ Is future data migration path designed?

Test Coverage
✅ Are normal paths tested?
✅ Are all assert failure paths tested?
✅ Are boundary values tested (0, max value)?
```

### More Practical Checking Order

Each time before publishing, recommend going through in this order:

1. **Permissions**
   Who can call, call what, what changes after calling
2. **Money**
   Where money comes from, where it goes, can it possibly get lost along the way
3. **State**
   After success and failure, do objects still maintain consistency
4. **Upgrade**
   If this version needs changes later, will it lock itself up

This is more useful than purely checking off checklist items, because it forces you to re-examine design according to real risk surfaces.

---

## 🔖 Chapter Summary

| Knowledge Point | Core Takeaway |
|--------|--------|
| Move Testing Framework | `test_scenario`, `#[test]`, `#[expected_failure]` |
| Overflow Safety | Move checks by default, but must correctly handle logic errors |
| Permission Checks | All write operations must verify Capability + object_id binding |
| Race Conditions | Sui writes to shared objects execute sequentially, atomic operations are safe |
| Contract Upgrades | UpgradeCap + compatibility rules + dynamic field migration |
| EVE Frontier Constraints | 250KB objects, 1024 dynamic fields/tx, 32 struct fields |

## 📚 Further Reading

- [Builder Constraints Documentation](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
- [Move Prover](https://move-language.github.io/move/prover/prover-guide.html)
- [Sui Package Upgrade Guide](https://docs.sui.io/guides/developer/packages/upgrade)
- [Move Testing Framework](https://docs.sui.io/guides/developer/first-app/write-package#testing-with-sui-move)
