# Chapter 32: KillMail System Deep Dive

> **Learning Objective**: Understand EVE Frontier's complete architecture for on-chain combat death records — from source code structure to interaction methods with Builder extensions.

---

> Status: Teaching example. Code in text is simplified for explanation; for source verification please refer to actual `world-contracts` files in repository.

## Minimal Call Chain

`Game server -> AdminACL validation -> create_killmail -> derived_object::claim -> share_object -> emit event`

## Corresponding Code Directory

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)

## Key Structs

| Type | Purpose | Reading Focus |
|------|------|------|
| `Killmail` | On-chain kill record shared object | How unique key, timestamp, kill parties and location are persisted |
| `LossType` | Distinguish ship/structure loss | How it affects upper-layer business interpretation |
| `KillmailRegistry` | Registry and index entry | How it avoids duplicate creation, how to locate records |
| `TenantItemId` | In-game object to on-chain mapping key | How tenant + item_id forms stable business key |

## Key Entry Functions

| Entry | Purpose | What to Confirm |
|------|------|------|
| `create_killmail` | Create kill record | Whether sponsor validation, uniqueness validation, anti-replay are done first |
| `derived_object::claim` related path | Generate deterministic object ID | Whether business key is stable, whether will be repeatedly claimed |
| Registry read/write entry | Establish lookup relationships | Whether Registry is just index, not record body itself |

## Most Easily Misunderstood Points

- `Killmail` isn't pure event log, but queryable, indexable shared object
- `Registry` isn't for "storing another copy of data," but for stable retrieval and uniqueness constraints
- Uniqueness comes from business key + `derived_object` path, not randomly generating a new UID

When reading this chapter, best to bring two perspectives simultaneously: **object perspective** and **index perspective**. Object perspective cares about "what state is actually settled on-chain, can subsequent contracts read it directly"; index perspective cares about "how off-chain services stably discover it, aggregate it, locate it by business key." Why KillMail is heavier than ordinary events is because EVE treats it as reusable world state for long-term, not one-time broadcast message. Many Builders first encountering this feel "since already emitting events, why also share_object a copy," fundamental reason is here: events suit broadcasting and statistics, objects suit subsequent contract composition, permission validation and deterministic addressing.

##  2.1 What is KillMail?

In EVE Frontier, each player-vs-player (PvP) kill event generates an immutable record on-chain, called **KillMail**. This isn't just a log — it's a shared object with unique object ID that anyone can query on-chain.

```
On-chain Structure Relationships:
KillmailRegistry (registry)
    └── Killmail (shared object)
            ├── killer_id    : Killer TenantItemId
            ├── victim_id    : Victim TenantItemId
            ├── kill_timestamp (Unix seconds)
            ├── loss_type    : SHIP | STRUCTURE
            └── solar_system_id : Location solar system
```

---

##  2.2 KillMail Core Data Structure

### Source Code Deep Dive (`world/sources/killmail/killmail.move`)

```move
// === Enums ===
/// Kill type: Ship or Structure
public enum LossType has copy, drop, store {
    SHIP,
    STRUCTURE,
}

/// On-chain KillMail shared object
public struct Killmail has key {
    id: UID,
    key: TenantItemId,                  // Deterministic ID from item_id + tenant
    killer_id: TenantItemId,
    victim_id: TenantItemId,
    reported_by_character_id: TenantItemId,
    kill_timestamp: u64,                // Unix timestamp (seconds, not milliseconds!)
    loss_type: LossType,
    solar_system_id: TenantItemId,
}
```

> **Key Design**: Killmail's `id` isn't randomly generated, but deterministically derived via `derived_object::claim(registry, key)` from `KillmailRegistry`, ensuring `item_id → object_id` mapping uniqueness.

### What is TenantItemId?

```move
// world/sources/primitives/in_game_id.move
public struct TenantItemId has copy, drop, store {
    item_id: u64,    // Game internal business ID
    tenant: String,  // Game tenant identifier (like "evefrontier")
}
```

