# Chapter 28: Location Proof Protocol Deep Dive

> **Learning Objective**: Master the core design of the `world::location` module — location hashing, BCS deserialization, LocationProof verification, and complete implementation of requiring players to "be present" in Builder extensions.

---

> Status: Teaching example. Location proof message organization and signature flow will vary by business. This chapter focuses on protocol structure and verification boundaries.

## Minimal Call Chain

`Game server observes location -> Generate LocationProof -> Player submits proof -> Contract deserializes and verifies -> Allow/deny business action`

## Corresponding Code Directory

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)

## Key Structs

| Type | Purpose | Reading Focus |
|------|------|------|
| `Location` | On-chain location hash container | See that only hash is stored on-chain, not plaintext coordinates |
| `LocationProofMessage` | Server-signed location proof message body | See if player, source object, target object, distance, deadline are all bound |
| `LocationProof` | Proof payload submitted on-chain | See how bytes, signature, and message body are combined |

## Key Entry Functions

| Entry | Purpose | What to Confirm |
|------|------|------|
| `verify_proximity` | Verify "player is near target" | Whether signature, target object, distance threshold, time window are all validated |
| BCS deserialization path | Restore proof from bytes | Whether field order matches off-chain encoding exactly |
| Business module wrapper entry | Connect proximity proof to Gate / Turret / Storage | Whether proof is bound to specific business object rather than generic reuse |

## Most Easily Misunderstood Points

- Location proof doesn't just prove "I am present," but proves "I am near a certain object, within a certain time window"
- Only checking distance without checking target object allows proof to be misused across different business entries
- BCS field order mismatch usually isn't a cryptography issue but an encoding issue

Location proof is best understood as a protocol layer, not as "a signature object." It has at least 4 layers of meaning: who is present, relative to what, within what time window, and what other business context is bound. Truly secure Builder designs don't just check the `distance` field alone, but bind `player_address`, `target_structure_id`, `target_location_hash`, `deadline_ms`, and even business identifiers in `data` into an inseparable statement.

## 1. Core Problem of Location System

EVE Frontier's on-chain contracts face a fundamental challenge: **How to verify a player (ship) is currently near a certain spatial location?**

On-chain contracts cannot access real-time game world location data. EVE Frontier's solution is **LocationProof**:

```
Game server observes "Player A is near Building B (distance < 1000m)"
    ↓
Server signs this "observed fact" into a LocationProof
    ↓
Player A submits this proof to on-chain contract
    ↓
Contract verifies signature, location hash, expiration time then executes business logic
```

---

## 2. LocationProof Data Structure

```move
// world/sources/primitives/location.move

/// Location hash (32 bytes, mixed hash containing x/y/z coordinates)
public struct Location has store {
    location_hash: vector<u8>,  // 32 bytes
}

/// Server-signed location proof message body
public struct LocationProofMessage has copy, drop {
    server_address: address,          // Signer (server address)
    player_address: address,          // Player wallet address being proven
    source_structure_id: ID,          // ID of structure player is at
    source_location_hash: vector<u8>, // Hash of player's location
    target_structure_id: ID,          // Target building's ID
    target_location_hash: vector<u8>, // Hash of target's location
    distance: u64,                    // Distance between them (game units)
    data: vector<u8>,                 // Stores additional business data
    deadline_ms: u64,                 // Proof expiration time (milliseconds)
}

/// Complete location proof (message body + signature)
public struct LocationProof has drop {
    message: LocationProofMessage,
    signature: vector<u8>,
}
```

The most noteworthy field here is actually `data`. Its existence isn't to "add more notes," but to reserve extension binding positions for different businesses. For example, a treasure chest system can write chest type or opening round into it, a market system can write market_id or order context into it. This way a proof isn't just "I am at a location," but "I am at a location, and this proof is for a specific business entry." If this binding layer is abandoned, proofs can easily be misused across multiple entries.

---

## 3. Complete Analysis of verify_proximity Function

