# Chapter 26: Complete Analysis of Access Control System

> **Learning Objective**: Deeply understand the complete permission architecture of the `world::access` module—from `GovernorCap`, `AdminACL`, `OwnerCap` to `Receiving` pattern, master the precise design of EVE Frontier's access control system.

---

> Status: Teaching example. Access control details are numerous, recommended to read section by section directly against source code and tests, rather than just looking at concept diagrams.

## Minimal Call Chain

`Entry point -> Permission object/authorization list check -> Borrow or consume capability -> Execute business action -> Return or destroy capability object`

## Corresponding Code Directories

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)

## Key Structs

| Type | Purpose | Reading Focus |
|------|------|------|
| `AdminACL` | Server authorization whitelist | See how sponsor whitelist is maintained |
| `GovernorCap` | System-level highest permission capability | See which actions must go through governor not owner |
| `OwnerCap<T>` | Generic ownership credential | See three lifecycles: borrowing, returning, transferring |
| `Receiving` related patterns | Safe borrowing of object-owned assets | See difference between object-owned and address-owned |
| `ServerAddressRegistry` | Server address registry | See how signature identity and business permissions connect |

## Key Entry Functions

| Entry | Purpose | What You Should Verify |
|------|------|------|
| `verify_sponsor` | Check if submitter is in server whitelist | It solves identity source, not all business constraints |
| `borrow_owner_cap` / `return_owner_cap` | Borrow and return ownership credentials | Whether strictly follows Borrow-Use-Return |
| governor / registry management entries | Maintain system-level permission configurations | Whether system admin rights are incorrectly delegated to regular owners |

## Most Easily Misread Points

- `ctx.sender()` in EVE Frontier usually isn't enough, many scenarios must check capability or sponsor
- `OwnerCap<T>` isn't one-time consumable, often temporarily borrowed then returned
- object-owned assets cannot copy address-owned permission judgment methods

The most effective way to understand this chapter is to break permissions into 3 sources: **address identity**, **capability object**, **server endorsement**. Address identity answers "who sent this transaction"; capability object answers "what control over which specific object does he have"; server endorsement answers "is this a system action recognized by the game world". EVE Frontier uses all three sources simultaneously because relying on `ctx.sender()` alone cannot express complex item trusteeship, building control, and off-chain state injection.

## 1. Why Is Access Control System Complex?

Traditional smart contract permissions usually have only two layers: owner (owner) and public. EVE Frontier needs more precise control:

```
Game Company (CCP Level)      → GovernorCap: system-level configuration
  ├── Game Server             → AdminACL/verify_sponsor: on-chain operation authorization
  ├── Building Owner (Builder)  → OwnerCap<T>: building control
  └── Player (Character)      → Access own items through OwnerCap
```

One character's items in another player's building—who can operate this item? This is the core problem EVE Frontier access control needs to solve.

So you'll see EVE permissions don't revolve around "is a certain address the owner," but around "who currently holds a certain object, who can temporarily borrow, who can represent server to write world state". Once the object world becomes complex, the single owner field common in traditional contracts isn't fine enough.

---

## 2. AdminACL: Server Authorization Whitelist

```move
// world/sources/access/access_control.move

pub struct AdminACL has key {
    id: UID,
    authorized_sponsors: Table<address, bool>,  // Server address whitelist
}

/// Only allow registered servers to execute privileged operations
pub fun verify_sponsor(admin_acl: &AdminACL, ctx: &TxContext) {
    assert!(
        admin_acl.authorized_sponsors.contains(ctx.sender()),
        EUnauthorizedSponsor,
    );
}
```

**Usage**: All operations in World contract requiring game server permissions start with `admin_acl.verify_sponsor(ctx)`:

```move
// Create character (must be triggered by server)
pub fun create_character(..., admin_acl: &AdminACL, ...) {
    admin_acl.verify_sponsor(ctx);
    // ...
}

// Create KillMail (must be triggered by server)
pub fun create_killmail(..., admin_acl: &AdminACL, ...) {
    admin_acl.verify_sponsor(ctx);
    // ...
}
```

### Server Address Registration (Only GovernorCap Can Operate)

```move
pub fun add_sponsor_to_acl(
    admin_acl: &mut AdminACL,
    _: &GovernorCap,           // Requires highest permission
    sponsor: address,
) {
    admin_acl.authorized_sponsors.add(sponsor, true);
}
```

---

## 3. GovernorCap: System Highest Permission

```move
// GovernorCap is the system's "root key"
// Its existence means game company retains system-level configuration capability
pub struct GovernorCap has key, store { id: UID }
```

`GovernorCap` is used for:
- Adding/removing server addresses to `AdminACL`
- Registering servers to `ServerAddressRegistry` (for signature verification)
- Setting system-wide configuration parameters

