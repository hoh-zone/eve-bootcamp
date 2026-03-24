# Chapter 16: Location and Proximity Systems

> **Goal:** Understand EVE Frontier's on-chain location privacy design, master how to build location-based game logic using the proximity system, and explore future ZK proof directions.

---

> Status: Educational chapter. Main focus on location privacy, server proofs, and future ZK directions.

## 16.1 On-Chain Challenges for Spatial Games

In a traditional MMORPG, location information is managed centrally by game servers. On-chain, this creates two contradictions:

1. **Transparency**: On-chain data is publicly viewable; if coordinates are stored in plaintext, all players' hidden base locations are immediately exposed
2. **Trustworthiness**: If locations are reported by clients, players can forge them ("I'm right next to you!")

EVE Frontier's solution: **Hashed locations + trusted game server signatures**.

What's most important here isn't memorizing the phrase "hashed location," but first understanding what it's balancing:

- **Privacy**
  Cannot expose base, facility, or player locations directly
- **Verifiability**
  Must allow certain distance-related actions to be proven
- **Usability**
  Cannot design the system so slowly that it's unplayable

So the location system is essentially an engineering trade-off between "privacy, trust, and real-time performance."

---

## 16.2 Hashed Locations: Protecting Coordinate Privacy

What's stored on-chain isn't plaintext coordinates, but **hash values**:

```
Storage: hash(x, y, salt) → chain.location_hash
Query: Anyone can only see the hash, cannot reverse-engineer coordinates
Verification: Players prove to the server "I know the coordinates for this hash"
```

```move
// location.move (simplified)
public struct Location has store {
    location_hash: vector<u8>,  // Hash of coordinates, not plaintext
}

/// Update location (requires game server signature authorization)
public fun update_location(
    assembly: &mut Assembly,
    new_location_hash: vector<u8>,
    admin_acl: &AdminACL,  // Must be authorized server as sponsor
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    assembly.location.location_hash = new_location_hash;
}
```

### What Can Hashed Locations Protect, and What Can't They?

They can protect:

- Plaintext coordinates aren't exposed on-chain
- Normal observers cannot directly see real locations from object fields

They cannot automatically protect against:

- Reverse-engineering risks from weak hashes or enumerable spaces
- Off-chain interfaces leaking real locations
- Frontend or logs accidentally exposing mapping relationships

In other words, hashing is one layer of the privacy system, not the whole thing.

---

## 16.3 Proximity Verification: Server Signature Pattern

When verifying "A is near B" (e.g., picking up items, jumping), the current approach uses **server signatures**:

```
① Player requests game server: "Prove I'm near stargate 0x..."
② Server queries player's actual game coordinates
③ Server verifies player is indeed near the stargate (<20km)
④ Server signs a statement "Player A is near Stargate B" with private key
⑤ Player attaches this signature to the transaction
⑥ On-chain contract verifies signature is from authorized server (AdminACL)
```

The most critical trust boundary in this design is:

> The chain doesn't know the real coordinates; it only trusts "the authorized server has already judged this for it."

This means system security depends not only on strict on-chain validation, but also on:

- Whether the game server is honest
- Whether the signature payload is complete
- Whether time windows and nonces are designed correctly

```move
// Distance verification when linking stargates
public fun link_gates(
    gate_a: &mut Gate,
    gate_b: &mut Gate,
    owner_cap_a: &OwnerCap<Gate>,
    distance_proof: vector<u8>,  // Server-signed proof of "distance > 20km between gates"
    admin_acl: &AdminACL,
    ctx: &TxContext,
) {
    // Verify server signature (simplified; actual implementation verifies ed25519 signature)
    verify_sponsor(admin_acl, ctx);
    // ...
}
```

### 16.3.1 Recommended Minimal Proof Message Body

Don't make "proximity proof" a black box byte string that only the server understands. The minimal viable payload should bind at least these fields:

```json
{
  "proof_type": "assembly_proximity",
  "player": "0xPLAYER",
  "assembly_id": "0xASSEMBLY",
  "location_hash": "0xHASH",
  "max_distance_m": 20000,
  "issued_at_ms": 1735689600000,
  "expires_at_ms": 1735689660000,
  "nonce": "4d2f1c..."
}
```

Each field's responsibility:

- `player`: Prevents other players from reusing the proof
- `assembly_id`: Prevents using proof from stargate A to call stargate B
- `location_hash`: Binds current on-chain location state into the proof
- `issued_at_ms` / `expires_at_ms`: Limits replay window
- `nonce`: Prevents multiple replays within the same window

### 16.3.2 Minimal Loop Between Server-Side Signing and On-Chain Validation

