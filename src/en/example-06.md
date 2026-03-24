# Example 6: Dynamic NFT Equipment System (Evolving Spaceship Weapons)

> **Goal:** Create a spaceship weapon NFT system where attributes automatically upgrade based on combat results; utilize Sui Display standard to ensure NFTs display latest status in real-time across all wallets and marketplaces.

---

> Status: Teaching example. Main content focuses on dynamic NFT and Display updates, complete directory at `book/src/code/example-06/`.

## Code Directory

- [example-06](./code/example-06)
- [example-06/dapp](./code/example-06/dapp)

## Minimal Call Chain

`Player holds weapon NFT -> Kill events accumulate -> Reaches threshold to upgrade -> Display metadata updates -> Wallet/marketplace displays new appearance`

## Requirements Analysis

**Scenario:** You designed a "growth weapon" system - players obtain a `PlasmaRifle`, initially an ordinary weapon, automatically upgrades appearance and attributes as kills accumulate:

- ⚪ **Basic (0-9 kills)**: Plasma Rifle Mk.1, base damage
- 🔵 **Elite (10-49 kills)**: Plasma Rifle Mk.2, image changes to elite version, damage +30%
- 🟡 **Legendary (50+ kills)**: Plasma Rifle Mk.3 "Inferno", image changes to legendary version, special effects

---

## Part 1: NFT Contract

```move
module dynamic_nft::plasma_rifle;

use sui::object::{Self, UID};
use sui::display;
use sui::package;
use sui::transfer;
use sui::event;
use std::string::{Self, String, utf8};

// ── One-Time Witness ─────────────────────────────────────────────

public struct PLASMA_RIFLE has drop {}

// ── Weapon Tier Constants ───────────────────────────────────────────

const TIER_BASIC: u8 = 1;
const TIER_ELITE: u8 = 2;
const TIER_LEGENDARY: u8 = 3;

const KILLS_FOR_ELITE: u64 = 10;
const KILLS_FOR_LEGENDARY: u64 = 50;

// ── Data Structures ───────────────────────────────────────────────

public struct PlasmaRifle has key, store {
    id: UID,
    name: String,
    tier: u8,
    kills: u64,
    damage_bonus_pct: u64,   // Damage bonus (percentage)
    image_url: String,
    description: String,
    owner_history: u64,      // Historical transfer count
}

public struct ForgeAdminCap has key, store {
    id: UID,
}

// ── Events ──────────────────────────────────────────────────

public struct RifleEvolved has copy, drop {
    rifle_id: ID,
    from_tier: u8,
    to_tier: u8,
    total_kills: u64,
}

// ── Initialization ────────────────────────────────────────────────

fun init(witness: PLASMA_RIFLE, ctx: &mut TxContext) {
    let publisher = package::claim(witness, ctx);

    let keys = vector[
        utf8(b"name"),
        utf8(b"description"),
        utf8(b"image_url"),
        utf8(b"attributes"),
        utf8(b"project_url"),
    ];

    let values = vector[
        utf8(b"{name}"),
        utf8(b"{description}"),
        utf8(b"{image_url}"),
        // attributes concatenates multiple fields
        utf8(b"[{\"trait_type\":\"Tier\",\"value\":\"{tier}\"},{\"trait_type\":\"Kills\",\"value\":\"{kills}\"},{\"trait_type\":\"Damage Bonus\",\"value\":\"{damage_bonus_pct}%\"}]"),
        utf8(b"https://evefrontier.com/weapons"),
    ];

    let mut display = display::new_with_fields<PlasmaRifle>(
        &publisher, keys, values, ctx,
    );
    display::update_version(&mut display);

    let admin_cap = ForgeAdminCap { id: object::new(ctx) };

    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_freeze_object(display);
    transfer::public_transfer(admin_cap, ctx.sender());
}

// ── Forge Initial Weapon ──────────────────────────────────────────

public fun forge_rifle(
    _admin: &ForgeAdminCap,
    recipient: address,
    ctx: &mut TxContext,
) {
    let rifle = PlasmaRifle {
        id: object::new(ctx),
        name: utf8(b"Plasma Rifle Mk.1"),
        tier: TIER_BASIC,
        kills: 0,
        damage_bonus_pct: 0,
        image_url: utf8(b"https://assets.example.com/weapons/plasma_mk1.png"),
        description: utf8(b"A standard-issue plasma rifle. Prove yourself in combat."),
        owner_history: 0,
    };

    transfer::public_transfer(rifle, recipient);
}

// ── Record Kill (called by turret extension)────────────────────────

public fun record_kill(
    rifle: &mut PlasmaRifle,
    ctx: &TxContext,
) {
    rifle.kills = rifle.kills + 1;
    check_and_evolve(rifle);
}

fun check_and_evolve(rifle: &mut PlasmaRifle) {
    let old_tier = rifle.tier;

    if rifle.kills >= KILLS_FOR_LEGENDARY && rifle.tier < TIER_LEGENDARY {
        rifle.tier = TIER_LEGENDARY;
        rifle.name = utf8(b"Plasma Rifle Mk.3 \"Inferno\"");
        rifle.damage_bonus_pct = 60;
        rifle.image_url = utf8(b"https://assets.example.com/weapons/plasma_legendary.png");
        rifle.description = utf8(b"This weapon has bathed in the fires of a thousand battles. Its plasma burns with legendary fury.");
    } else if rifle.kills >= KILLS_FOR_ELITE && rifle.tier < TIER_ELITE {
        rifle.tier = TIER_ELITE;
        rifle.name = utf8(b"Plasma Rifle Mk.2");
        rifle.damage_bonus_pct = 30;
        rifle.image_url = utf8(b"https://assets.example.com/weapons/plasma_mk2.png");
        rifle.description = utf8(b"Battle-hardened and upgraded. The plasma cells burn hotter than standard.");
    };

    if old_tier != rifle.tier {
        event::emit(RifleEvolved {
            rifle_id: object::id(rifle),
            from_tier: old_tier,
            to_tier: rifle.tier,
            total_kills: rifle.kills,
        });
    }
}

// ── Getter Functions ──────────────────────────────────────────────

public fun get_tier(rifle: &PlasmaRifle): u8 { rifle.tier }
public fun get_kills(rifle: &PlasmaRifle): u64 { rifle.kills }
public fun get_damage_bonus(rifle: &PlasmaRifle): u64 { rifle.damage_bonus_pct }

// ── Transfer Tracking (optional) ─────────────────────────────────────

// If using TransferPolicy, can track transfer count
// Simplified here via event monitoring
```