```move
pub fun register_server_address(
    server_address_registry: &mut ServerAddressRegistry,
    _: &GovernorCap,
    server_address: address,
) {
    server_address_registry.authorized_address.add(server_address, true);
}
```

---

## 4. OwnerCap\<T\>: Generic Ownership Credential

This is EVE Frontier access control's most ingenious design:

```move
/// OwnerCap<T> proves holder's control over some T type object
pub struct OwnerCap<phantom T: key> has key, store {
    id: UID,
    authorized_object_id: ID,   // Bound to specific object ID
}
```

**Why use generics?**

```move
OwnerCap<Gate>           // Control over some Gate
OwnerCap<Turret>         // Control over some Turret
OwnerCap<StorageUnit>    // Control over some StorageUnit
OwnerCap<Character>      // Control over some Character
```

Type system naturally ensures permissions won't be used across types incorrectly.

### OwnerCap Creation (Only AdminACL Can Create)

```move
pub fun create_owner_cap<T: key>(
    admin_acl: &AdminACL,
    obj: &T,
    ctx: &mut TxContext,
): OwnerCap<T> {
    admin_acl.verify_sponsor(ctx);
    let object_id = object::id(obj);
    let owner_cap = OwnerCap<T> {
        id: object::new(ctx),
        authorized_object_id: object_id,
    };
    event::emit(OwnerCapCreatedEvent { ... });
    owner_cap
}
```

**Important constraint**: Players cannot create `OwnerCap` themselves, can only be issued by game server (verify_sponsor).

This layer constraint's significance is keeping "permission object minting rights" firmly within system boundaries. Otherwise once anyone can mint `OwnerCap<T>` themselves, the entire capability system loses credibility. Capability objects are reliable not just because they're on-chain objects, but because their source chain itself is controlled.

---

## 5. Receiving Pattern: Safe Borrowing of OwnerCap

This is one of EVE Frontier's most unique patterns—`OwnerCap` is usually stored under Character object's control, borrowed temporarily using Sui's `Receiving<T>` when needed:

```
Character (shared object)
  └── Holds → OwnerCap<Gate> (stored via Sui transfer::transfer)

When player operates:
  1. Player submits Receiving<OwnerCap<Gate>> ticket (proves right to extract)
  2. character::receive_owner_cap() → Temporarily extract OwnerCap<Gate>
  3. Execute operation (like modifying Gate configuration)
  4. Use return_owner_cap_to_object() to return OwnerCap to Character
```

### Source Code Implementation

```move
/// Borrow OwnerCap from Character
pub(package) fun receive_owner_cap<T: key>(
    receiving_id: &mut UID,
    ticket: Receiving<OwnerCap<T>>,   // Sui native Receiving ticket
): OwnerCap<T> {
    transfer::receive(receiving_id, ticket)
}

/// Return OwnerCap to Character
pub fun return_owner_cap_to_object<T: key>(
    owner_cap: OwnerCap<T>,
    character: &mut Character,
    receipt: ReturnOwnerCapReceipt,   // Receipt after operation completes
) {
    validate_return_receipt(receipt, object::id(&owner_cap), ...);
    transfer::transfer(owner_cap, character.character_address);
}
```

### ReturnOwnerCapReceipt Prevents Loss

```move
pub struct ReturnOwnerCapReceipt {
    owner_id: address,
    owner_cap_id: ID,
}
```

In function signature borrowing OwnerCap, must return `ReturnOwnerCapReceipt`, otherwise compilation error. This ensures:
1. OwnerCap will definitely be returned (cannot be lost)
2. Must be used in pairs (cannot forge receipt)

`Receiving` pattern seems a bit tedious on surface, essentially making object-owned lifecycle explicit. Things held by regular addresses, you can use with references; but capabilities held by objects like Character, StorageUnit, without a set of explicit "borrow-use-return" process, easily get lost or intercepted in complex call chains. EVE chooses to make this process verbose in exchange for auditable, rollbackable, strongly constrained permission flow.

---

## 6. Complete Permission Hierarchy Diagram

```
GovernorCap (root key, CCP holds)
    │
    ▼ Configure
AdminACL (server whitelist)
    │
    ▼ verify_sponsor
All privileged operations (create character, create building, issue OwnerCap...)
    │
    ▼ create_owner_cap<T>
OwnerCap<Gate>  OwnerCap<Turret>  OwnerCap<StorageUnit>...
    │                                      │
    ▼ Transfer to Character                 ▼ Transfer to Builder player
Character custody (Receiving pattern)        Direct holding
    │
    ▼ receive_owner_cap (Receiving<OwnerCap<Gate>>)
Temporarily borrow → Use → Return
```

---

## 7. ServerAddressRegistry: Signature Verification Whitelist

Unlike `AdminACL`, `ServerAddressRegistry` is specifically for signature verification (not function call permissions):