Off-chain services must do at least two things: first verify real coordinate relationships, then sign an explicit payload.

```ts
type ProximityProofPayload = {
  proofType: "assembly_proximity";
  player: string;
  assemblyId: string;
  locationHash: string;
  maxDistanceM: number;
  issuedAtMs: number;
  expiresAtMs: number;
  nonce: string;
};

async function issueProximityProof(input: {
  player: string;
  assemblyId: string;
  expectedHash: string;
}) {
  const location = await getPlayerLocationFromGameServer(input.player);
  const assembly = await getAssemblyLocation(input.assemblyId);

  assert(hash(location) === input.expectedHash);
  assert(distance(location, assembly) <= 20_000);

  const payload: ProximityProofPayload = {
    proofType: "assembly_proximity",
    player: input.player,
    assemblyId: input.assemblyId,
    locationHash: input.expectedHash,
    maxDistanceM: 20_000,
    issuedAtMs: Date.now(),
    expiresAtMs: Date.now() + 60_000,
    nonce: crypto.randomUUID(),
  };

  return signPayload(payload);
}
```

On-chain side must validate at least four layers:

```move
// Simplified pseudocode: real implementation should deserialize payload and compare field by field
public fun verify_proximity_proof(
    assembly_id: ID,
    expected_player: address,
    expected_hash: vector<u8>,
    proof_bytes: vector<u8>,
    admin_acl: &AdminACL,
    clock: &Clock,
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);

    let payload = decode_proximity_payload(proof_bytes);
    assert!(payload.assembly_id == assembly_id, EWrongAssembly);
    assert!(payload.player == expected_player, EWrongPlayer);
    assert!(payload.location_hash == expected_hash, EWrongLocationHash);
    assert!(clock.timestamp_ms() <= payload.expires_at_ms, EProofExpired);
    assert!(check_and_consume_nonce(payload.nonce), EReplay);
}
```

What's truly important here is: `verify_sponsor(admin_acl, ctx)` only proves "this transaction came from an authorized server," which isn't enough to prove "this location statement itself is for the current object, current player, current time window."

### So What's the Most Common Mistake in Location Proofs?

Not "getting the signature algorithm wrong," but incomplete payload binding.

Once the payload misses binding one item, classic reuse problems emerge:

- Bound player but not object
  Player can use proof from A to call B
- Bound object but not time window
  Old proofs can be repeatedly replayed
- Bound time but not current location hash
  Old location can impersonate new location

---

## 16.4 Strategic Design Around Location Systems

Even though locations are hashed, Builders can still design many location-based mechanics:

### Strategy One: Location Locking (Asset Bound to Location)

```move
// Asset is only valid at specific location hash
public fun claim_resource(
    claim: &mut ResourceClaim,
    claimant_location_hash: vector<u8>,  // Server-proven location
    admin_acl: &AdminACL,
    ctx: &mut TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    // Verify player location hash matches resource point
    assert!(
        claimant_location_hash == claim.required_location_hash,
        EWrongLocation,
    );
    // Grant resource
}
```

What's truly interesting about location systems is: you don't need to know plaintext coordinates to design very strong spatial rules.

This means Builders at the upper business layer usually don't care about "exactly where you are in the universe," but rather:

- Whether you're near a certain facility
- Whether you're within a certain region
- Whether you meet entry, extraction, activation conditions

This makes many mechanics feel more like "conditional access control" rather than "map rendering systems."

### Strategy Two: Base Zone Control

```move
public struct BaseZone has key {
    id: UID,
    center_hash: vector<u8>,   // Base center location hash
    owner: address,
    zone_nft_ids: vector<ID>,  // List of friendly NFTs in this zone
}

// Authorize component only for players within base range
public fun base_service(
    zone: &BaseZone,
    service: &mut StorageUnit,
    player_in_zone_proof: vector<u8>,  // Server proof "player is within base range"
    admin_acl: &AdminACL,
    ctx: &mut TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    // ...provide service
}
```

### Strategy Three: Movement Path Tracking (Off-chain + On-chain Combined)

```typescript
// Off-chain: Listen to player location update events
client.subscribeEvent({
  filter: { MoveEventType: `${WORLD_PKG}::location::LocationUpdated` },
  onMessage: (event) => {
    const { assembly_id, new_hash } = event.parsedJson as any;
    // Update local path records
    locationHistory.push({ assembly_id, hash: new_hash, time: Date.now() });
  },
});

// On-chain: Only store hash, parse path off-chain
```

---

## 16.5 Future Direction: Zero-Knowledge Proofs Replacing Server Trust

Official documentation mentions **future plans to use ZK proofs** to replace current server signatures:

