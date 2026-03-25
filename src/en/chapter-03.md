# Chapter 3: Move Smart Contract Fundamentals

> **Objective:** Master core concepts of the Move language, understand the Sui object model, and be able to read and modify EVE Frontier contract code.

---

> Status: Foundation chapter. Main text focuses on Move language, object model, and minimal examples.

## 3.1 Move Language Overview

Move is the smart contract language used by Sui, specifically designed for the problem that "on-chain assets cannot be arbitrarily copied, discarded, or transferred." It's not about first writing a general programming language and then using libraries to constrain assets; rather, it treats "resources" as the most important objects at the language level.

You can first grasp three intuitions:

- **Assets aren't just balance numbers**
  On Sui, many assets are truly independent objects with their own `id`, fields, ownership, and lifecycle
- **Types determine whether you can copy, store, discard**
  Move uses an ability system to restrict what you can do with a value, preventing you from mistakenly treating "precious assets" as ordinary variables
- **Contracts are more like modules + object systems**
  What you write isn't "one giant global state," but a set of module functions to create, read, and modify objects

So learning Move isn't just about learning syntax. What you really need to establish is a new way of thinking:

1. First distinguish between ordinary data and resources
2. Then distinguish who owns objects, who can modify them, who can transfer them
3. Only then write these rules into function entries and business processes

This is also well-suited to EVE Frontier. Because in EVE, many things are naturally not "a row in a database record," but more like independently existing assets or facilities:

- A pass NFT
- A smart stargate
- A storage unit
- A permission credential
- A kill record

When these things are in Move, the expression becomes very natural.

---

## 3.2 Module Structure

A Move contract consists of one or more **modules**:

```move
// File: sources/my_contract.move

// Module declaration: package_name::module_name
module my_package::my_module {

    // Import dependencies
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::transfer;

    // Struct definition (assets/data)
    public struct MyObject has key, store {
        id: UID,
        value: u64,
    }

    // Init function (automatically executed once during contract deployment)
    fun init(ctx: &mut TxContext) {
        let obj = MyObject {
            id: object::new(ctx),
            value: 0,
        };
        transfer::share_object(obj);
    }

    // Public function (can be called externally)
    public fun set_value(obj: &mut MyObject, new_value: u64) {
        obj.value = new_value;
    }
}
```

Although this code is short, it already contains the four most common types of Move elements:

- **Module declaration**
  `module my_package::my_module` indicates "this file defines a module"
- **Dependency imports**
  `use` is used to introduce types or functions exposed by other modules
- **Struct definition**
  `MyObject` describes what an on-chain object looks like
- **Function entries**
  Functions like `init`, `set_value` define how objects are created and modified

### What's the Relationship Between Modules and Packages?

Many newcomers conflate "packages" and "modules" into one thing, but they're actually not at the same level:

- **Package**
  Is an entire Move project directory, typically containing `Move.toml`, `sources/`, `tests/`
- **Module**
  Is a code unit within a package, a package can have multiple modules

Here's a structure closer to a real project:

```text
my-extension/
├── Move.toml
├── sources/
│   ├── gate_logic.move
│   ├── gate_auth.move
│   └── pricing.move
└── tests/
    └── gate_tests.move
```

Here:

- `my-extension` is a package
- `gate_logic`, `gate_auth`, `pricing` are three modules

You can think of "package" as a deployment unit, and "module" as a code organization unit.

### Why is `init` Important?

`init` executes once when the package is first published. Common uses include:

- Create shared objects
- Send `AdminCap` to the deployer
- Initialize global configuration
- Establish registry objects

It's typically the "boot action when the system first comes online." If you don't create key objects properly in `init`, many entry functions won't work properly later.

### Why Do Fields Almost Always Start with `id: UID`?

Because on Sui, a true on-chain object must have `UID`, which represents a globally unique identity. Structs without `UID` are often just:

- Ordinary nested data
- Configuration items
- Event payloads
- One-time credentials

This is also your first clue when reading EVE contracts to determine "is this an independent object or not."

---

## 3.3 Move's Abilities (Ability System)

This is one of the most important concepts in Move. Each struct type can have the following abilities:

