# Chapter 12: Advanced Move — Generics, Dynamic Fields, and Event Systems

> **Goal:** Master generics programming in Move, dynamic field storage, Table/VecMap data structures, and event systems, enabling you to independently design complex on-chain data models.

---

> Status: Advanced design chapter. Main content focuses on generics, dynamic fields, events, and Table/VecMap.

## 12.1 Generics

Generics allow your code to work with multiple types while maintaining type safety. This is widely used in EVE Frontier's OwnerCap.

### Basic Generic Syntax

```move
// T is a type parameter, similar to <T> in other languages
public struct Box<T: store> has key, store {
    id: UID,
    value: T,
}

// Generic function
public fun wrap<T: store>(value: T, ctx: &mut TxContext): Box<T> {
    Box { id: object::new(ctx), value }
}

public fun unwrap<T: store>(box: Box<T>): T {
    let Box { id, value } = box;
    id.delete();
    value
}
```

### Phantom Type Parameters

`phantom T` doesn't actually hold a value of type T, only used for type distinction:

```move
// T is not actually used, but creates type distinction
public struct OwnerCap<phantom T> has key {
    id: UID,
    authorized_object_id: ID,
}

// These two are completely different types, the system won't confuse them
let gate_cap: OwnerCap<Gate> = ...;
let ssu_cap: OwnerCap<StorageUnit> = ...;
```

### Generics with Constraints

```move
// T must have both key and store abilities
public fun transfer_to_object<T: key + store, Container: key>(
    container: &mut Container,
    value: T,
) { ... }

// T must have copy and drop (temporary value, not an asset)
public fun log_value<T: copy + drop>(value: T) { ... }
```

### Why Are Generics Particularly Important in Move?

Because many safety designs in Move don't rely on "passing a string to identify the type," but instead put the type itself into the interface.

The advantages of this approach:

- Type mismatches can be detected at compile time
- Permissions and object categories can be tightly bound
- You don't need to manually write fragile type checks at runtime

### What Does `phantom` Really Solve?

When you first see `phantom T`, it's easy to think it's just a syntax trick. Actually, it solves:

> "I don't need to actually store a T, but I need this type identity to participate in security boundaries."

This is especially common in permission objects, because what permissions really care about is often not the data itself, but "who this permission card is for."

### When Should You Use Generics, and When Shouldn't You?

Scenarios suitable for generics:

- Permission objects
- Generic containers
- Same logic serving multiple object types
- The type itself carries security meaning

Scenarios not suitable for over-genericization:

- Business semantics are already very specific
- Only one or two fixed object types
- Generics would significantly increase interface reading cost

In other words, generics aren't for "looking advanced," but for clearly expressing "this logic is naturally generic."

---

## 12.2 Dynamic Fields

Sui has a powerful feature: **Dynamic Fields**, which allow you to add arbitrary key-value pairs to objects at runtime, without needing to define all fields at compile time.

### Why Do We Need Dynamic Fields?

Suppose your storage box needs to support any type of item, and the item types are unknown at compile time:

```move
// ❌ Inflexible way: fixed fields
public struct Inventory has key {
    id: UID,
    fuel: Option<u64>,
    ore: Option<u64>,
    // Adding new item types requires modifying the contract...
}

// ✅ Flexible way: dynamic fields
public struct Inventory has key {
    id: UID,
    // No predefined fields, use dynamic fields for storage
}
```

### Dynamic Fields API

```move
use sui::dynamic_field as df;
use sui::dynamic_object_field as dof;

// Add dynamic field (value is not an object type)
df::add(&mut inventory.id, b"fuel_amount", 1000u64);

// Read dynamic field
let fuel: &u64 = df::borrow(&inventory.id, b"fuel_amount");
let fuel_mut: &mut u64 = df::borrow_mut(&mut inventory.id, b"fuel_amount");

// Check if exists
let exists = df::exists_(&inventory.id, b"fuel_amount");

// Remove dynamic field
let old_value: u64 = df::remove(&mut inventory.id, b"fuel_amount");

// Dynamic object field (value itself is an object with independent ObjectID)
dof::add(&mut storage.id, item_type_id, item_object);
let item = dof::borrow<u64, Item>(&storage.id, item_type_id);
let item = dof::remove<u64, Item>(&mut storage.id, item_type_id);
```

