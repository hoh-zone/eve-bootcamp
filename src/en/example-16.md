# Practical Case 16: NFT Crafting and Disassembly System

> **Objective:** Build a material crafting system—destroy multiple low-level NFTs to craft one high-level NFT (probabilistic), also support disassembling high-level NFTs into materials; use on-chain randomness to ensure fair results.

---

> Status: Teaching example. The main text explains crafting/disassembly and random number integration, complete directory is based on `book/src/code/example-16/`.

## Corresponding Code Directory

- [example-16](./code/example-16)
- [example-16/dapp](./code/example-16/dapp)

## Minimal Call Chain

`User selects materials -> Contract reads random number -> Execute craft/fail return -> Emit event -> Frontend refreshes results`

## Requirements Analysis

**Scenario:** You've designed a three-tier equipment system:

- **Material Fragment**: Common, random drops
- **Refined Component**: 3 fragments → 60% chance to craft
- **Ancient Artifact**: 3 refined components → 30% chance to craft, returns 1 component on failure

---

## Contract

```move
module crafting::forge;

use sui::object::{Self, UID, ID};
use sui::random::{Self, Random};
use sui::transfer;
use sui::event;
use std::string::{Self, String, utf8};

// ── Constants ──────────────────────────────────────────────────

const TIER_FRAGMENT: u8 = 0;
const TIER_COMPONENT: u8 = 1;
const TIER_ARTIFACT: u8 = 2;

// Crafting success rates (BPS)
const FRAGMENT_TO_COMPONENT_BPS: u64 = 6_000; // 60%
const COMPONENT_TO_ARTIFACT_BPS: u64 = 3_000; // 30%

// ── Data Structures ───────────────────────────────────────────────

public struct ForgeItem has key, store {
    id: UID,
    tier: u8,
    name: String,
    image_url: String,
    power: u64,    // Attribute value (higher tier = stronger)
}

public struct ForgeAdminCap has key, store { id: UID }

// ── Events ──────────────────────────────────────────────────

public struct CraftAttempted has copy, drop {
    crafter: address,
    input_tier: u8,
    success: bool,
    result_tier: u8,
}

public struct ItemDisassembled has copy, drop {
    crafter: address,
    from_tier: u8,
    fragments_returned: u64,
}

// ── Initialization ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::public_transfer(ForgeAdminCap { id: object::new(ctx) }, ctx.sender());
}

/// Mint base fragment (Admin only, e.g., quest reward)
public fun mint_fragment(
    _cap: &ForgeAdminCap,
    recipient: address,
    ctx: &mut TxContext,
) {
    let item = ForgeItem {
        id: object::new(ctx),
        tier: TIER_FRAGMENT,
        name: utf8(b"Plasma Fragment"),
        image_url: utf8(b"https://assets.example.com/fragment.png"),
        power: 10,
    };
    transfer::public_transfer(item, recipient);
}

// ── Crafting: 3 low-level → 1 high-level (with random success rate) ────────────

public fun craft(
    input1: ForgeItem,
    input2: ForgeItem,
    input3: ForgeItem,
    random: &Random,
    ctx: &mut TxContext,
) {
    // Three inputs must be same tier
    assert!(input1.tier == input2.tier && input2.tier == input3.tier, EMismatchedTier);
    let input_tier = input1.tier;
    assert!(input_tier < TIER_ARTIFACT, EMaxTierReached);

    let target_tier = input_tier + 1;

    // Get on-chain random number (0-9999)
    let mut rng = random::new_generator(random, ctx);
    let roll = rng.generate_u64() % 10_000;

    let success_threshold = if target_tier == TIER_COMPONENT {
        FRAGMENT_TO_COMPONENT_BPS
    } else {
        COMPONENT_TO_ARTIFACT_BPS
    };

    // Destroy all three inputs regardless of success
    let ForgeItem { id: id1, .. } = input1;
    let ForgeItem { id: id2, .. } = input2;
    let ForgeItem { id: id3, .. } = input3;
    id1.delete(); id2.delete(); id3.delete();

    let success = roll < success_threshold;

    if success {
        let (name, image_url, power) = get_tier_info(target_tier);
        let result = ForgeItem {
            id: object::new(ctx),
            tier: target_tier,
            name,
            image_url,
            power,
        };
        transfer::public_transfer(result, ctx.sender());
    } else if target_tier == TIER_ARTIFACT {
        // Consolation prize on artifact craft failure: return 1 refined component
        let (name, image_url, power) = get_tier_info(TIER_COMPONENT);
        let consolation = ForgeItem {
            id: object::new(ctx),
            tier: TIER_COMPONENT,
            name,
            image_url,
            power,
        };
        transfer::public_transfer(consolation, ctx.sender());
    };
    // No return on component craft failure (60% success rate, risk is player's)

    event::emit(CraftAttempted {
        crafter: ctx.sender(),
        input_tier,
        success,
        result_tier: if success { target_tier } else { input_tier },
    });
}

// ── Disassembly: 1 high-level → multiple low-level ────────────────────────────

public fun disassemble(
    item: ForgeItem,
    ctx: &mut TxContext,
) {
    assert!(item.tier > TIER_FRAGMENT, ECannotDisassembleFragment);

    let target_tier = item.tier - 1;
    let fragments_to_return = 2u64; // Disassembly only returns 2 (lossy)
    let item_tier = item.tier;

    let ForgeItem { id, .. } = item;
    id.delete();

    let (name, image_url, power) = get_tier_info(target_tier);
    let mut i = 0;
    while (i < fragments_to_return) {
        let fragment = ForgeItem {
            id: object::new(ctx),
            tier: target_tier,
            name,
            image_url,
            power,
        };
        transfer::public_transfer(fragment, ctx.sender());
        i = i + 1;
    };

    event::emit(ItemDisassembled {
        crafter: ctx.sender(),
        from_tier: item_tier,
        fragments_returned: fragments_to_return,
    });
}

fun get_tier_info(tier: u8): (String, String, u64) {
    if tier == TIER_FRAGMENT {
        (utf8(b"Plasma Fragment"), utf8(b"https://assets.example.com/fragment.png"), 10)
    } else if tier == TIER_COMPONENT {
        (utf8(b"Refined Component"), utf8(b"https://assets.example.com/component.png"), 100)
    } else {
        (utf8(b"Ancient Artifact"), utf8(b"https://assets.example.com/artifact.png"), 1000)
    }
}

const EMismatchedTier: u64 = 0;
const EMaxTierReached: u64 = 1;
const ECannotDisassembleFragment: u64 = 2;
```

