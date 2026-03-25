# Chapter 4: Smart Assembly Development and On-Chain Deployment

> **Objective:** Understand the working principles and APIs of each smart assembly, master the complete workflow from character creation to contract deployment.

---

> Status: Foundation chapter. Main text focuses on deployment workflow and on-chain component operations.

## 4.1 Complete Deployment Workflow

Before your code can take effect in the real game, you need to complete the following complete chain:

```
1. Create on-chain character (Smart Character)
        ↓
2. Deploy network node (Network Node), deposit fuel and go online
        ↓
3. Anchor smart assembly (Anchor Assembly)
        ↓
4. Bring assembly online (Assembly Online)
        ↓
5. Write and publish custom Move extension package
        ↓
6. Register extension to assembly (authorize_extension)
        ↓
7. Players interact with assembly through extension API
```

In local development, steps 1-5 can be completed with one click using `builder-scaffold` initialization scripts.

Many people when first encountering this chapter will mistakenly think "publishing contracts" is the main process. Actually it's not. For EVE Builders, the real main process is:

1. First have on-chain entity
2. Then have operable facilities
3. Then have custom extension logic
4. Finally attach extensions to facilities for player consumption

In other words, the Move package you write doesn't work independently out of thin air. It must be attached to a smart assembly that actually exists, is already online, and is already attributed to the character system.

### The Three Most Easily Confused "IDs" in Deployment

During deployment, at least three types of IDs will appear simultaneously:

- **Package ID**
  Represents your Move package published on-chain
- **Object ID**
  Represents specific objects, such as characters, stargates, turrets, storage units
- **Business ID**
  Represents character, item, facility numbers in the game server

Don't mix these three:

- `Package ID` determines "where your code is"
- `Object ID` determines "where your facilities and assets are"
- Business ID determines "who things in the game world are"

Later you'll frequently switch back and forth between "code address" and "facility object address." If these two concepts aren't separated, debugging will be very painful.

---

## 4.2 Smart Character

Smart Character is your **main identity** on-chain, all assemblies belong to your character.

### Character's On-Chain Structure

```move
public struct Character has key {
    id: UID,                        // Unique object ID
    // Each owned asset corresponds to an OwnerCap
    // owner_caps stored as dynamic fields
}
```

### OwnerCap: Asset Ownership Credential

Whenever you own an assembly (network node/turret/stargate/storage unit), the character will hold the corresponding `OwnerCap<T>` object. All write operations to that assembly require first "borrowing" this OwnerCap from the character:

```typescript
// TypeScript script example: Borrow OwnerCap
const [ownerCap] = tx.moveCall({
    target: `${packageId}::character::borrow_owner_cap`,
    typeArguments: [`${packageId}::assembly::Assembly`],
    arguments: [tx.object(characterId), tx.object(ownerCapId)],
});

// ... use ownerCap to execute operations ...

// Must return after use
tx.moveCall({
    target: `${packageId}::character::return_owner_cap`,
    typeArguments: [`${packageId}::assembly::Assembly`],
    arguments: [tx.object(characterId), ownerCap],
});
```

> 💡 Borrow & Return pattern combined with Hot Potato ensures OwnerCap won't leave the character object.

### Why Not Take OwnerCap Out and Hold Permanently?

Because `OwnerCap` isn't an ordinary key, but a high-privilege credential. Designing it as "borrow then must return" has several direct benefits:

- Permissions won't easily leave the character system
- After a transaction ends, won't leave dangling high-privilege objects
- Assembly ownership still stably belongs to character, rather than scattered to script addresses or temporary objects

From a design perspective, this is equivalent to implementing "temporary privilege escalation" on-chain:

- You first prove you're a legitimate operator of the character
- System temporarily lends you the permission object
- After completing high-privilege operations, you must return the permission

This is more flexible than "hardcoded admin address," and more suitable for game scenarios' delegation, transfer, inheritance, shell-changing operations and other needs.

### What Role Does Character Actually Play in Business?