### Real Application in EVE Frontier

The **Ephemeral Inventory** in storage units is implemented using dynamic fields:

```move
// Create ephemeral inventory for a specific character (using character OwnerCap ID as key)
df::add(
    &mut storage_unit.id,
    owner_cap_id,      // Use character's OwnerCap ID as key
    EphemeralInventory::new(ctx),
);

// Character accesses their own ephemeral inventory
let my_inventory = df::borrow_mut<ID, EphemeralInventory>(
    &mut storage_unit.id,
    my_owner_cap_id,
);
```

### The Real Value of Dynamic Fields

Its greatest value isn't "avoiding struct definition changes," but:

> Allowing objects to grow new sub-states at runtime, without having to hardcode all slots in advance.

This is especially critical for game-type systems, because many states are naturally open sets:

- A warehouse might contain many types of items
- A facility might serve many characters
- A market might have continuously new listings

If you write them all as fixed fields, your structure will quickly lose control.

### When to Use `dynamic_field` vs `dynamic_object_field`?

A very practical decision criterion:

- **Value is just a simple value or ordinary struct**
  Use `dynamic_field`
- **Value itself should also be an independent object**
  Use `dynamic_object_field`

The latter is more suitable for:

- Needs independent object ID
- Needs to be transferred, referenced, or deleted separately
- May be operated on separately by other logic later

### Most Common Mistakes with Dynamic Fields

#### 1. Treating it as a "universal database"

Dynamic fields are very flexible, but not infinitely free. They bring:

- Higher read/write costs
- More complex index paths
- Higher debugging difficulty

#### 2. Key design is too casual

If key design is unstable, you'll encounter later:

- Can't find original data for the same business entity
- Inconsistent mapping rules between off-chain and on-chain
- Data seems to be written successfully, but can't be read back

#### 3. Putting frequently traversed large collections directly in

Dynamic fields are suitable for locating by key, not naturally suited for high-frequency full traversal. As long as your business often needs to "scan all entries," you need to start considering index and pagination strategies.

---

## 12.3 Table and VecMap: On-chain Collection Types

### Table: Key-Value Mapping

```move
use sui::table::{Self, Table};

public struct Registry has key {
    id: UID,
    members: Table<address, MemberInfo>,
}

// Add
table::add(&mut registry.members, member_addr, MemberInfo { ... });

// Query
let info = table::borrow(&registry.members, member_addr);
let info_mut = table::borrow_mut(&mut registry.members, member_addr);

// Existence check
let is_member = table::contains(&registry.members, member_addr);

// Remove
let old_info = table::remove(&mut registry.members, member_addr);

// Length
let count = table::length(&registry.members);
```

> ⚠️ **Note**: Each entry in a Table is an independent dynamic field on-chain, and each access has a separate cost. A transaction can access at most **1024 dynamic fields**.

### VecMap: Small-scale Ordered Mapping

```move
use sui::vec_map::{Self, VecMap};

// VecMap is stored in object fields (not dynamic fields), suitable for small datasets
public struct Config has key {
    id: UID,
    toll_settings: VecMap<u64, u64>,  // zone_id -> toll_amount
}

// Operations
vec_map::insert(&mut config.toll_settings, zone_id, amount);
let amount = vec_map::get(&config.toll_settings, &zone_id);
vec_map::remove(&mut config.toll_settings, &zone_id);
```

### Selection Recommendations

| Scenario | Recommended Type |
|------|---------|
| Large-scale, dynamically growing collections | `Table` |
| Less than 100 entries, needs traversal | `VecMap` or `vector` |
| Values are objects (with independent ObjectID) | `dynamic_object_field` |
| Values are simple values (u64, bool, etc.) | `dynamic_field` |

### What Essentially Is `Table`?

It's essentially not a "hash table in memory," but an on-chain collection abstraction built on dynamic fields.

So when using `Table`, you should always remember three things:

- Each read/write has real on-chain cost
- The more entries, the more strategy needed for operations and troubleshooting
- It's more like an "extensible index structure," not a local container to use casually