```move
pub struct ServerAddressRegistry has key {
    id: UID,
    authorized_address: Table<address, bool>,
}

pub fun is_authorized_server_address(
    registry: &ServerAddressRegistry,
    server_address: address,
): bool {
    registry.authorized_address.contains(server_address)
}
```

**Purpose**: Verify signature source in `location::verify_proximity`:

```move
assert!(
    access::is_authorized_server_address(server_registry, message.server_address),
    EUnauthorizedServer,
);
```

Here we can also see division of labor between `AdminACL` and `ServerAddressRegistry`: former leans toward "who can directly represent server to send transactions", latter leans toward "whose off-chain signatures can be recognized on-chain". They often come from same batch of backend systems, but semantics aren't the same. Mixing them into one table saves effort short term, long term makes permission surface very hard to shrink.

---

## 8. Builder Perspective: How to Properly Use OwnerCap

### When Creating Building

```move
// When game server creates Gate for Builder, automatically creates and transfers OwnerCap<Gate>
pub fun create_gate_with_owner(...) {
    admin_acl.verify_sponsor(ctx);
    let gate = Gate { ... };
    let owner_cap = create_owner_cap(&admin_acl, &gate, ctx);
    // owner_cap transferred to builder, builder controls this Gate
    transfer::share_object(gate);
    transfer::public_transfer(owner_cap, builder_address);
}
```

### When Builder Modifies Building Configuration

```move
// Builder uses OwnerCap to prove they have right to operate the Gate
pub fun set_gate_config(
    gate: &mut Gate,
    owner_cap: &OwnerCap<Gate>,      // Holding grants permission
    new_config: GateConfig,
    ctx: &TxContext,
) {
    // Verify OwnerCap's corresponding object ID matches gate
    assert!(owner_cap.authorized_object_id == object::id(gate), EOwnerCapMismatch);
    gate.config = new_config;
}
```

---

## 9. Comparison: EVE vs Traditional Contract Permissions

| Scenario | Traditional Contract | EVE Frontier |
|------|---------|-------------|
| Building ownership | Record owner address | `OwnerCap<T>` object |
| Transfer ownership | Update address field | Transfer `OwnerCap<T>` object |
| Lend permissions | No standard mechanism | Receiving pattern + ReturnReceipt |
| Server permissions | Hardcoded address | `AdminACL` (updatable whitelist) |
| Signature verification | None | `ServerAddressRegistry` |

---

## 10. Security Trap: Don't Hold Too Many OwnerCaps

OwnerCap has `has key, store`, meaning it can be stored in any object or table. Builder needs to be careful:

```
❌ Bad design: Store OwnerCap in public shared object
   → Anyone might call using some vulnerability

✅ Correct design:
   - OwnerCap stored in deployer's personal wallet address
   - Or managed through Character's Receiving pattern
   - Important operations use multi-sig wallet with OwnerCap
```

More bluntly, `OwnerCap<T>` should be treated as control plane key, not regular business asset. It shouldn't be casually placed in public shared objects, nor exposed to too many intermediate contracts for "frontend convenience". You can compare it to root key in operations: truly secure systems don't lack root keys, but root keys appear rarely, circulate rarely, and always accompanied by additional process constraints when they appear.

---

## 11. Practical Exercises

1. **Permission Analysis**: List all functions in World contract requiring `admin_acl.verify_sponsor(ctx)`, analyze which players can never directly call
2. **OwnerCap Delegation System**: Design a contract allowing Gate Owner to delegate partial permissions (like modifying toll fees) to another address without transferring OwnerCap itself
3. **Multi-sig OwnerCap Custody**: Implement a 2-of-3 multi-sig account where three maintainers need two to agree to modify building configuration

---

## Chapter Summary

| Component | Layer | Purpose |
|------|-----|------|
| `GovernorCap` | Highest (CCP) | System-level configuration, register servers |
| `AdminACL` | Server layer | Game operation function call authorization |
| `ServerAddressRegistry` | Server layer | Ed25519 signature source verification |
| `OwnerCap<T>` | Building layer | Generic building control credential |
| Receiving pattern | Player layer | OwnerCap safe borrowing mechanism |
| `ReturnOwnerCapReceipt` | Security mechanism | Force OwnerCap return, prevent loss |

---

## Course Complete

Congratulations on completing the **EVE Frontier Builder Complete Course**!

From basic Move 2024 syntax, to on-chain PvP records (KillMail), to signature verification, location proof, energy fuel systems, Extension pattern, turret AI and access control—you've mastered all core knowledge needed to build complex applications on EVE Frontier.

**Next Steps**:
1. Join [EVE Frontier Builders Discord](https://discord.gg/evefrontier)
2. Deploy your first Extension on testnet
3. Find your galaxy in the game, light up a Smart Gate

> *Building in the stars is an extension of civilization.*