```move
pub fun verify_proximity(
    location: &Location,           // Target building's on-chain location object
    proof: LocationProof,          // Player-submitted proof
    server_registry: &ServerAddressRegistry, // Authorized server whitelist
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let LocationProof { message, signature } = proof;

    // ① Validate message field validity
    validate_proof_message(&message, location, server_registry, ctx.sender());

    // ② Serialize message struct to bytes (BCS format)
    let message_bytes = bcs::to_bytes(&message);

    // ③ Verify deadline not expired
    assert!(is_deadline_valid(message.deadline_ms, clock), EDeadlineExpired);

    // ④ Call sig_verify to verify Ed25519 signature
    assert!(
        sig_verify::verify_signature(
            message_bytes,
            signature,
            message.server_address,
        ),
        ESignatureVerificationFailed,
    )
}
```

### validate_proof_message Internal Verification

```move
fun validate_proof_message(
    message: &LocationProofMessage,
    expected_location: &Location,
    server_registry: &ServerAddressRegistry,
    sender: address,
) {
    // 1. Server address is in whitelist
    assert!(
        access::is_authorized_server_address(server_registry, message.server_address),
        EUnauthorizedServer,
    );

    // 2. Player address in message matches caller (prevent others using your proof)
    assert!(message.player_address == sender, EUnverifiedSender);

    // 3. Target location hash matches on-chain Location object
    assert!(
        message.target_location_hash == expected_location.location_hash,
        EInvalidLocationHash,
    );
}
```

**Triple verification** ensures security:
1. ✅ Signature from authorized server
2. ✅ Proof issued for current caller (prevent front-running)
3. ✅ Target location matches on-chain object's location (prevent tampering)

These three verifications solve basic identity and target binding, but Builders often need a fourth verification: **business binding**. For example, "opening this door" and "opening that chest" even if both are near the same coordinates, should not share the same proof. The safest approach is to make the `data` or target object field uniquely point to this business entry, rather than relying only on spatial proximity.

---

## 4. BCS Deserialization: Restoring LocationProof from Bytes

When players submit `proof_bytes` (raw bytes) via SDK rather than a struct, the contract needs manual deserialization:

```move
pub fun verify_proximity_proof_from_bytes(
    server_registry: &ServerAddressRegistry,
    location: &Location,
    proof_bytes: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Manual BCS deserialization
    let (message, signature) = unpack_proof(proof_bytes);
    // ...(same as verify_proximity afterwards)
}
```

### unpack_proof's BCS Manual Deserialization

```move
fun unpack_proof(proof_bytes: vector<u8>): (LocationProofMessage, vector<u8>) {
    let mut bcs_data = bcs::new(proof_bytes);

    // "Peel" fields in BCS field order
    let server_address = bcs_data.peel_address();
    let player_address = bcs_data.peel_address();

    // ID type restored via address
    let source_structure_id = object::id_from_address(bcs_data.peel_address());

    // vector<u8> type uses peel_vec! macro
    let source_location_hash = bcs_data.peel_vec!(|bcs| bcs.peel_u8());

    let target_structure_id = object::id_from_address(bcs_data.peel_address());
    let target_location_hash = bcs_data.peel_vec!(|bcs| bcs.peel_u8());
    let distance = bcs_data.peel_u64();
    let data = bcs_data.peel_vec!(|bcs| bcs.peel_u8());
    let deadline_ms = bcs_data.peel_u64();
    let signature = bcs_data.peel_vec!(|bcs| bcs.peel_u8());

    let message = LocationProofMessage {
        server_address, player_address, source_structure_id,
        source_location_hash, target_structure_id, target_location_hash,
        distance, data, deadline_ms,
    };
    (message, signature)
}
```

> **`peel_vec!` macro**: Standard way to handle BCS-encoded `vector<u8>` in Move 2024, equivalent to reading length first, then reading bytes one by one.

---

## 5. Distance Verification

Besides "whether nearby," also supports "whether distance between two structures meets requirements":

```move
pub fun verify_distance(
    location: &Location,
    server_registry: &ServerAddressRegistry,
    proof_bytes: vector<u8>,
    max_distance: u64,           // Builder-set maximum distance threshold
    ctx: &mut TxContext,
) {
    let (message, signature) = unpack_proof(proof_bytes);
    validate_proof_message(&message, location, server_registry, ctx.sender());
    let message_bytes = bcs::to_bytes(&message);

    // Verify distance doesn't exceed Builder-set threshold
    assert!(message.distance <= max_distance, EOutOfRange);

    assert!(
        sig_verify::verify_signature(message_bytes, signature, message.server_address),
        ESignatureVerificationFailed,
    )
}
```

