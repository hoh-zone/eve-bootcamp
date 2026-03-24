# Chapter 13: NFT Design & Metadata Management

> **Goal:** Master Sui's NFT standard (Display), design evolvable dynamic NFTs, and apply NFTs as permission credentials, achievement badges, and game assets in the EVE Frontier ecosystem.

---

> Status: Advanced design chapter. Main content focuses on NFT standards, dynamic metadata, and Collection patterns.

## 13.1 Sui's NFT Model

On Sui, an NFT is simply a unique object with the `key` ability. There's no special "NFT contract" - any object with a unique ObjectID is naturally an NFT:

```move
// Simplest NFT
public struct Badge has key, store {
    id: UID,
    name: vector<u8>,
    description: vector<u8>,
    image_url: vector<u8>,
}
```

The most important understanding isn't "NFTs can display images," but rather:

> An NFT on Sui is first an object, and second a collectible or display item.

This means you can naturally use NFTs in three different scenarios:

- **Pure display**
  Badges, memorabilia, achievement proofs
- **Permission-based**
  Passes, membership cards, whitelist credentials
- **Functional**
  Upgradeable ships, equipment, subscriptions, rental certificates

The design priorities for these three types of NFTs are completely different.

### Four questions to ask before designing an NFT

1. Is it primarily a display item, permission card, or operational asset?
2. Is it transferable?
3. Will its metadata change?
4. Should frontends and markets treat it as a "tradable commodity"?

If these four questions aren't answered clearly, the subsequent `Display`, `Collection`, and `TransferPolicy` will be easy to misalign.

---

## 13.2 Sui Display Standard: Making NFTs Display Correctly Everywhere

The `Display` object tells wallets and markets how to display your NFT:

```move
module my_nft::space_badge;

use sui::display;
use sui::package;
use std::string::utf8;

// One-time witness (create Publisher)
public struct SPACE_BADGE has drop {}

public struct SpaceBadge has key, store {
    id: UID,
    name: String,
    tier: u8,           // 1=Bronze, 2=Silver, 3=Gold
    earned_at_ms: u64,
    image_url: String,
}

fun init(witness: SPACE_BADGE, ctx: &mut TxContext) {
    // 1. Use OTW to create Publisher (prove package author identity)
    let publisher = package::claim(witness, ctx);

    // 2. Create Display (define how to display SpaceBadge)
    let mut display = display::new_with_fields<SpaceBadge>(
        &publisher,
        // Field name   // Template value ({field_name} will be replaced by actual field value)
        vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"image_url"),
            utf8(b"project_url"),
        ],
        vector[
            utf8(b"{name}"),                                          // NFT name
            utf8(b"EVE Frontier Builder Badge - Tier {tier}"),        // Description
            utf8(b"{image_url}"),                                     // Image URL
            utf8(b"https://evefrontier.com"),                         // Project link
        ],
        ctx,
    );

    // 3. Submit Display (freeze version, make it externally visible)
    display::update_version(&mut display);

    // 4. Transfer (Publisher to deployer, Display shared or frozen)
    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_freeze_object(display);
}
```

### What does `Display` really solve?

It solves the interpretation layer problem between "on-chain object fields" and "wallet and market display content."

Without this layer:

- Wallets can only see raw fields
- Markets have difficulty uniformly displaying name, description, image
- The same type of NFT will display inconsistently across different frontends

So `Display` isn't decoration, it's part of the NFT product experience.

### Most common mistakes when designing Display

#### 1. Stuffing all display semantics into on-chain fields

Not all display copy needs to be mutable on-chain fields. Some stable descriptions are better suited for templates, while some dynamic state is better suited for fields.

#### 2. Over-relying on external image URLs

If image resource paths are unstable, the NFT itself still exists, but the user-visible experience will collapse.

#### 3. Field naming disconnected from frontend understanding

If on-chain fields are named too internally, the frontend and wallet layer will have difficulty interpreting them stably.

---

## 13.3 Dynamic NFTs: Evolving Metadata

EVE Frontier's game state changes in real-time, and your NFT metadata can change along with it:

```move
module my_nft::evolving_ship;

/// Evolvable ship NFT
public struct EvolvingShip has key, store {
    id: UID,
    name: String,
    hull_class: u8,        // 0=Frigate, 1=Cruiser, 2=Battleship
    combat_score: u64,     // Combat points (increase with battles)
    kills: u64,            // Kill count
    image_url: String,     // Changes based on hull_class
}

/// Record combat result (called by turret contract)
public fun record_kill(
    ship: &mut EvolvingShip,
    ctx: &TxContext,
) {
    ship.kills = ship.kills + 1;
    ship.combat_score = ship.combat_score + 100;

    // Upgrade ship level (evolution)
    if ship.combat_score >= 10_000 && ship.hull_class < 2 {
        ship.hull_class = ship.hull_class + 1;
        // Update image URL (point to higher-level asset)
        ship.image_url = get_image_url(ship.hull_class);
    }
}

fun get_image_url(class: u8): String {
    let base = b"https://assets.evefrontier.com/ships/";
    let suffix = if class == 0 { b"frigate.png" }
                 else if class == 1 { b"cruiser.png" }
                 else { b"battleship.png" };
    // Concatenate URL (string operations in Move use sui::string)
    let mut url = std::string::utf8(base);
    url.append(std::string::utf8(suffix));
    url
}
```

**Display template auto-updates**: Since Display renders using current values of fields like `{hull_class}` and `{image_url}`, when fields change, the NFT's display in wallets also updates immediately.

### What are dynamic NFTs suited for and not suited for?

Suited for:

- Growth-oriented assets
- Items whose value is affected by state
- In-game combat records, achievements, proficiency mappings

Not necessarily suited for:

- Collectibles emphasizing static scarcity narratives
- Assets where the secondary market heavily relies on fixed metadata

Because once metadata is mutable, you've introduced new product issues by default:

- Who can modify it?
- Are changes auditable?
- When players buy in, are they buying the current state or a potentially changing future state?

### Key boundaries of dynamic metadata design

- **Is state change traceable on-chain**
  Best to have event records
- **Are modification permissions clear**
  Not just any module can arbitrarily modify
- **Can the frontend correctly reflect changes**
  Otherwise on-chain changes while user interface stays on old image

---

## 13.4 Collection Pattern

```move
module my_nft::badge_collection;

/// Badge series collection (meta-object, describes this NFT series)
public struct BadgeCollection has key {
    id: UID,
    name: String,
    total_supply: u64,
    minted_count: u64,
    admin: address,
}

/// Individual badge
public struct AllianceBadge has key, store {
    id: UID,
    collection_id: ID,      // Which collection it belongs to
    serial_number: u64,     // Series number (nth minted)
    tier: u8,
    attributes: vector<NFTAttribute>,
}

public struct NFTAttribute has store, copy, drop {
    trait_type: String,
    value: String,
}

/// Mint badge (track number and total)
public fun mint_badge(
    collection: &mut BadgeCollection,
    recipient: address,
    tier: u8,
    attributes: vector<NFTAttribute>,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == collection.admin, ENotAdmin);
    assert!(collection.minted_count < collection.total_supply, ESoldOut);

    collection.minted_count = collection.minted_count + 1;

    let badge = AllianceBadge {
        id: object::new(ctx),
        collection_id: object::id(collection),
        serial_number: collection.minted_count,
        tier,
        attributes,
    };

    transfer::public_transfer(badge, recipient);
}
```

The value of Collection isn't just "categorizing a batch of NFTs," but making series management clear:

- Supply control
- Number tracking
- Official series identity
- Frontend aggregated display

### What problems are Collections best suited to solve?

- Whether a certain series is sold out
- Which series does asset #N belong to
- Whether a badge comes from that official issuance system

Without this collection layer, doing these later becomes much harder:

- Series pages
- Rarity statistics
- Official certification

---

## 13.5 NFTs as Access Control Credentials

In EVE Frontier, NFTs are the most natural permission carriers:

```move
// Using NFTs to check permissions
public fun enter_restricted_zone(
    gate: &Gate,
    character: &Character,
    badge: &AllianceBadge,   // Must hold badge to call
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Verify badge tier (need gold badge to enter)
    assert!(badge.tier >= 3, EInsufficientBadgeTier);
    // Verify badge belongs to correct collection (prevent forgery)
    assert!(badge.collection_id == OFFICIAL_COLLECTION_ID, EWrongCollection);
    // ...
}
```

This is one of the most practical NFT use cases in EVE Builder, because it makes "permission" into an object that players can actually hold and understand.

### Why are permission NFTs often better than address whitelists?

Because they're more flexible and product-oriented:

- Can be transferred
- Can be revoked
- Can have tiers
- Can have expiration times
- Frontend can intuitively display them

But you must be careful of one thing:

> As long as it's transferable, the permission flows with it.

So you must first decide whether this permission NFT should be:

- A transferable market asset
- Or a non-transferable identity credential

---

## 13.6 NFT Transfer Policies

Sui supports flexible NFT transfer policies:

```move
// Default: anyone can transfer (public_transfer)
transfer::public_transfer(badge, recipient);

// Lock-up: NFT can only be moved by specific contracts (via TransferPolicy)
use sui::transfer_policy;

// Establish TransferPolicy during package initialization (restrict transfer conditions)
fun init(witness: SPACE_BADGE, ctx: &mut TxContext) {
    let publisher = package::claim(witness, ctx);
    let (policy, policy_cap) = transfer_policy::new<SpaceBadge>(&publisher, ctx);

    // Add custom rules (such as royalty payments)
    // royalty_rule::add(&mut policy, &policy_cap, 200, 0); // 2% royalty

    transfer::public_share_object(policy);
    transfer::public_transfer(policy_cap, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}
```

### Transfer policy essentially defines "the social attributes of this NFT"

- **Free transfer**
  More like a commodity
- **Restricted transfer**
  More like a permit with rules
- **Non-transferable**
  More like identity or achievement

This isn't a technical detail, it's product positioning.

If your NFT is:

- Membership status
- Real-name credential
- Alliance internal identity card

Then default free transfer often isn't a good idea.

---

## 13.7 Embedding NFTs in EVE Frontier Assets (Object Owns Object)

```move
// Ship equipment NFT (owned by ship object)
public struct Equipment has key, store {
    id: UID,
    name: String,
    stat_bonus: u64,
}

public struct Ship has key {
    id: UID,
    // Equipment embedded in Ship object (object owns object)
    equipped_items: vector<Equipment>,
}

// Equip item to ship
public fun equip(
    ship: &mut Ship,
    equipment: Equipment,  // Equipment moves from player wallet into Ship
    ctx: &TxContext,
) {
    vector::push_back(&mut ship.equipped_items, equipment);
}
```

Object-owns-object design is especially natural for game assets, because it allows you to express:

- A ship owns multiple pieces of equipment
- A character owns a set of certificates
- A container holds multiple special assets

### When should NFTs exist independently vs. be embedded?

Suited for independent existence:

- Need to trade separately
- Need to display separately
- Need to authorize or transfer separately

Suited for embedding into other objects:

- Mainly as a component of a larger object
- Don't need frequent independent circulation
- More emphasis on combined overall state

This is essentially balancing "tradability" and "compositional expressiveness."

---

## Chapter Summary

| Knowledge Point | Core Points |
|--------|--------|
| Sui NFT Essence | Unique object with `key`, ObjectID is NFT ID |
| Display Standard | `display::new_with_fields()` defines wallet display template |
| Dynamic NFT | Mutable fields + Display template references fields → auto-sync display |
| Collection Pattern | MetaObject tracks supply and numbering |
| NFT as Permission | Pass NFT reference for permission checks, more flexible than address whitelist |
| TransferPolicy | Control NFT secondary market transfer rules (such as royalties) |

## Further Reading

- [Sui Display Standard](https://docs.sui.io/standards/display)
- [Sui NFT Guide](https://docs.sui.io/guides/developer/nft)
- [Move Book: Object Owns Object](https://move-book.com/object/ownership.html)