### Why Is `VecMap` Suitable for Small-scale Configuration?

Because it stores data directly in object fields, usually more suitable for:

- Small number of configuration items
- Needs full reading
- Needs traversal by insertion order or small scale

Typical examples include:

- Fee tier tables
- Small-scale whitelists
- Mode switch configurations

### What to Really Ask When Choosing Types

Don't just ask "can this container store it," but ask:

1. How large will this collection grow?
2. Am I doing exact key lookups, or frequently traversing all?
3. Are the values independent objects?
4. Will I need to do pagination and indexing on it in the future?

Once these four questions are answered, container selection usually won't be too off.

---

## 12.4 Event Systems

Events are the bridge between on-chain contracts and off-chain applications. Events are not stored in on-chain state, but are attached to transaction records and can be captured by indexers.

### Defining and Emitting Events

```move
use sui::event;

// Event struct: only needs copy + drop
public struct GateJumped has copy, drop {
    gate_id: ID,
    character_id: ID,
    destination_gate_id: ID,
    timestamp_ms: u64,
    toll_paid: u64,
}

public struct ItemSold has copy, drop {
    storage_unit_id: ID,
    seller: address,
    buyer: address,
    item_type_id: u64,
    price: u64,
}

// Emit event in function
public fun process_purchase(
    storage_unit: &mut StorageUnit,
    buyer: &Character,
    payment: Coin<SUI>,
    item_type_id: u64,
    ctx: &mut TxContext,
): Item {
    let price = coin::value(&payment);
    // ... process purchase logic ...

    // Emit event (no gas consumption difference, emission is free index recording)
    event::emit(ItemSold {
        storage_unit_id: object::id(storage_unit),
        seller: storage_unit.owner_address,
        buyer: ctx.sender(),
        item_type_id,
        price,
    });

    // ... return item ...
}
```

The most easily misunderstood aspect of events:

> It's a record of "what happened in the transaction," not the source of truth for "what the current system state is."

This sentence is very important. Because many frontend or index design problems start from treating events as state.

### What Are Events Suitable for Expressing?

Most suitable for expressing:

- Something just happened
- Who triggered it
- What were the key parameters at the time
- What should off-chain systems do based on this subscription or notification

For example:

- Transaction records
- Jump records
- Claim triggers
- Authorization changes

### What Should Events Not Independently Bear?

Not suitable for independently bearing:

- Current inventory truth
- Whether the current object is online
- Complete business state of a current facility

Because events are naturally timelines, not current state snapshots.

### Listening to Events in TypeScript

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });

// Query historical events
const events = await client.queryEvents({
  query: {
    MoveEventType: `${MY_PACKAGE}::toll_gate_ext::GateJumped`,
  },
  limit: 50,
});

events.data.forEach(event => {
  const fields = event.parsedJson as {
    gate_id: string;
    character_id: string;
    toll_paid: string;
  };
  console.log(`Jump: ${fields.character_id} paid ${fields.toll_paid}`);
});

// Real-time subscription (WebSocket)
const unsubscribe = await client.subscribeEvent({
  filter: { Package: MY_PACKAGE },
  onMessage: (event) => {
    console.log("New event:", event.type, event.parsedJson);
  },
});

// Stop subscription
setTimeout(() => unsubscribe(), 60_000);
```

### When Designing Events, How to Think About Fields?

A good event should at least answer:

1. Who did it
2. On which object
3. What did they do
4. What are the key business parameters
5. How should off-chain systems locate related objects based on this

If there are too few fields, off-chain is hard to consume; too many fields will bloat the event and blur semantics.

### A Very Practical Combination Principle

Mature on-chain systems usually adopt this combination:

- **Objects**
  Store current state
- **Events**
  Store historical actions
- **Index layer**
  Reorganize objects and events into data views that are easy for frontends to use

This is also why when you read GraphQL, indexer, and dApp chapters later, you'll always see "object queries + event queries" appearing together.

### Driving dApp Real-time Updates with Events

```tsx
// src/hooks/useGateEvents.ts
import { useEffect, useState } from 'react'
import { SuiClient } from '@mysten/sui/client'