```move
// Creation method
let key = in_game_id::create_key(item_id, tenant);
```

This design allows same `item_id` to be reused across different tenants (different servers/game versions) without conflict.

---

##  2.3 KillMail Creation Flow

### Full Flow Analysis

```move
public fun create_killmail(
    registry: &mut KillmailRegistry,
    admin_acl: &AdminACL,           // Only authorized servers can create
    item_id: u64,                   // Kill record's in-game ID
    killer_id: u64,
    victim_id: u64,
    reported_by_character: &Character,  // Reporting character (must be present)
    kill_timestamp: u64,            // Unix seconds
    loss_type: u8,                  // 1=SHIP, 2=STRUCTURE
    solar_system_id: u64,
    ctx: &mut TxContext,
) {
    // 1. Verify caller is authorized server
    admin_acl.verify_sponsor(ctx);

    // 2. Generate key using reporter's tenant
    let tenant = reported_by_character.tenant();
    let killmail_key = in_game_id::create_key(item_id, tenant);

    // 3. Prevent duplicate creation
    assert!(!registry.object_exists(killmail_key), EKillmailAlreadyExists);

    // 4. Verify key fields non-zero
    assert!(item_id != 0, EKillmailIdEmpty);
    assert!(killer_id != 0, ECharacterIdEmpty);
    // ...

    // 5. Derive deterministic UID from registry (core mechanism)
    let killmail_uid = derived_object::claim(registry.borrow_registry_id(), killmail_key);

    // 6. Create and share
    let killmail = Killmail { id: killmail_uid, ... };
    transfer::share_object(killmail);
}
```

### Flow Diagram

```
Game Server → create_killmail()
                ↓
       verify_sponsor (AdminACL check)
                ↓
       create_key(item_id, tenant)
                ↓
       object_exists? → Yes → ABORT EKillmailAlreadyExists
                ↓ No
       derived_object::claim → Deterministic UID
                ↓
       Killmail {..} → share_object
                ↓
       emit KillmailCreatedEvent
```

---

##  2.4 Event System and Off-Chain Indexing

```move
public struct KillmailCreatedEvent has copy, drop {
    key: TenantItemId,
    killer_id: TenantItemId,
    victim_id: TenantItemId,
    reported_by_character_id: TenantItemId,
    loss_type: LossType,
    kill_timestamp: u64,
    solar_system_id: TenantItemId,
}
```

KillMail uses **event indexing + object storage dual-track system**:

| Component | Use |
|------|------|
| On-chain shared object `Killmail` | Can be read by contracts, Builder extensions can query |
| `KillmailCreatedEvent` | For index services to monitor in real-time, build leaderboards/statistics |

In this dual-track design, events aren't state truth, but **discovery mechanism**. Indexers typically first learn "a new KillMail appeared" via events, then read object body on-chain based on object ID or business key. Benefit is off-chain leaderboards, achievement systems, battle reports can consume events at high throughput, but when actually involving reward distribution, dispute arbitration, subsequent extension reads/writes, can still return to object layer to get stable state. Otherwise if only relying on events, subsequent Builder contracts have no unified on-chain read entry.

---

##  2.5 How Do Builders Use KillMail?

### Scenario: Kill Score Reward System

Builder can listen to `KillmailCreatedEvent` events, receive reward requests in own extension contract:

```move
module my_pvp::kill_reward;

use world::killmail::Killmail;
use world::access::OwnerCap;
use sui::coin::{Self, Coin};
use sui::sui::SUI;

public struct RewardPool has key {
    id: UID,
    balance: Balance<SUI>,
    reward_per_kill: u64,
    owner: address,
}

/// Player submits KillMail object to claim SUI reward
pub fun claim_kill_reward(
    pool: &mut RewardPool,
    killmail: &Killmail,           // Pass in on-chain KillMail object
    character_id: ID,              // Caller's character ID
    ctx: &mut TxContext,
) {
    // Verify killmail.killer_id corresponds to current caller's character
    // (Actually needs OwnerCap verification)
    assert!(balance::value(&pool.balance) >= pool.reward_per_kill, 0);

    let reward = coin::take(&mut pool.balance, pool.reward_per_kill, ctx);
    transfer::public_transfer(reward, ctx.sender());
}
```