| Ability | Keyword | Meaning |
|------|--------|------|
| **Key** | `has key` | Can be a Sui object, stored in global state |
| **Store** | `has store` | Can be nested and stored in other objects |
| **Copy** | `has copy` | Can be implicitly copied (use cautiously!) |
| **Drop** | `has drop` | Can be automatically discarded when function ends (not using it is okay) |

Don't treat abilities as "syntax decoration." They're essentially answering a very serious question:

> How is this value allowed to be handled by developers?

### What Do the Four Abilities Mean?

#### 1. `key`

`has key` indicates this type can exist as a top-level on-chain object.

Common characteristics:

- Usually contains `id: UID`
- Can be owned by an address, shared, or owned by an object
- Can be a core object for transaction reads/writes

Without `key`, this type cannot independently hang in on-chain global state.

#### 2. `store`

`has store` indicates this type can be safely placed in other object fields.

For example:

- Put a configuration struct into `StorageUnit`
- Put a whitelist rule into `SmartAssembly`
- Embed metadata structure into NFT

Often, a type isn't an independent object, but it must be able to exist as a component of other objects—this is when you need `store`.

#### 3. `copy`

`has copy` indicates this value can be copied.

This is usually only suitable for:

- Small pure data
- Values that don't represent scarce resources
- Similar to ID, boolean markers, enums, simple configurations

If something represents "permission," "asset," "unique credential," it usually shouldn't be given `copy`.

#### 4. `drop`

`has drop` indicates this value can be directly discarded if not used.

This ability seems inconspicuous, but is actually quite critical. Because Move is very strict by default: if a value isn't properly consumed, the compiler will chase you asking "what exactly do you plan to do with it?"

So:

- With `drop`, not using it is okay
- Without `drop`, you must explicitly consume or transfer it

### Why Do Abilities Directly Affect Security?

Because many security boundaries are not guarded by `if` judgments, but by "the type simply doesn't allow you to do this."

For example:

- If an NFT doesn't have `copy`, you can't duplicate a second copy
- If a hot potato object doesn't have `drop`, you can't secretly ignore it
- If a permission object doesn't have a public construction path, external parties can't forge it

This is one of Move's strong points: it moves many business constraints forward into the type system.

### Application in EVE Frontier

```move
// JumpPermit: has key + store, is a real on-chain asset, cannot be copied
public struct JumpPermit has key, store {
    id: UID,
    character_id: ID,
    route_hash: vector<u8>,
    expires_at_timestamp_ms: u64,
}

// VendingAuth: only has drop, is a one-time "credential" (Witness Pattern)
public struct VendingAuth has drop {}
```

These two examples can be viewed together:

- `JumpPermit` is a true object that should exist on-chain, so it has `key`
- `VendingAuth` is only a witness value in a call flow, doesn't need on-chain persistence, so only given `drop`

When reading EVE contracts, you can often directly guess the author's intent through abilities:

- `has key, store`: Likely a real object or quasi-object
- Only `drop`: Likely witness, receipt, one-time intermediate state
- `copy, drop, store`: Likely ordinary value type or configuration data

---

## 3.4 Sui Object Model Explained

On Sui, all structs with `key` ability are **objects**, divided into three ownership types:

### Ownership Types

```
1. Address-owned
   └── Only the person holding that address can access
   └── Example: Player character's OwnerCap

2. Shared Object
   └── Anyone can read/write on-chain (controlled by contract logic)
   └── Example: Smart storage unit, stargate body

3. Object-owned
   └── Held by another object, external cannot directly access
   └── Example: Configuration stored inside components
```

These three ownership types aren't abstract classifications, but one of the most core decisions when designing business models.

### 1. Address-owned: Most Like "My Assets"

Address-owned objects are typically suitable for:

- Player personal NFTs
- `OwnerCap`
- Character private credentials
- Transferable tickets, permits, badges

Characteristics are:

- Controlled by a certain address
- Transaction usually requires signature from that address
- Very suitable for expressing "who owns, who controls"

### 2. Shared Objects: Most Like "Public Facilities"

Shared objects are suitable for:

- Markets
- Stargates
- Storage units
- Alliance vaults
- Server-wide registries

The focus isn't "who owns this object," but "who can perform what operations on it under what rules."