```
Now:
  Player → Server (where are you?) → Server signature → On-chain signature verification

Future (ZK):
  Player → Local computation of ZK proof ("I know coordinates satisfying this hash, and < 20km")
         → On-chain ZK verifier (no server involvement)
```

**Advantages of ZK Proofs**:
- Fully decentralized, doesn't depend on server honesty
- Players can prove "I'm here" without exposing exact coordinates
- Can theoretically prove arbitrarily complex spatial relationships

**Practical Development Recommendations**:
- During current phase, when integrating with servers, design payload structure, time windows, nonce, and object binding clearly (see Chapter 8)
- `AdminACL.verify_sponsor()` can only serve as one layer of "source verification," cannot replace payload validation
- When ZK goes live in the future, try to only replace "proof mechanism," don't rewrite upper business state machines

### Why Design Now for "Future Proof Mechanism Replaceability"?

Because what should really be stable is upper business semantics, not today's proof implementation details.

In other words, you should split the system into two layers:

- **Upper Business Rules**
  E.g., "can only withdraw items when nearby"
- **Lower Proof Mechanism**
  E.g., today it's server signatures, future might switch to ZK

This way when upgrading in the future, you're replacing "how to prove," not rewriting the entire business state machine.

### 16.5.1 Failure Scenarios and Defense Checklist

| Failure Scenario | Typical Cause | Minimal Defense |
|------|------|------|
| Proof replay | Payload lacks `nonce` or expiry time | Add `nonce` + short validity + on-chain consumption |
| Wrong object reuse | Proof doesn't bind `assembly_id` | Payload strongly binds target object |
| Wrong person reuse | Proof doesn't bind `player` | Payload strongly binds caller address |
| Old location reuse | Doesn't bind `location_hash` | Write current on-chain hash into payload |
| Server clock drift | Expiry judgment inconsistent | Use on-chain `Clock` for final judgment |

### Another Commonly Overlooked Failure Scenario: Off-Chain Cache Staleness

If the server gets an old location cache, it might sign a "formally legal, business-wise incorrect" proof.

So in real systems, you also need to consider:

- Whether server location data source is fresh enough
- Whether location sampling and on-chain state have significant delays
- Whether certain actions need shorter proof validity periods

---

## 16.6 Displaying Location Information in dApps

```tsx
// Location information not directly readable to Builders (hashed), but can display in-game coordinates
// (by interfacing with game server API for decryption)

interface AssemblyDisplayInfo {
  id: string
  name: string
  systemName: string    // Star system name (from server API)
  constellation: string // Constellation
  region: string        // Region
  onlineStatus: string
}

async function getAssemblyDisplayInfo(assemblyId: string): Promise<AssemblyDisplayInfo> {
  // 1. Read hashed location from chain
  const obj = await suiClient.getObject({
    id: assemblyId,
    options: { showContent: true },
  });
  const locationHash = (obj.data?.content as any)?.fields?.location?.fields?.location_hash;

  // 2. Query star system name via game server API using hash
  const geoRes = await fetch(`${GAME_API}/location?hash=${locationHash}`);
  const geoInfo = await geoRes.json();

  return {
    id: assemblyId,
    name: (obj.data?.content as any)?.fields?.name,
    systemName: geoInfo.system_name,
    constellation: geoInfo.constellation,
    region: geoInfo.region,
    onlineStatus: (obj.data?.content as any)?.fields?.status,
  };
}
```

### When Displaying Locations in Frontend, Most Important Isn't "How Detailed," But "Not Leaking Unauthorized Information"

So frontends are usually better suited to display:

- Star system name
- Constellation
- Region
- Online status

Rather than carelessly displaying:

- Overly granular internal coordinates
- Debug fields that can be used to reverse-engineer precise locations

This is why location systems must be designed together with the off-chain display layer, not just considering hashing in contracts and calling it done.

---

## 🔖 Chapter Summary

| Knowledge Point | Core Takeaway |
|--------|--------|
| Hashed Location | Coordinates stored as hashes, prevents privacy leaks |
| Proximity Verification | Current: Server signatures → Future: ZK proofs |
| AdminACL Role | `verify_sponsor()` verifies server's sponsor address |
| Builder Opportunities | Location locking, base zones, trajectory analysis |
| ZK Outlook | Fully decentralized spatial proofs without server trust |

## 📚 Further Reading

- [EVE World Explainer - Privacy](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/eve-frontier-world-explainer.md#privacy-location-obfuscation)
- [Sui ZK Login (Related ZK Tech Background)](https://docs.sui.io/concepts/cryptography/zklogin)
- [Constraints Documentation](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