Don't just understand `Character` as an alias for wallet address. It's more like an on-chain "operating entity":

- Assemblies hang under character name, not directly under wallet address name
- Character can internally manage multiple `OwnerCap` uniformly
- Character can serve as a bridge between on-chain permissions and in-game identity

So in many Builder scenarios, the truly stable entity isn't "which wallet clicked the button," but "which character is operating these facilities."

---

## 4.3 Network Node

### What is a Network Node?

- Energy station anchored at Lagrange Points
- Provides **Energy** for all nearby smart assemblies
- Each assembly when going online needs to "reserve" a certain amount of energy from the network node

### Lifecycle

```
Anchored (Anchored)
    ↓ depositFuel (Deposit fuel)
Fueled (Fueled)
    ↓ online (Go online)
Online (Running)  ←→ offline (Go offline)
```

What's most important here isn't remembering state names, but understanding:

> Whether a facility can work depends not only on "whether the contract is published," but also on whether it's actually powered in the game world.

This is a key difference between EVE Frontier and ordinary dApps. In ordinary dApps, after a contract is successfully published, theoretically anyone can call it; but in EVE, many facilities' availability is also constrained by "world state":

- Is there a network node
- Does the network node have fuel
- Is the facility properly anchored
- Is the facility online

### From Builder's Perspective, What Does Network Node Actually Solve?

It solves the problem of "facilities shouldn't be online unconditionally forever."

If this layer of design didn't exist:

- Stargates could be open forever
- Turrets could work forever
- Storage facilities could keep responding

Then many meanings of operation, maintenance, supply, and occupation in the game would be lost. With network nodes added, facilities become assets that truly need maintenance, rather than "one deployment permanent money printer."

### Initialization Scripts for Local Testing (from builder-scaffold)

```bash
# Execute in builder-scaffold/ts-scripts directory
pnpm setup:character      # Create character
pnpm setup:network-node   # Create and start network node
pnpm setup:assembly       # Create and connect smart assembly
```

---

## 4.4 Smart Storage Unit (SSU) In-Depth Analysis

### Two Types of Inventory

| Inventory Type | Holder | Capacity | Access Method |
|---------|--------|------|--------|
| **Primary Inventory** | Assembly Owner | Large | `OwnerCap<StorageUnit>` |
| **Ephemeral Inventory** | Interacting character | Small | Character's own `OwnerCap` |

Ephemeral inventory is used for non-Owner players to interact with your SSU (e.g., when purchasing items, first transfer items to ephemeral inventory, then player takes them).

### How Do Items Reach the Chain?

```
In-game item → game_item_to_chain_inventory() → On-chain Item object
On-chain Item object → chain_item_to_game_inventory() → In-game item (requires proximity proof)
```

What's truly difficult here isn't "which function to call," but understanding that inventories on both sides aren't simple mirrors.

Many newcomers will default to thinking:

- There's a gun in the game backpack
- After going on-chain it's just "copying a record"

Actually the correct understanding is closer to:

- A certain in-game item is mapped to an on-chain object through a trusted process
- This object then enters the on-chain inventory system
- When it's taken back to the game world, it needs to go through another trusted return path

So the essence of `Storage Unit` isn't a "on-chain cabinet," but an **asset exchange node between on-chain and game world**.

### Why Distinguish Between Primary and Ephemeral Inventory?

Because many interactions aren't "Owner opening the warehouse to get things themselves," but "third-party players having a controlled interaction with your facility."

For example, a vending machine:

1. Player pays tokens
2. Facility first transfers corresponding items to a temporary intermediate area
3. Player then claims from that path

Benefits of doing this:

- Don't have to fully expose main inventory to external parties
- Intermediate states of transactions are easier to audit
- Easier to do rollback and settlement when failures occur

### Extension API Overview