---

## Part 2: Turret Extension - Combat Result Reports to Weapon

```move
module dynamic_nft::turret_combat;

use dynamic_nft::plasma_rifle::{Self, PlasmaRifle};
use world::turret::{Self, Turret};
use world::character::Character;

public struct CombatAuth has drop {}

/// Turret kill event (called by turret extension)
public fun on_kill(
    turret: &Turret,
    killer: &Character,
    weapon: &mut PlasmaRifle,       // Player's weapon
    ctx: &TxContext,
) {
    // Verify legitimate turret extension call (requires CombatAuth)
    turret::verify_extension(turret, CombatAuth {});

    // Record kill to weapon
    plasma_rifle::record_kill(weapon, ctx);
}
```

---

## Part 3: Frontend Weapon Display dApp

```tsx
// src/WeaponDisplay.tsx
import { useState, useEffect } from 'react'
import { useCurrentClient } from '@mysten/dapp-kit-react'
import { useRealtimeEvents } from './hooks/useRealtimeEvents'

const DYNAMIC_NFT_PKG = "0x_DYNAMIC_NFT_PACKAGE_"

interface RifleData {
  name: string
  tier: string
  kills: string
  damage_bonus_pct: string
  image_url: string
  description: string
}

const TIER_COLORS = {
  '1': '#9CA3AF',  // Gray (basic)
  '2': '#3B82F6',  // Blue (elite)
  '3': '#F59E0B',  // Gold (legendary)
}

const TIER_LABELS = { '1': 'Basic', '2': 'Elite', '3': 'Legendary' }

export function WeaponDisplay({ rifleId }: { rifleId: string }) {
  const client = useCurrentClient()
  const [rifle, setRifle] = useState<RifleData | null>(null)
  const [justEvolved, setJustEvolved] = useState(false)

  const loadRifle = async () => {
    const obj = await client.getObject({
      id: rifleId,
      options: { showContent: true },
    })
    if (obj.data?.content?.dataType === 'moveObject') {
      setRifle(obj.data.content.fields as RifleData)
    }
  }

  useEffect(() => { loadRifle() }, [rifleId])

  // Monitor evolution events
  const evolutions = useRealtimeEvents<{
    rifle_id: string; from_tier: string; to_tier: string; total_kills: string
  }>(`${DYNAMIC_NFT_PKG}::plasma_rifle::RifleEvolved`)

  useEffect(() => {
    const myEvolution = evolutions.find(e => e.rifle_id === rifleId)
    if (myEvolution) {
      setJustEvolved(true)
      loadRifle() // Reload latest data
      setTimeout(() => setJustEvolved(false), 5000)
    }
  }, [evolutions])

  if (!rifle) return <div className="loading">Loading weapon data...</div>

  const tierColor = TIER_COLORS[rifle.tier as keyof typeof TIER_COLORS]
  const tierLabel = TIER_LABELS[rifle.tier as keyof typeof TIER_LABELS]
  const killsForNextTier = rifle.tier === '1'
    ? 10 : rifle.tier === '2' ? 50 : null
  const progress = killsForNextTier
    ? Math.min(100, (Number(rifle.kills) / killsForNextTier) * 100) : 100

  return (
    <div className="weapon-card" style={{ borderColor: tierColor }}>
      {justEvolved && (
        <div className="evolution-banner">
          ✨ Weapon Evolved!
        </div>
      )}

      <div className="weapon-image-container">
        <img
          src={rifle.image_url}
          alt={rifle.name}
          className={`weapon-image tier-${rifle.tier}`}
        />
        <span className="tier-badge" style={{ background: tierColor }}>
          {tierLabel}
        </span>
      </div>

      <div className="weapon-info">
        <h2>{rifle.name}</h2>
        <p className="description">{rifle.description}</p>

        <div className="stats">
          <div className="stat">
            <span>⚔️ Kills</span>
            <strong>{rifle.kills}</strong>
          </div>
          <div className="stat">
            <span>💥 Damage Bonus</span>
            <strong>+{rifle.damage_bonus_pct}%</strong>
          </div>
        </div>

        {killsForNextTier && (
          <div className="evolution-progress">
            <span>Evolution Progress: {rifle.kills} / {killsForNextTier} kills</span>
            <div className="progress-bar">
              <div
                className="progress-fill"
                style={{ width: `${progress}%`, background: tierColor }}
              />
            </div>
          </div>
        )}

        {!killsForNextTier && (
          <div className="max-tier-badge">👑 Max Tier Reached</div>
        )}
      </div>
    </div>
  )
}
```

