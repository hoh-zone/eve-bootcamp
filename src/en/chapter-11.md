# Chapter 11: Deep Dive into Ownership Model

> **Objective:** Deeply understand EVE Frontier's capability object system, master the complete lifecycle of OwnerCap, and learn to design secure delegation authorization and ownership transfer schemes.

---

> Status: Advanced design chapter. Text focuses on OwnerCap, delegation, and ownership lifecycle.

## 11.1 Why Have a Dedicated Ownership Model?

When many newcomers first design a permission system, the intuition is:

- Record an owner address
- Check if the caller is this address for every operation

This approach is convenient in the short term, but once entering EVE Frontier's world of "facilities that can be operated, transferred, delegated, and composed," problems quickly emerge:

- **Not delegable**
  It's hard to safely hand over partial power temporarily to others
- **Not composable**
  Permission rules scattered across functions, system becomes increasingly chaotic
- **Cannot express fine-grained control**
  Hard to express "can operate this turret, but not that gate"
- **Not naturally transferable**
  Once facilities, characters, and operating rights migrate, hardcoded addresses become fragile

EVE Frontier uses Sui's native **Capability object system**. Its core idea isn't "who are you," but:

> What permission object are you holding.

This transforms ownership from "account attribute" to "composable, transferable, verifiable on-chain entity."

---

## 11.2 Permission Hierarchy Structure

```
GovernorCap (deployer holds — highest permission)
    │
    └── AdminACL (shared object — authorized server address list)
            │
            └── OwnerCap<T> (player holds — operation rights for specific objects)
```

### GovernorCap: Game Operation Layer

`GovernorCap` is created during contract deployment, held by CCP Games (game operators). It can:
- Add/remove server authorization addresses to `AdminACL`
- Execute global configuration changes

As a Builder, you don't need to worry about `GovernorCap`.

### AdminACL: Server Authorization Layer

`AdminACL` is a **shared object** containing a list of authorized game server addresses.

Certain operations (like proximity proof, jump verification) require game server as **sponsor** to sign transactions:

```move
// Verify if caller is authorized sponsor
public fun verify_sponsor(admin_acl: &AdminACL, ctx: &TxContext) {
    assert!(
        admin_acl.sponsors.contains(ctx.sponsor().unwrap()),
        EUnauthorizedSponsor
    );
}
```

This means: certain sensitive operations cannot be completed by players alone, must go through game server verification.

### OwnerCap: Player Operation Layer

```move
public struct OwnerCap<phantom T> has key {
    id: UID,
    authorized_object_id: ID,  // Only valid for this specific object
}
```

`phantom T` makes `OwnerCap<Gate>` and `OwnerCap<StorageUnit>` completely different types that cannot be mixed—this is type system level security guarantee.

### Why Separate These Three Permission Layers?

You can think of them as three completely different responsibilities:

- **GovernorCap**
  Solves "world-level rules and global governance"
- **AdminACL**
  Solves "which servers or backend processes are trusted"
- **OwnerCap**
  Solves "which specific business entity can operate which facility"

Separating them has the biggest advantage: the system won't mix "global governance rights" with "single facility operation rights" into one pot.

Otherwise you easily get this bad structure:

- One address is both server authorizer
- And all facility administrator
- And executor of certain temporary business

Once this address has problems, the entire system's permission boundaries collapse.

---

## 11.3 Character as Keychain

All player's `OwnerCap` are stored in the **Character object**, not sent directly to wallet address.

```
Player wallet address
    └── Character (shared object, mapped to wallet address)
            ├── OwnerCap<NetworkNode>  → Network node 0x...a1
            ├── OwnerCap<Gate>         → Gate 0x...b2
            ├── OwnerCap<StorageUnit>  → Storage box 0x...c3
            └── OwnerCap<Gate>         → Gate 0x...d4 (second gate)
```

**Why this design?**
- All asset ownership concentrated in Character, transferring Character equals transferring all assets
- Even if player changes wallet address, Character remains, assets aren't lost
- Cooperates with alliance mechanisms for collective ownership management

One thing to note here:

> Character isn't just a simple wallet mapping layer, but a true permission container.

It organizes "people, characters, facilities, permissions" together across these dimensions:

- Wallet is signing entry
- Character is business entity
- OwnerCap is specific facility permissions
- Facility objects are controlled assets

The benefit of this is when you later do:

- Account migration
- Multi-sig control
- Alliance trusteeship
- Character transfer

You don't need to rewrite an entire permission system, but make changes around the `Character` layer.

---