```move
// 1. Register extension (Owner calls)
public fun authorize_extension<Auth: drop>(
    storage_unit: &mut StorageUnit,
    owner_cap: &OwnerCap<StorageUnit>,
)

// 2. Extension deposits item
public fun deposit_item<Auth: drop>(
    storage_unit: &mut StorageUnit,
    character: &Character,
    item: Item,
    _auth: Auth,           // Witness
    ctx: &mut TxContext,
)

// 3. Extension withdraws item
public fun withdraw_item<Auth: drop>(
    storage_unit: &mut StorageUnit,
    character: &Character,
    _auth: Auth,           // Witness
    type_id: u64,
    ctx: &mut TxContext,
): Item
```

---

## 4.5 Smart Gate In-Depth Analysis

### Default vs Custom Behavior

```
No extension: Anyone can jump
    ↓ authorize_extension<MyAuth>()
Has extension: Players must hold JumpPermit to jump
```

### JumpPermit Mechanism

```move
// Jump permit: time-limited on-chain object
public struct JumpPermit has key, store {
    id: UID,
    character_id: ID,
    route_hash: vector<u8>,   // A↔B bidirectional valid
    expires_at_timestamp_ms: u64,
}
```

The key to `JumpPermit` isn't that "it's a ticket," but that it splits a complex judgment into two segments:

1. First decide "are you qualified to get the ticket"
2. Then decide "can you execute the jump with the ticket"

This split is very suitable for game rule extensions, because "qualification judgment" can be very complex:

- Are you a whitelist member
- Have you paid
- Have you completed prerequisite quests
- Are you within the valid time window

But once the ticket is issued, the logic when actually executing the jump can be more standard and unified.

This is also a common thinking for many extension designs:

> Move complex business judgments forward to "credential issuance," converge underlying facility actions to "credential consumption."

**Complete jump process:**
1. Player calls your extension function (e.g., `pay_and_request_permit()`)
2. Extension verifies conditions (check tokens, check whitelist, etc.)
3. Extension calls `gate::issue_jump_permit()` to issue Permit
4. Permit transferred to player
5. Player calls `gate::jump_with_permit()` to jump, Permit consumed

### Extension API

```move
// Register extension
public fun authorize_extension<Auth: drop>(
    gate: &mut Gate,
    owner_cap: &OwnerCap<Gate>,
)

// Issue jump permit (only registered Auth types can call)
public fun issue_jump_permit<Auth: drop>(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    _auth: Auth,
    expires_at_timestamp_ms: u64,
    ctx: &mut TxContext,
)

// Jump using permit (consumes JumpPermit)
public fun jump_with_permit(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    jump_permit: JumpPermit,
    admin_acl: &AdminACL,
    clock: &Clock,
    ctx: &mut TxContext,
)
```

### What is `authorize_extension` Actually Authorizing?

It's authorizing not "a certain address," nor "a certain transaction," but **a certain type identity**.

In other words, what assemblies truly trust is:

- Only calls bringing a certain designated witness type
- Can enter underlying capability entry points

This gives assembly extensions two important properties:

- Assembly kernel doesn't need to know what your business logic looks like
- But it can very clearly know "which extension types are qualified to access"

So Builders' work is often not "modifying official logic," but "packaging their own logic into officially allowed typed extensions to access."

---

## 4.6 Smart Turret In-Depth Analysis

Turret's extension pattern is similar to stargate, authorized through Typed Witness.

### Default Behavior
Turret uses standard attack logic provided by game server.

### Custom Behavior
Builder can register extensions to change turret's **target judgment** logic. For example:
- Allow characters holding specific NFT to pass safely
- Only attack characters not on alliance list
- Turn attack on/off based on time period (open daytime, closed nighttime)

---

## 4.7 Publishing and Registering Extension to Assembly

### Step 1: Publish Your Extension Package

```bash
# In your Move package directory
sui client publish

# Output example:
# Package ID: 0x1234abcd...
# Transaction Digest: HMNaf...
```

Record the **Package ID**, this is your contract address.

After publishing completes, you should immediately record at least three types of information:

- Your `Package ID`
- The assembly object ID you want to bind
- Transaction digest