---

## 🎯 Complete Review

```
Contract Layer
├── plasma_rifle.move
│   ├── PlasmaRifle (NFT object, fields update with combat)
│   ├── Display (template references fields → wallet auto-syncs display)
│   ├── forge_rifle()    ← Owner mints and distributes
│   ├── record_kill()    ← Turret contract calls
│   └── check_and_evolve() ← Internal: check threshold, upgrade fields + emit event
│
└── turret_combat.move
    └── on_kill()         ← Turret kill triggers weapon upgrade

dApp Layer
└── WeaponDisplay.tsx
    ├── Subscribe to RifleEvolved event (refresh immediately on evolution)
    ├── Dynamic color theme (by tier)
    └── Evolution progress bar
```

## 🔧 Extension Exercises

1. **Weapon Durability**: Each use decreases `durability` field, quality degrades and damage reduces when low (needs repair)
2. **Special Attributes**: Legendary tier randomly gains special affixes (using random numbers + dynamic fields)
3. **Weapon Fusion**: Two Elite weapons destroyed → mint one Legendary (material consumption upgrade)

---

## 📚 Related Documentation

- [Chapter 13: NFT Design & Display Standard](./chapter-13.md)
- [Chapter 12: Event System](./chapter-12.md)
- [Sui Display Documentation](https://docs.sui.io/standards/display)
