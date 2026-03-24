# Chapter 30: Extension Pattern in Practice — Official Example Deep Dive

> **Learning Objective**: Master EVE Frontier Builder extension standard development patterns through deep dive of two real official extension examples in `world-contracts/contracts/extension_examples/`.

---

> Status: Mapped to official example directory. Text is structured explanation; recommend reading while opening extension example source code.

## Minimal Call Chain

`authorize_extension<XAuth> -> Write ExtensionConfig -> Business entry validates rules -> Call World Assembly API`

## Corresponding Code Directory

- [world-contracts/contracts/extension_examples](https://github.com/evefrontier/world-contracts/tree/main/contracts/extension_examples)

## Key Structs

| Type | Purpose | Reading Focus |
|------|------|------|
| `AdminCap` | Management capability for configuring extension rules | Who can write config, who can only read config |
| `XAuth` / witness type | Binds extension authorization identity | How witness type becomes extension switch |
| Config object / dynamic field key | Stores extension rules | Whether rule key matches business entry reads |

## Key Entry Functions

| Entry | Purpose | What to Confirm |
|------|------|------|
| `authorize_extension<XAuth>` | Authorize witness to World building | Whether authorization type matches extension package type exactly |
| Config write entry | Initialize tribe / bounty rules | Whether write key and read key match |
| Extension business entry | Actually execute business rules | Whether only reads own config, doesn't assume World kernel is modified |

## Most Easily Misunderstood Points

- Extension pattern isn't "modifying World contract source code," but hooking behavior through witness and config objects
- Successful authorization doesn't mean business will run; inconsistent config keys still can't read rules
- Once witness type is wrong, problem usually isn't in logic but in authorization chain itself

Extension pattern's real power isn't "can insert custom code," but it controls extension capability within a very clear boundary: **World continues to control core assets and core state, Builder only rewrites rules at allowed facets**. This makes EVE's extensions more like constrained composition rather than arbitrary monkey patching. You can change who can pass gates, what to pay before passing, what configs to satisfy, but can't secretly rewrite Gate's underlying ownership and world rules.

## 1. What is Extension Pattern?

EVE Frontier's Builder extension system allows any developer to modify game building behavior (Gate, Turret, StorageUnit, etc.) without modifying World contract itself.

Core design: **Typed Witness Authorization Pattern**

```
World Contract                       Builder Extension Package
─────────────                        ─────────────
Gate has key {                       pub struct XAuth {}
  extension: Option<TypeName>  ←──── gate::authorize_extension<XAuth>()
}
                                     When gate activates XAuth, game engine
                                     calls extension functions in XAuth's package
```

---

## 2. Official Example Overview

`extension_examples` contains two typical examples:

| Example File | Function | Authorization Type |
|---------|------|---------|
| `tribe_permit.move` | Only allow specific tribe characters to use gate | Identity filtering |
| `corpse_gate_bounty.move` | Submit corpse as "toll" to use gate | Item consumption |

Both rely on shared config framework: `config.move`

---

## 3. Shared Config Framework: `config.move`

```move
module extension_examples::config;

use sui::dynamic_field as df;

/// Admin capability
public struct AdminCap has key, store { id: UID }

/// Extension's authorization witness type (Typed Witness)
public struct XAuth has drop {}

/// Extension config shared object (uses dynamic fields to store various rules)
public struct ExtensionConfig has key {
    id: UID,
    admin: address,
}

/// Dynamic field operations: add/update rules
public fun set_rule<K: copy + drop + store, V: store>(
    config: &mut ExtensionConfig,
    _: &AdminCap,           // Only AdminCap holders can set rules
    key: K,
    value: V,
) {
    if (df::exists_(&config.id, key)) {
        df::remove<K, V>(&mut config.id, key);
    };
    df::add(&mut config.id, key, value);
}

/// Check if rule exists
pub fun has_rule<K: copy + drop + store>(config: &ExtensionConfig, key: K): bool {
    df::exists_(&config.id, key)
}

/// Read rule
pub fun borrow_rule<K: copy + drop + store, V: store>(
    config: &ExtensionConfig,
    key: K,
): &V {
    df::borrow(&config.id, key)
}

/// Get XAuth instance (only callable within package)
pub(package) fun x_auth(): XAuth { XAuth {} }
```

**Design Highlight**: `ExtensionConfig` uses dynamic fields to store different types of "rules," each rule has its own Key type (like `TribeConfigKey`, `BountyConfigKey`), don't interfere with each other, can be combined arbitrarily.

This is why both dynamic field and typed witness are used here. Dynamic field solves "how rules are stored and extended," typed witness solves "who is qualified to trigger this rule set." Former is data-facing, latter is permission-facing. Many beginners writing extensions first time only focus on building config tables, but forget the most critical authorization chain, final manifestation is configs are there, code compiles, but World doesn't recognize this extension identity at all.

---

## 4. Example One: Tribe Permit (`tribe_permit.move`)

### Function

Only characters belonging to a specific `tribe` can pass through this Gate.

### Core Structure

```move
module extension_examples::tribe_permit;

/// Dynamic field Key
public struct TribeConfigKey has copy, drop, store {}

/// Dynamic field Value
public struct TribeConfig has drop, store {
    tribe: u32,   // Allowed tribe ID
}
```

### Issue Permit (Core Logic)

```move
pub fun issue_jump_permit(
    extension_config: &ExtensionConfig,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    _: &AdminCap,           // Requires AdminCap (prevent abuse)
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. Read tribe config
    assert!(extension_config.has_rule<TribeConfigKey>(TribeConfigKey {}), ENoTribeConfig);
    let tribe_cfg = extension_config.borrow_rule<TribeConfigKey, TribeConfig>(TribeConfigKey {});

    // 2. Verify character tribe
    assert!(character.tribe() == tribe_cfg.tribe, ENotStarterTribe);

    // 3. 5-day validity period (in milliseconds)
    let expires_at_timestamp_ms = clock.timestamp_ms() + 5 * 24 * 60 * 60 * 1000;

    // 4. Call world::gate to issue JumpPermit NFT
    gate::issue_jump_permit<XAuth>(   // Use XAuth as witness
        source_gate,
        destination_gate,
        character,
        config::x_auth(),               // Get witness instance
        expires_at_timestamp_ms,
        ctx,
    );
}
```

### Admin Configuration

```move
pub fun set_tribe_config(
    extension_config: &mut ExtensionConfig,
    admin_cap: &AdminCap,
    tribe: u32,
) {
    extension_config.set_rule<TribeConfigKey, TribeConfig>(
        admin_cap,
        TribeConfigKey {},
        TribeConfig { tribe },
    );
}
```

---

## 5. Example Two: Corpse Bounty Gate (`corpse_gate_bounty.move`)

### Function

Player must deposit a specific type of "corpse item" from inventory into Builder's StorageUnit to get permission to pass Gate.

### Complete Flow

```move
pub fun collect_corpse_bounty<T: key + store>(
    extension_config: &ExtensionConfig,
    storage_unit: &mut StorageUnit,      // Builder's item storage
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,               // Player character
    player_inventory_owner_cap: &OwnerCap<T>,  // Player's item ownership credential
    corpse_item_id: u64,                 // Corpse item_id to submit
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. Read bounty config (what type of corpse needed)
    assert!(extension_config.has_rule<BountyConfigKey>(BountyConfigKey {}), ENoBountyConfig);
    let bounty_cfg = extension_config.borrow_rule<BountyConfigKey, BountyConfig>(BountyConfigKey {});

    // 2. Withdraw corpse item from player inventory
    //    OwnerCap<T> proves player has authority to operate this item
    let corpse = storage_unit.withdraw_by_owner<T>(
        character,
        player_inventory_owner_cap,
        corpse_item_id,
        1,    // Quantity
        ctx,
    );

    // 3. Verify corpse type matches bounty requirement
    assert!(corpse.type_id() == bounty_cfg.bounty_type_id, ECorpseTypeMismatch);

    // 4. Deposit corpse into Builder's StorageUnit (as "collection")
    storage_unit.deposit_item<XAuth>(
        character,
        corpse,
        config::x_auth(),
        ctx,
    );

    // 5. Issue JumpPermit with 5-day validity
    let expires_at_timestamp_ms = clock.timestamp_ms() + 5 * 24 * 60 * 60 * 1000;
    gate::issue_jump_permit<XAuth>(
        source_gate, destination_gate, character,
        config::x_auth(), expires_at_timestamp_ms, ctx,
    );
}
```

---

## 6. Comparison of Two Patterns

```
tribe_permit (identity verification):
  Player → [Provide Character object] → Verify tribe_id → Issue JumpPermit

corpse_gate_bounty (item consumption):
  Player → [Provide corpse item] → Transfer to Builder → Issue JumpPermit
```

| Attribute | tribe_permit | corpse_gate_bounty |
|------|-------------|-------------------|
| Verification method | Character attribute | Item ownership |
| Resource consumption | None (permit has time limit) | Consumes one corpse item |
| Reusable | Yes (each time needs AdminCap signing) | Each time needs item consumption |
| Application scenario | Social gating (alliance exclusive) | Economic incentive (bounty hunter) |

These two official examples actually correspond to Builders' two most common extension approaches: **identity filtering** and **resource exchange**. Former focuses on "who you are," latter focuses on "what you bring to exchange." Once you understand these two parent patterns, many other gameplay are just variants, like whitelist markets, loot exchange, quest tickets, membership privileges, consumable activation, etc., can all be combined along these two paths.

---

## 7. Builder Development Checklist

Based on two official examples, steps to develop a standard Extension:

```
1. Define XAuth witness type (one per extension package)
2. Create ExtensionConfig shared object
3. Create AdminCap (for managing config)
4. Define rule structs (XxxConfig) and corresponding Key types (XxxConfigKey)
5. Implement management functions: set_xxx_config (requires AdminCap)
6. Implement core logic: check rules → business logic → call gate::issue_jump_permit<XAuth>
7. In init() create and transfer ExtensionConfig and AdminCap
```

When actually implementing, recommend checking one more thing: **after extension fails, is World's core state still safe**. A good extension even if can't read config, permissions don't match, payment insufficient, should only abort this business, not leave Gate, StorageUnit, Character in half-completed state. This is also why World tightly controls core asset operation access, trying to keep failure rollback within extension boundaries.

---

## 8. My First Extension: Toll Gate

```move
module my_toll::paid_gate;

use my_toll::config::{Self, AdminCap, XAuth, ExtensionConfig};
use world::{character::Character, gate::{Self, Gate}};
use sui::{coin::{Self, Coin}, sui::SUI, balance::{Self, Balance}};
use sui::clock::Clock;

public struct TollConfigKey has copy, drop, store {}
public struct TollConfig has drop, store { toll_amount: u64 }

public struct TollVault has key {
    id: UID,
    balance: Balance<SUI>,
}

public fun pay_toll_and_jump(
    extension_config: &ExtensionConfig,
    vault: &mut TollVault,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let toll_cfg = extension_config.borrow_rule<TollConfigKey, TollConfig>(TollConfigKey {});
    assert!(coin::value(&payment) >= toll_cfg.toll_amount, 0);

    let toll = coin::split(&mut payment, toll_cfg.toll_amount, ctx);
    balance::join(&mut vault.balance, coin::into_balance(toll));
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    let expires = clock.timestamp_ms() + 60 * 60 * 1000; // 1 hour pass
    gate::issue_jump_permit<XAuth>(
        source_gate, destination_gate, character,
        config::x_auth(), expires, ctx,
    );
}
```

---

## Chapter Summary

| Concept | Key Points |
|------|------|
| Typed Witness (`XAuth`) | Each extension package's unique authorization credential, passed into `gate::issue_jump_permit<XAuth>` |
| `ExtensionConfig` | Uses dynamic fields to store extensible rules, supports arbitrary rule type combinations |
| `TribeConfigKey/BountyConfigKey` | Identifying Keys for different rules, avoid type collision |
| `AdminCap` | Controls who can modify extension config |
| `OwnerCap<T>` | Player item operation authorization credential |

> Next Chapter: **Turret AI Extension Development** — Analyzing target priority queue system through `world::turret`, developing custom turret AI extensions.