### Scenario: KillMail-Based NFT Badge

```move
/// Mint "Centurion Badge" NFT after 100 kills
public fun mint_centurion_badge(
    tracker: &KillTracker,           // Self-built kill count tracking object
    recipient: address,
    ctx: &mut TxContext,
) {
    assert!(tracker.kill_count >= 100, ENotEnoughKills);
    // Mint NFT...
}
```

---

##  2.6 `derived_object` Pattern Deep Dive

KillMail uses Sui's `derived_object` (deterministic object ID) pattern, an important design in EVE Frontier World contracts:

```move
// Derive deterministic UID from registry
let killmail_uid = derived_object::claim(registry.borrow_registry_id(), killmail_key);
```

**Why not use `object::new(ctx)`?**

| Comparison | `object::new(ctx)` | `derived_object::claim()` |
|---|---|---|
| ID source | Random (based on tx digest) | Deterministic (based on key) |
| Duplicate creation | Cannot prevent (new ID each time) | Auto-prevents (key can only be used once) |
| Off-chain precomputation | Impossible | Possible (knowing key means knowing ID) |
| Use case | Ordinary objects | Game assets, KillMail and other objects with business IDs |

---

##  2.7 KillMail Registry Design

```move
// world/sources/registry/killmail_registry.move
public struct KillmailRegistry has key {
    id: UID,
    // Note: No other fields! All data stored via derived_object
}

pub fun object_exists(registry: &KillmailRegistry, key: TenantItemId): bool {
    derived_object::exists(&registry.id, key)
}
```

This registry is extremely minimal — it's just a `UID` container, all KillMails exist as its `derived children` in Sui's state tree.

The key design philosophy here: **Registry doesn't store business details, only provides namespace and uniqueness anchor**. This approach is lighter than "Registry contains another Table<key, object_id>" because real uniqueness is already guaranteed by `derived_object`. You can understand it as a "parent directory" rather than "database table." Once Builders understand this approach, later when seeing deterministic object patterns for characters, buildings, permits, credentials, it will be much easier.

---

##  2.8 Security Analysis

### Only Server Can Create

```move
admin_acl.verify_sponsor(ctx);
```

`verify_sponsor` checks if caller is in `AdminACL.authorized_sponsors` list. Ordinary players **cannot** forge KillMail — each kill record is signed by address linked to game server key.

### Anti-Replay

```move
assert!(!registry.object_exists(killmail_key), EKillmailAlreadyExists);
```

Using `derived_object` existence check naturally prevents same battle from being submitted repeatedly.

---

##  2.9 Practice Exercises

1. **Read KillMail**: Write a PTB (programmable transaction block), pass in a KillMail object ID, print `killer_id`, `victim_id`, `kill_timestamp`
2. **Kill Score Contract**: Implement score system based on KillMail, 100 points per ship kill, 50 points per structure kill
3. **KillMail NFT Credential**: Design Builder extension allowing victim to claim "death compensation" based on KillMail object ID

---

## Chapter Summary

| Concept | Key Points |
|------|------|
| `Killmail` | Immutable shared object recording PvP kill events |
| `TenantItemId` | `item_id + tenant` composite key, supports multi-tenancy |
| `derived_object` | Deterministic object ID, prevents duplication, supports off-chain precomputation |
| `KillmailRegistry` | Uses UID as parent node for derived children |
| Security mechanisms | AdminACL verification + derived_object anti-replay |

> Next Chapter: **zkLogin Principles** — Understanding how EVE Vault uses zero-knowledge proofs to enable passwordless wallet access through OAuth login.