## 11.4 Complete Borrow-Use-Return Pattern

Executing any operation requiring OwnerCap must follow the "borrow → use → return" three-step atomic transaction:

```move
// Character module provided interface
public fun borrow_owner_cap<T: key>(
    character: &mut Character,
    owner_cap_ticket: Receiving<OwnerCap<T>>,  // Use Receiving pattern
    ctx: &TxContext,
): (OwnerCap<T>, ReturnOwnerCapReceipt)        // Return Cap + hot potato receipt

public fun return_owner_cap<T: key>(
    character: &Character,
    owner_cap: OwnerCap<T>,
    receipt: ReturnOwnerCapReceipt,             // Must consume receipt
)
```

`ReturnOwnerCapReceipt` is a hot potato (no Abilities), ensuring OwnerCap **must be returned**, cannot be lost outside transaction.

### What Does This Pattern Really Prevent?

It's not simply for "elegant writing," but prevents several very real risks:

- High-privilege objects intercepted mid-transaction
- Scripts forget to return permissions, leaving dangling state
- Extension logic brings permission objects into wrong paths
- In multi-step operations, permission boundaries become no longer auditable

Forcing `borrow -> use -> return` into the same transaction is like adding a hard constraint to high-privilege operations:

> You can temporarily use it to do things, but cannot take it away.

### Why Pair with Hot Potato Receipt?

Because relying only on "developer consciously calling return" isn't enough.

As long as the type system allows you to skip the return step, someone will eventually:

- Forget in scripts
- Delete during refactoring
- Directly `return` in error branches

After adding receipt, compiler and type system will force you to complete the process together.

### Complete TypeScript Call Example

```typescript
import { Transaction } from "@mysten/sui/transactions";

const WORLD_PKG = "0x...";

async function bringGateOnline(
  tx: Transaction,
  characterId: string,
  ownerCapId: string,
  gateId: string,
  networkNodeId: string,
) {
  // ① Borrow OwnerCap
  const [ownerCap, receipt] = tx.moveCall({
    target: `${WORLD_PKG}::character::borrow_owner_cap`,
    typeArguments: [`${WORLD_PKG}::gate::Gate`],
    arguments: [
      tx.object(characterId),
      tx.receivingRef({ objectId: ownerCapId, version: "...", digest: "..." }),
    ],
  });

  // ② Use OwnerCap: bring gate online
  tx.moveCall({
    target: `${WORLD_PKG}::gate::online`,
    arguments: [
      tx.object(gateId),
      tx.object(networkNodeId),
      tx.object(ENERGY_CONFIG_ID),
      ownerCap,
    ],
  });

  // ③ Return OwnerCap (receipt consumed, hot potato makes this step unskippable)
  tx.moveCall({
    target: `${WORLD_PKG}::character::return_owner_cap`,
    arguments: [tx.object(characterId), ownerCap, receipt],
  });
}
```

---

## 11.5 Ownership Transfer Scenarios

### Scenario 1: Transfer Control of Single Component

If you want to hand over control of one gate to an ally (but keep your Character and other facilities), you can transfer only the corresponding `OwnerCap`:

```typescript
// Extract OwnerCap from your Character, send to ally
const tx = new Transaction();

// Extract OwnerCap (note this isn't borrowing, but transferring)
// Specific API subject to world contract, this is just conceptual
tx.moveCall({
  target: `${WORLD_PKG}::character::transfer_owner_cap`,
  typeArguments: [`${WORLD_PKG}::gate::Gate`],
  arguments: [
    tx.object(myCharacterId),
    tx.object(ownerCapId),
    tx.pure.address(allyAddress),  // Ally's Character address
  ],
});
```

### Scenario 2: Transfer Complete Character (All Assets Packaged Transfer)

Transferring entire Character object allows corresponding wallet address to control all bound assets. Suitable for alliance overall asset handover, account trading scenarios.

Need to distinguish three actions that sound similar but are completely different:

- **Transfer single OwnerCap**
  Only hand over control of one facility
- **Transfer Character**
  Hand over entire chain of permissions and assets
- **Delegate operation**
  Don't transfer ownership, only give limited operation capability

If these three aren't separated, your product design will quickly become messy.

For example, alliance treasury scenario:

- Property rights may belong to alliance entity
- Daily operation rights may belong to on-duty members
- Emergency shutdown rights may belong only to core administrators

This requires you can't just use "one owner" to express all relationships.

### Scenario 3: Delegate Operation (Without Transferring Ownership)

