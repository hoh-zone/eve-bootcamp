# Chapter 18: Multi-Tenant Architecture and Game Server Integration

> **Goal:** Understand EVE Frontier's multi-tenant world contract design, master how to build platform-level contracts serving multiple alliances, and how to bidirectionally integrate with game servers.

---

> Status: Architecture chapter. Main focus on multi-tenant design and Registry patterns.

## 18.1 What Are Multi-Tenant Contracts?

**Single-tenant**: One contract serves only one Owner (your alliance).

**Multi-tenant**: One contract after deployment can simultaneously serve multiple unrelated Owners (multiple alliances), with isolated data.

```
Single-tenant example (Example 1-5 pattern):
  Contract → Dedicated TollGate (only your stargate)

Multi-tenant example:
  Contract → Register Alliance A's stargate toll configuration
        → Register Alliance B's stargate toll configuration
        → Register Alliance C's storage box market configuration
        → (Each alliance isolated, data independent)
```

**Use Cases**: Building a "SaaS"-level tool that can be used by multiple alliances. Examples: universal auction platform, royalty market infrastructure, quest system framework.

Multi-tenancy is most easily misunderstood as "cramming many users into one contract." What it really needs to solve is:

> How to let many mutually untrusting operators share the same protocol capabilities, but without cross-contamination, unauthorized access, or data pollution.

So the core of multi-tenant design isn't "saving deployment times," but three things:

- **Isolation**
  Tenant A cannot touch Tenant B's state
- **Reuse**
  Same logic doesn't need to be repackaged for each alliance
- **Operability**
  Platform can continue maintenance, upgrades, and billing

---

## 18.2 Multi-Tenant Contract Design Pattern

```move
module platform::multi_toll;

use sui::table::{Self, Table};
use sui::object::{Self, ID};

/// Platform registry (shared object, used by all tenants)
public struct TollPlatform has key {
    id: UID,
    registrations: Table<ID, TollConfig>,  // gate_id → toll configuration
}

/// Each tenant's (stargate's) independent configuration
public struct TollConfig has store {
    owner: address,          // Owner of this configuration (stargate owner)
    toll_amount: u64,
    fee_recipient: address,
    total_collected: u64,
}

/// Tenant registration (any Builder can register their stargate)
public fun register_gate(
    platform: &mut TollPlatform,
    gate: &Gate,
    owner_cap: &OwnerCap<Gate>,          // Prove you're this stargate's Owner
    toll_amount: u64,
    fee_recipient: address,
    ctx: &TxContext,
) {
    // Verify OwnerCap and Gate correspondence
    assert!(owner_cap.authorized_object_id == object::id(gate), ECapMismatch);

    let gate_id = object::id(gate);
    assert!(!table::contains(&platform.registrations, gate_id), EAlreadyRegistered);

    table::add(&mut platform.registrations, gate_id, TollConfig {
        owner: ctx.sender(),
        toll_amount,
        fee_recipient,
        total_collected: 0,
    });
}

/// Adjust tenant configuration (only can modify your own configuration)
public fun update_toll(
    platform: &mut TollPlatform,
    gate: &Gate,
    owner_cap: &OwnerCap<Gate>,
    new_toll_amount: u64,
    ctx: &TxContext,
) {
    assert!(owner_cap.authorized_object_id == object::id(gate), ECapMismatch);

    let config = table::borrow_mut(&mut platform.registrations, object::id(gate));
    assert!(config.owner == ctx.sender(), ENotConfigOwner);

    config.toll_amount = new_toll_amount;
}

/// Multi-tenant jump (toll logic reused, but configurations independently isolated)
public fun multi_tenant_jump(
    platform: &mut TollPlatform,
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Read this stargate's dedicated toll configuration
    let gate_id = object::id(source_gate);
    assert!(table::contains(&platform.registrations, gate_id), EGateNotRegistered);

    let config = table::borrow_mut(&mut platform.registrations, gate_id);
    assert!(coin::value(&payment) >= config.toll_amount, EInsufficientPayment);

    // Transfer to respective fee_recipient
    let toll = payment.split(config.toll_amount, ctx);
    transfer::public_transfer(toll, config.fee_recipient);
    config.total_collected = config.total_collected + config.toll_amount;

    // Return change
    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    // Issue jump permit
    gate::issue_jump_permit(
        source_gate, dest_gate, character, MultiTollAuth {}, clock.timestamp_ms() + 15 * 60 * 1000, ctx,
    );
}

public struct MultiTollAuth has drop {}
const ECapMismatch: u64 = 0;
const EAlreadyRegistered: u64 = 1;
const ENotConfigOwner: u64 = 2;
const EGateNotRegistered: u64 = 3;
const EInsufficientPayment: u64 = 4;
```

### What Multi-Tenant Design Really Needs to Decide First Is "What Is the Tenant Key"

In this example, `gate_id` serves as the tenant boundary. In reality, common tenant keys include:

- A certain `assembly_id`
- A certain `character_id`
- An alliance object ID
- A normalized business primary key

This choice is very critical, because it determines:

- How data is isolated
- How permissions are validated
- How frontend and indexing layers retrieve

If the tenant key is chosen unstably, you'll frequently encounter dirty boundary problems like "is this one tenant or two."

### Three Most Common Types of Accidents in Multi-Tenant Contracts

#### 1. Incomplete Isolation

Looks like multi-tenant, but certain paths still use global shared parameters, causing different alliances to affect each other.

#### 2. Platform Parameters and Tenant Parameters Mixed Together

Result is:

- Some configurations should be globally unified
- But were privately changed by a tenant

Or vice versa:

- Fee rates that should be independent per tenant
- Made into global single values

#### 3. Query Model Didn't Keep Up

On-chain wrote multi-tenant structure, but frontend and indexing layers still only know how to read by "single object" thinking, ultimately the platform is unusable.

---

## 18.3 Game Server Integration Patterns

### Pattern One: Server as Event Listener

```typescript
// game-server/event-listener.ts
// Game server listens to on-chain events, updates game state

import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: process.env.SUI_RPC! });

// Listen to player achievements, trigger in-game rewards
await client.subscribeEvent({
  filter: { Package: MY_PACKAGE },
  onMessage: async (event) => {
    if (event.type.includes("AchievementUnlocked")) {
      const { player, achievement_type } = event.parsedJson as any;

      // Game server handles: grant in-game items to player
      await gameServerAPI.grantItemToPlayer(player, achievement_type);
    }

    if (event.type.includes("GateJumped")) {
      const { character_id, destination_gate_id } = event.parsedJson as any;

      // Game server handles: teleport player to destination system
      await gameServerAPI.teleportCharacter(character_id, destination_gate_id);
    }
  },
});
```

### Pattern Two: Server as Data Provider

```typescript
// game-server/api.ts
// Game server provides off-chain data, dApp calls

import express from "express";

const app = express();

// Provide star system name (decrypt location hash)
app.get("/api/location/:hash", async (req, res) => {
  const { hash } = req.params;
  const geoInfo = await locationDB.getByHash(hash);
  res.json(geoInfo);
});

// Verify proximity (for Sponsor service to call)
app.post("/api/proximity/verify", async (req, res) => {
  const { player_id, assembly_id, max_distance_km } = req.body;

  const playerPos = await getPlayerPosition(player_id);
  const assemblyPos = await getAssemblyPosition(assembly_id);
  const distance = calculateDistance(playerPos, assemblyPos);

  res.json({
    is_near: distance <= max_distance_km,
    distance_km: distance,
  });
});

// Get player real-time game status
app.get("/api/character/:id/status", async (req, res) => {
  const status = await gameServerAPI.getCharacterStatus(req.params.id);
  res.json({
    online: status.online,
    system: status.current_system,
    ship: status.current_ship,
    fleet: status.fleet_id,
  });
});
```

### Pattern Three: Bidirectional State Synchronization

```
On-chain events ──────────────► Game server
(NFT minting, quest completion)     (Update game world state)

Game server ──────────────► On-chain transactions
(Physics verification, sponsor signatures)      (Record results, grant rewards)
```

### Don't Mix These Three Patterns Into One Pot

While all called "server integration," their responsibilities are completely different:

- **Event Listener**
  Consumer-oriented, syncs on-chain results back to game world
- **Data Provider**
  Query-oriented, provides off-chain interpretation layer for frontend and backend
- **Bidirectional Sync**
  Collaboration-oriented, lets on-chain and game server mutually drive state changes

If you don't layer them, you'll easily end up with:

- One service managing listening, sponsoring, and all queries
- When problems occur, completely don't know which chain broke

### Most Critical Between Game Server and On-Chain Isn't "Connectivity," But "Calibration Consistency"

For example:

- Are on-chain recognized `assembly_id` and game server recognized facility IDs the same thing
- Do location hashes and off-chain map coordinates have one-to-one correspondence
- Are character IDs in events and character primary keys in game database stably mapped

Once these mappings drift, system surface still works, but business slowly becomes distorted.

---

## 18.4 ObjectRegistry: Global Query Table

When your contract has multiple shared objects, need a registry for other contracts and dApps to find them:

```move
module platform::registry;

/// Global registry (like DNS)
public struct ObjectRegistry has key {
    id: UID,
    entries: Table<String, ID>,  // name → ObjectID
}

/// Register a named object
public fun register(
    registry: &mut ObjectRegistry,
    name: vector<u8>,
    object_id: ID,
    _admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    table::add(
        &mut registry.entries,
        std::string::utf8(name),
        object_id,
    );
}

/// Query
public fun resolve(registry: &ObjectRegistry, name: String): ID {
    *table::borrow(&registry.entries, name)
}
```

```typescript
// Query Treasury ID through registry
const registry = await getObjectWithJson(REGISTRY_ID);
const treasuryId = registry?.entries?.["alliance_treasury"];
```

Registry's value isn't just "conveniently lookup an ID," but unifying "scattered object discovery logic."

This will directly improve three things:

- Frontend doesn't need to hardcode a bunch of object addresses
- Other contracts know where to find key objects
- After upgrades or migrations, can do smooth transitions through registry

### But Registry Also Has Boundaries

Don't treat it as a universal database. It's best suited for:

- Name resolution
- Core object entry discovery
- Small amount of stable mappings

Not suited for:

- High-frequency changing large lists
- Heavy business statistics
- Large-scale time series data

---

## 🔖 Chapter Summary

| Knowledge Point | Core Takeaway |
|--------|--------|
| Multi-Tenant Contracts | Table isolates configuration by gate_id, any Builder can register |
| Server Roles | Event listening + data providing + proximity verification |
| Bidirectional Sync | On-chain events → Game state; Game verification → On-chain record |
| ObjectRegistry | Global name table, convenient for other contracts and dApps to find objects |

## 📚 Further Reading

- [Chapter 8: Sponsored Transactions](./chapter-08.md)
- [EVE World Explainer](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/eve-frontier-world-explainer.md)