Because when troubleshooting problems later, almost all chains trace back from these three things:

- Was the contract successfully published
- Is the facility the object you thought it was
- Did this authorization or registration actually succeed on-chain

### Step 2: Authorize Extension to Assembly

Through TypeScript script (or dApp call) to register your extension:

```typescript
import { Transaction } from "@mysten/sui/transactions";

const tx = new Transaction();

// Borrow OwnerCap from character
const [ownerCap] = tx.moveCall({
    target: `${WORLD_PACKAGE}::character::borrow_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::gate::Gate`],
    arguments: [tx.object(CHARACTER_ID), tx.object(OWNER_CAP_ID)],
});

// Authorize extension (tell stargate: allow my_extension::custom_gate::Auth type to call)
tx.moveCall({
    target: `${WORLD_PACKAGE}::gate::authorize_extension`,
    typeArguments: [`${MY_PACKAGE}::custom_gate::Auth`],  // Your Witness type
    arguments: [tx.object(GATE_ID), ownerCap],
});

// Return OwnerCap
tx.moveCall({
    target: `${WORLD_PACKAGE}::character::return_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::gate::Gate`],
    arguments: [tx.object(CHARACTER_ID), ownerCap],
});

await client.signAndExecuteTransaction({ signer: keypair, transaction: tx });
```

Here you need to pay special attention to one thing:

> "Publish successful" doesn't equal "extension already in effect."

You should at least confirm three layers of binding relationships are established:

1. Your package is already on-chain
2. Your assembly object is the correct assembly
3. Assembly has added your witness type to allowed list

### Step 3: Verify Registration Success

```bash
# Query stargate object, confirm extension type has been added to allowed_extensions
sui client object <GATE_ID>
```

---

## 4.8 Using TypeScript to Read On-Chain State

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });

// Read stargate object
const gateObject = await client.getObject({
    id: GATE_ID,
    options: { showContent: true },
});

console.log(gateObject.data?.content);

// GraphQL query all assemblies of specified type
const query = `
  query {
    objects(filter: { type: "${WORLD_PACKAGE}::gate::Gate" }) {
      nodes {
        address
        asMoveObject { contents { json } }
      }
    }
  }
`;
```

### Why Does Deployment Chapter Also Need to Discuss Reading State?

Because in actual development, deployment and reading have never been two separate things. After completing each step, you need to immediately verify:

- Was the object created
- Did state switch to online
- Was extension registered successfully
- Did assembly fields change as expected

So the real rhythm is usually:

```text
Execute one step
  -> Immediately read on-chain state
  -> Confirm object and field changes
  -> Continue to next step
```

If you only know how to "send transactions" but don't know how to "immediately verify state," it's hard to judge whether it's:

- Transaction didn't send
- Sent but wrong object
- Object correct but state didn't change
- State changed but front-end queried wrong place

### From Developer's Perspective, What's the Minimum Closed Loop of This Chapter?

The minimum closed loop isn't "I published a package," but:

1. Have character
2. Have facility
3. Have permission credential
4. Have custom extension package
5. Have successful registration record
6. Have one real verifiable player interaction

Only when all 6 things are completed do you truly finish a Builder facility extension.

---

## 🔖 Chapter Summary

| Deployment Step | Key Operation |
|---------|--------|
| 1. Character | On-chain identity, holds all OwnerCap |
| 2. Network Node | Deposit fuel → Go online → Output energy |
| 3. Assembly | Anchor → Connect node → Go online |
| 4. Extension Package | `sui client publish` |
| 5. Register Extension | `authorize_extension<MyAuth>(gate, owner_cap)` |
| 6. Player Interaction | Call your Entry functions, call world contracts through Witness |

## 📚 Extended Reading

- [Smart Storage Unit Documentation](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/storage-unit/README.md)
- [Smart Gate Documentation](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/gate/README.md)
- [Interfacing with the World](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [builder-scaffold ts-scripts](https://github.com/evefrontier/builder-scaffold/tree/main/ts-scripts)