interface JumpEvent {
  gate_id: string
  character_id: string
  toll_paid: string
  timestamp_ms: string
}

export function useGateEvents(packageId: string) {
  const [events, setEvents] = useState<JumpEvent[]>([])

  useEffect(() => {
    const client = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })

    const subscribe = async () => {
      await client.subscribeEvent({
        filter: { MoveEventType: `${packageId}::toll_gate_ext::GateJumped` },
        onMessage: (event) => {
          setEvents(prev => [event.parsedJson as JumpEvent, ...prev.slice(0, 49)])
        },
      })
    }

    subscribe()
  }, [packageId])

  return events
}
```

---

## 12.5 Dynamic Fields vs Events Use Cases

| Need | Solution |
|------|------|
| Persistent collection data storage | Dynamic fields / Table |
| Historical record queries (no need to keep in contract) | Events |
| Real-time notification to off-chain systems | Events |
| State checks within contracts | Dynamic fields |
| Analysis and statistical data (transaction volume, active users) | Events + off-chain indexing |

---

## 12.6 Practice: Designing a Trackable Auction State Machine

Integrating the knowledge from this chapter, design a complex auction state object:

```move
module my_auction::auction;

use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::event;
use sui::clock::Clock;

/// Auction status enumeration (represented by u8)
const STATUS_OPEN: u8 = 0;
const STATUS_ENDED: u8 = 1;
const STATUS_CANCELLED: u8 = 2;

/// Auction object
public struct Auction<phantom ItemType: key + store> has key {
    id: UID,
    status: u8,
    min_bid: u64,
    current_bid: u64,
    current_winner: Option<address>,
    end_time_ms: u64,
    bid_history_count: u64,
    // Bid history stored with dynamic fields (avoid large objects)
}

/// Bid event
public struct BidPlaced has copy, drop {
    auction_id: ID,
    bidder: address,
    amount: u64,
    timestamp_ms: u64,
}

/// Bid function
public fun place_bid<T: key + store>(
    auction: &mut Auction<T>,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let bid_amount = coin::value(&payment);
    let now = clock.timestamp_ms();

    // Verification
    assert!(auction.status == STATUS_OPEN, EAuctionNotOpen);
    assert!(now < auction.end_time_ms, EAuctionEnded);
    assert!(bid_amount > auction.current_bid, EBidTooLow);

    // Refund previous bidder's bid (simplified version)
    // ...

    // Update auction state
    auction.current_bid = bid_amount;
    auction.current_winner = option::some(ctx.sender());

    // Record bid history (using dynamic fields)
    let bid_key = auction.bid_history_count;
    auction.bid_history_count = bid_key + 1;
    df::add(&mut auction.id, bid_key, BidRecord {
        bidder: ctx.sender(),
        amount: bid_amount,
        timestamp_ms: now,
    });

    // Emit event (for dApp real-time display)
    event::emit(BidPlaced {
        auction_id: object::id(auction),
        bidder: ctx.sender(),
        amount: bid_amount,
        timestamp_ms: now,
    });
}
```

---

## 🔖 Chapter Summary

| Knowledge Point | Core Points |
|--------|--------|
| Generics | `<T>` type parameter + `phantom T` type distinction |
| Dynamic Fields | Add fields at runtime, `df::add/borrow/remove`, max 1024/tx |
| Table | Large-scale on-chain KV storage, `table::add/borrow/contains` |
| VecMap | Small ordered KV, stored in fields, suitable for config tables |
| Events | `has copy + drop`, `event::emit()`, can be subscribed off-chain |
| Events vs Dynamic Fields | Temporary notifications use events; persistent state uses dynamic fields |

## 📚 Further Reading

- [Sui Dynamic Fields Documentation](https://docs.sui.io/concepts/dynamic-fields)
- [Move Book: Generics](https://move-book.com/reference/generics.html)
- [Sui Events Documentation](https://docs.sui.io/guides/developer/accessing-data/using-events)
- [inventory.move](https://github.com/evefrontier/world-contracts/blob/main/contracts/world/sources/primitives/inventory.move)