By writing extension contracts, you can allow specific addresses to operate your facilities in **limited scope** without transferring OwnerCap:

```move
// In your extension contract, maintain an operator whitelist
public struct OperatorRegistry has key {
    id: UID,
    operators: Table<address, bool>,
}

public fun delegated_action(
    registry: &OperatorRegistry,
    ctx: &TxContext,
) {
    // Verify caller is in operator list
    assert!(registry.operators.contains(ctx.sender()), ENotOperator);
    // ... execute operation
}
```

### Easiest Pitfall in Delegation

Many people's first delegation treats whitelist as "weakened ownership." This isn't enough.

A secure delegation design needs to answer at least:

- What actions can delegatee do, what can't they do?
- Does delegation have time limits?
- Can delegation be revoked?
- Is delegation only valid for one facility?
- Can delegatee re-delegate?

If these boundaries aren't written clearly, delegation becomes "invisible gifting rights" from "flexible authorization."

---

## 11.6 OwnerCap Security Boundaries

### Each OwnerCap Only Valid for One Object

```move
public fun verify_owner_cap<T: key>(
    obj: &T,
    owner_cap: &OwnerCap<T>,
) {
    // authorized_object_id ensures this OwnerCap can only be used for corresponding object
    assert!(
        owner_cap.authorized_object_id == object::id(obj),
        EOwnerCapMismatch
    );
}
```

This means if you have two gates, you have two `OwnerCap<Gate>`, they cannot be used interchangeably.

### Why is `authorized_object_id` So Critical?

Because `phantom T` only solves "object categories cannot mix," but hasn't solved "same category different instances cannot mix."

For example:

- `OwnerCap<Gate>` can only be used for Gate, no problem
- But without `authorized_object_id`
  Your one Gate permission might incorrectly operate another Gate

So complete security boundaries are actually two layers:

1. **Type boundary**
   `Gate` and `StorageUnit` cannot mix
2. **Instance boundary**
   This Gate and that Gate also cannot mix

### Losing OwnerCap Means Losing Control

If Character containing OwnerCap is transferred, you lose control of all facilities. Please **safeguard your Character object's ownership private key**.

From operational perspective, more accurately, you need to protect not "some button permission," but the entire business control chain:

- Wallet signing rights
- Character control rights
- OwnerCap collection inside Character
- Critical delegation configurations and multi-sig settings

Once this chain breaks, recovery cost is very high.

---

## 11.7 Advanced: Multi-sig & Alliance Co-ownership

Through Sui's multisig functionality, an alliance can jointly control critical facilities:

```bash
# Create 2/3 multi-sig address (requires 2 out of 3 members to agree to operate)
sui keytool multi-sig-address \
  --pks <pk1> <pk2> <pk3> \
  --weights 1 1 1 \
  --threshold 2
```

Set Character's control address to multi-sig address, alliance critical assets require multiple signatures to operate.

### What's Multi-sig Suitable For, What's Not?

Multi-sig is very suitable for:

- Alliance treasury
- Ultra-high value infrastructure
- Critical parameter adjustments
- Upgrades & emergency shutdowns

Multi-sig not necessarily suitable for:

- High-frequency daily operations
- Player interactions requiring second-level response
- Large numbers of small repetitive management actions

So realistic practice usually isn't "put everything on multi-sig," but layer it:

- Core control rights on multi-sig
- Daily operational permissions released to execution layer through limited delegation

This is closer to real organizational structure.

---

## Chapter Summary

| Concept | Key Points |
|------|--------|
| Permission hierarchy | GovernorCap > AdminACL > OwnerCap<T> |
| Character keychain | All OwnerCap centrally stored, transferring Character = transferring all assets |
| Borrow-Use-Return | Three-step atomic operation, ReturnReceipt (hot potato) ensures must return |
| Type safety | `OwnerCap<Gate>` ≠ `OwnerCap<StorageUnit>`, cannot mix |
| Delegate operations | Through extension contract + whitelist implementation, no need to transfer OwnerCap |
| Multi-sig | Sui native multi-sig address suitable for alliance co-ownership scenarios |

## Further Reading

- [Ownership Model Documentation](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/ownership-model.md)
- [Smart Character Documentation](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/smart-character.md)
- [character.move Source Code](https://github.com/evefrontier/world-contracts/blob/main/contracts/world/sources/character/character.move)
- [Sui Multi-sig Documentation](https://docs.sui.io/guides/developer/cryptography/multisig)
- [Receiving Object Pattern](https://docs.sui.io/guides/developer/objects/transfers/transfer-to-object)