---

## dApp (Forging Station Interface)

```tsx
// ForgingStation.tsx
import { useState } from 'react'
import { useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react'
import { useQuery } from '@tanstack/react-query'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const CRAFTING_PKG = "0x_CRAFTING_PACKAGE_"
const TIER_NAMES = ['Fragment', 'Refined Component', 'Ancient Artifact']
const CRAFT_RATES = ['60%', '30%', '—']

export function ForgingStation() {
  const client = useCurrentClient()
  const dAppKit = useDAppKit()
  const account = useCurrentAccount()
  const [selected, setSelected] = useState<string[]>([])
  const [status, setStatus] = useState('')
  const [lastCraft, setLastCraft] = useState<{success: boolean; tier: string} | null>(null)

  const { data: userItems, refetch } = useQuery({
    queryKey: ['forge-items', account?.address],
    queryFn: async () => {
      if (!account) return []
      const objs = await client.getOwnedObjects({
        owner: account.address,
        filter: { StructType: `${CRAFTING_PKG}::forge::ForgeItem` },
        options: { showContent: true },
      })
      return objs.data.map(obj => ({
        id: obj.data!.objectId,
        tier: Number((obj.data!.content as any).fields.tier),
        name: (obj.data!.content as any).fields.name,
        power: (obj.data!.content as any).fields.power,
      }))
    },
    enabled: !!account,
  })

  const toggleSelect = (id: string) => {
    setSelected(prev =>
      prev.includes(id) ? prev.filter(i => i !== id) : prev.length < 3 ? [...prev, id] : prev
    )
  }

  const handleCraft = async () => {
    if (selected.length !== 3) return
    const tx = new Transaction()
    tx.moveCall({
      target: `${CRAFTING_PKG}::forge::craft`,
      arguments: [
        tx.object(selected[0]),
        tx.object(selected[1]),
        tx.object(selected[2]),
        tx.object('0x8'), // Random system object
      ],
    })
    try {
      setStatus('Crafting (on-chain random determination)...')
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      // Read craft result from event
      const craftEvent = result.events?.find(e => e.type.includes('CraftAttempted'))
      if (craftEvent) {
        const { success, result_tier } = craftEvent.parsedJson as any
        setLastCraft({ success, tier: TIER_NAMES[Number(result_tier)] })
        setStatus(success ? `Craft successful! Obtained ${TIER_NAMES[Number(result_tier)]}` : 'Craft failed')
      }
      setSelected([])
      refetch()
    } catch (e: any) { setStatus(`${e.message}`) }
  }

  const selectedTier = selected.length > 0 && userItems
    ? userItems.find(i => i.id === selected[0])?.tier
    : null

  return (
    <div className="forging-station">
      <h1>Mysterious Forge</h1>

      {lastCraft && (
        <div className={`craft-result ${lastCraft.success ? 'success' : 'fail'}`}>
          {lastCraft.success ? 'Craft Successful!' : 'Craft Failed'} → {lastCraft.tier}
        </div>
      )}

      <div className="craft-info">
        <div>Fragment × 3 → Refined Component (success rate {CRAFT_RATES[0]})</div>
        <div>Refined Component × 3 → Ancient Artifact (success rate {CRAFT_RATES[1]})</div>
      </div>

      <h3>Select 3 same-tier items to craft</h3>
      <div className="items-grid">
        {userItems?.map(item => (
          <div
            key={item.id}
            className={`item-slot ${selected.includes(item.id) ? 'selected' : ''}`}
            onClick={() => toggleSelect(item.id)}
          >
            <div className="tier-badge">{TIER_NAMES[item.tier]}</div>
            <div className="power">Power: {item.power}</div>
          </div>
        ))}
      </div>

      <button
        className="craft-btn"
        disabled={selected.length !== 3}
        onClick={handleCraft}
      >
        Start Crafting ({selected.length}/3 selected)
      </button>

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## Related Documentation
- [Sui On-chain Randomness](https://docs.sui.io/guides/developer/advanced/randomness-onchain)
- [Chapter 13: NFT Design](./chapter-13.md)
- [Chapter 35: Future Outlook](./chapter-35.md)