This is the core form of many EVE Frontier facility contracts. Because although a facility also has an operator, it's first a public object that will be interacted with by many players together.

### 3. Object-owned: Most Like "Facility Internal Components"

Object ownership is commonly used to hide complex internal state, such as:

- Configuration object inside a facility
- Inventory table inside a component
- Auxiliary index inside a registry

Its benefit is encapsulating state, not letting external parties randomly take it out and misuse it.

### Why is the Object Model Easier to Express Game Worlds Than "Global Mapping"?

Because many entities in games are naturally independently existing, can be referenced, can be transferred, can be composed:

- A turret
- A permit
- A character permission
- An alliance treaty

If all stuffed into one big table, logic becomes more and more like "database management scripts." The object model is closer to real-world "entities + relationships + ownership."

### Objects Don't Just Have Two States of "Exist or Not"

When designing, you also need to consider object lifecycle:

1. **Creation**
   Who creates it? In `init` or in business entry?
2. **Holding**
   Who owns it after creation? Address, shared, or object internal?
3. **Modification**
   Who can get `&mut`? Under what premise is modification allowed?
4. **Transfer**
   Can it be transferred? Do permissions follow after transfer?
5. **Destruction**
   When can it disappear? Need to settle balance or reclaim resources before destruction?

### Deterministic Derivation of Object IDs

In EVE Frontier, each in-game entity's ObjectID on-chain is deterministically derived through `TenantItemId`:

```move
public struct TenantItemId has copy, drop, store {
    item_id: u64,          // Unique ID in-game
    tenant: String,        // Distinguish different game server instances
}
```

This means after the game server knows `item_id`, it can **pre-calculate** that item's ObjectID on-chain without waiting for on-chain response.

This is very important in the EVE scenario, because off-chain servers and on-chain objects need long-term alignment:

- Game server knows a facility's, character's, item's business ID
- Contract needs to map it to on-chain object keys using stable rules
- Front-end and indexing services query according to the same rules

If this mapping isn't stable, the entire system will be chaotic:

- Off-chain considers it the same facility
- On-chain found another object
- Data displayed by front-end and real interactive objects don't match

So when you later see `TenantItemId`, `derived_object`, registries, you need to first realize: the author is solving not "how to write code," but "how to keep cross-system identity consistent."

---

## 3.5 Key Security Patterns

EVE Frontier and other Sui projects widely use several Move-specific security design patterns:

### Pattern 1: Capability Pattern

Permissions are represented by holding objects, not account roles.

```move
// Define capability object
public struct OwnerCap<phantom T> has key, store {
    id: UID,
}

// Function that requires OwnerCap to call
public fun withdraw_by_owner<T: key>(
    storage_unit: &mut StorageUnit,
    owner_cap: &OwnerCap<T>,  // Must hold this credential
    ctx: &mut TxContext,
): Item {
    // ...
}
```

**Advantage**: `OwnerCap` can be transferred, can be delegated, more flexible than account-level permissions.

You can think of Capability as "permission materialization":

- Traditional thinking is often "determine if `sender == admin`"
- Move/Sui's more common thinking is "do you hold a certain permission object"

This brings several direct benefits:

- Permissions can be transferred
- Permissions can be split
- Permissions can be made into NFT / Badge / Cap
- Permission relationships are easier to audit on-chain

### Pattern 2: Typed Witness Pattern

**This is the core of EVE Frontier's extension system!** Used to verify the caller is a specific package's module.

```move
// Builder defines a Witness type in their own package
module my_extension::custom_gate {
    // Only this module can create Auth instances (because it has no public constructor)
    public struct Auth has drop {}

    // When calling stargate API, pass Auth {} as credential
    public fun request_jump(
        gate: &mut Gate,
        character: &Character,
        ctx: &mut TxContext,
    ) {
        // Custom logic (e.g., check fees)
        // ...

        // Use Auth {} to prove call comes from this authorized module
        gate::issue_jump_permit(
            gate, destination, character,
            Auth {},      // Witness: prove I am my_extension::custom_gate
            expires_at,
            ctx,
        )
    }
}
```

The Star Gate component knows your `Auth` type has been registered in the whitelist, so it allows the call.

This pattern feels strange the first time because `Auth {}` has no data inside. But what it really wants to express is:

> "I'm not proving identity through field content, I'm proving which module I'm from through the type itself."

Why is this strong?

- External modules can't arbitrarily forge your witness type
- Components can only trust witness types in the whitelist
- So "who can call a certain underlying capability" can be restricted to specific extension packages

This is the core of EVE Frontier's extensible components. Many components don't simply expose a `public entry` for anyone to call, but require you to bring a specific witness to enter.

### Pattern 3: Hot Potato

An object with no `copy`, `store`, `drop` abilities, must be consumed within the same transaction:

```move
// No abilities = hot potato, must be handled in this tx
public struct NetworkCheckReceipt {}

public fun check_network(node: &NetworkNode): NetworkCheckReceipt {
    // Perform check...
    NetworkCheckReceipt {}  // Return hot potato
}

public fun complete_action(
    assembly: &mut Assembly,
    receipt: NetworkCheckReceipt,  // Must pass in, ensures check was executed
) {
    let NetworkCheckReceipt {} = receipt; // Consume hot potato
    // Formally execute operation
}
```

**Purpose**: Force certain operations to be atomically combined (e.g., "first check network node → then execute component operation").

This pattern is especially suitable for "prerequisite checks cannot be skipped" processes:

- First verify eligibility, then mint credential
- First check network status, then execute facility action
- First read and lock a certain context, then settle

Its focus isn't storing data, but using the type system to force callers to do things in order.

---

## 3.6 Function Visibility and Access Control

```move
module example::access_demo {

    // Private function: can only be called within this module
    fun internal_logic() { }

    // Package-visible: other modules in the same package can call (Layer 1 Primitives use this)
    public(package) fun package_only() { }

    // Entry: can be directly called as top-level of a Transaction
    public fun user_action(ctx: &mut TxContext) { }

    // Public: any module can call
    public fun read_data(): u64 { 42 }
}
```

---

## 3.7 Writing Your First Move Extension Module

Let's combine the above concepts to write a simplest Storage Unit extension:

```move
module my_extension::simple_vault;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::tx_context::TxContext;

// Our Witness type
public struct VaultAuth has drop {}

/// Anyone can deposit items (open deposit)
public fun deposit_item(
    storage_unit: &mut StorageUnit,
    character: &Character,
    item: Item,
    ctx: &mut TxContext,
) {
    // Use VaultAuth{} as witness, proving this call is a legally bound extension
    storage_unit::deposit_item(
        storage_unit,
        character,
        item,
        VaultAuth {},
        ctx,
    )
}

/// Only characters with specific Badge (NFT) can withdraw items
public fun withdraw_item_with_badge(
    storage_unit: &mut StorageUnit,
    character: &Character,
    _badge: &MemberBadge,  // Must hold member badge to call
    type_id: u64,
    ctx: &mut TxContext,
): Item {
    storage_unit::withdraw_item(
        storage_unit,
        character,
        VaultAuth {},
        type_id,
        ctx,
    )
}
```

---

## 3.8 Compilation and Testing

```bash
# In your Move package directory
cd my-extension

# Compile (checks types and logic)
sui move build

# Run unit tests
sui move test

# Publish to testnet
sui client publish
```

After successful publication, you'll get a `Package ID` (like `0xabcdef...`), which is your contract's on-chain address.

---

## 🔖 Chapter Summary

| Concept | Key Points |
|------|--------|
| Move Module | `module package::name { }` is code organization unit |
| Abilities | `key`(object) `store`(nestable) `copy`(copyable) `drop`(discardable) |
| Three Ownerships | Address-owned / Shared object / Object-owned |
| Capability Pattern | Permission = holding object, can transfer can delegate |
| Witness Pattern | Uniquely instantiated type as call credential, EVE Frontier extension core |
| Hot Potato | No-ability struct, force atomic operations |

## 📚 Extended Reading

- [Move Book (Official)](https://move-book.com)
- [Sui Move Concepts](https://docs.sui.io/concepts/sui-move-concepts)
- [Typed Witness Pattern](https://move-book.com/programmability/witness-pattern)
- [Capability Pattern](https://move-book.com/programmability/capability)
- [EVE Frontier World Contract Code](https://github.com/evefrontier/world-contracts)