### Same Location Verification (No Signature Needed)

```move
/// Verify two temporary inventories are at same location (for EVE space P2P trading)
pub fun verify_same_location(location_a_hash: vector<u8>, location_b_hash: vector<u8>) {
    assert!(location_a_hash == location_b_hash, ENotInProximity);
}
```

---

## 6. Builder Practice: Space-Restricted Trading Market

```move
module my_market::space_market;

use world::location::{Self, Location, LocationProof};
use world::access::ServerAddressRegistry;
use sui::clock::Clock;

/// Only players near market can purchase
pub fun buy_item(
    market: &mut Market,
    market_location: &Location,          // Market's on-chain location object
    proximity_proof: LocationProof,       // Player-submitted location proof
    server_registry: &ServerAddressRegistry,
    payment: Coin<SUI>,
    item_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Verify player is near market (core guard)
    location::verify_proximity(
        market_location,
        proximity_proof,
        server_registry,
        clock,
        ctx,
    );

    // Subsequent business logic
    // ...
}
```

---

## 7. Builder Practice: Location-Locked Treasure Chest

```move
module my_treasure::chest;

use world::location::{Self, Location};
use world::access::ServerAddressRegistry;

/// Can only open chest when at chest location
pub fun open_chest(
    chest: &mut TreasureChest,
    chest_location: &Location,
    proximity_proof_bytes: vector<u8>,
    server_registry: &ServerAddressRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Use bytes interface (server passes bytes directly, no need to construct struct in PTB)
    location::verify_proximity_proof_from_bytes(
        server_registry,
        chest_location,
        proximity_proof_bytes,
        clock,
        ctx,
    );

    // Open chest!
    let loot = chest.claim_loot(ctx);
    transfer::public_transfer(loot, ctx.sender());
}
```

---

## 8. Location Proof Expiration Mechanism

```move
fun is_deadline_valid(deadline_ms: u64, clock: &Clock): bool {
    let current_time_ms = clock.timestamp_ms();
    deadline_ms > current_time_ms
}
```

Game servers typically set **30 seconds to 5 minutes** validity period for location proofs. After expiration, players need to request a new proof from the server.

**Design Recommendation**:
- One-time actions (like opening chest): Set 30 second validity
- Continuous actions (like mining session): Set 5 minute validity, refresh periodically

Expiration time essentially balances two things: security window and interaction cost. Window too long, risk of proof being intercepted or player delaying use increases; window too short, network jitter, wallet confirmation delay, sponsored transaction queuing become false negatives. When designing as a Builder, don't just ask "theoretically how short is safest," but also look at how long it typically takes from server signature to on-chain finalization in real transaction paths.

---

## 9. Special Handling for Testing

Since test environments cannot run real game server signatures, world-contracts provides test versions without deadline verification:

```move
#[test_only]
pub fun verify_proximity_without_deadline(
    server_registry: &ServerAddressRegistry,
    location: &Location,
    proof: LocationProof,
    ctx: &mut TxContext,
): bool {
    let LocationProof { message, signature } = proof;
    validate_proof_message(&message, location, server_registry, ctx.sender());
    let message_bytes = bcs::to_bytes(&message);
    sig_verify::verify_signature(message_bytes, signature, message.server_address)
}
```

In tests, you can pre-generate a fixed "never expires" signature, bypassing time checks.

---

## Chapter Summary

| Concept | Key Points |
|------|------|
| `Location` | 32-byte hash, maintained by game server |
| `LocationProof` | Message body + Ed25519 signature, limited validity |
| Triple verification | Server whitelist + player address match + location hash match |
| `verify_distance` | Supports verification of upper limit on distance between two buildings |
| BCS peel manual deserialization | Field order must match struct definition |

> Next Chapter: **Energy and Fuel System** — Deep dive into EVE Frontier's dual-layer energy mechanism for building operations, and precise calculation logic for fuel consumption rates.
