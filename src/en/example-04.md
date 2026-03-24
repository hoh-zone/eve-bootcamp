# Example 4: Quest Unlock System (On-Chain Quests + Conditional Gate)

> **Goal:** Build an on-chain quest system: players complete specified quests, on-chain records completion status; gate extension reads quest status, only allows players who completed quests to jump. Also provides quest publishing and verification dApp.

---

> Status: Mapped to local code directory. Main content focuses on decoupling quest state and conditional gate, suitable for permission-based gameplay entry.

## Code Directory

- [example-04](./code/example-04)
- [example-04/dapp](./code/example-04/dapp)

## Minimal Call Chain

`Register quest -> Player completes quest -> On-chain records status -> Gate reads quest status -> Allow or deny`

## Requirements Analysis

**Scenario:** You operate a gate leading to a high-value mining area. Players must first complete a series of "membership tests" to enter:

- 📋 **Quest 1**: Donate 100 units of ore to your storage box (verifiable on-chain)
- 🔑 **Quest 2**: Obtain on-chain certification issued by alliance Leader
- 🚪 **Complete all quests** → Can pass through the gate to enter mining area

**Design Features:**
- Quest status is entirely on-chain, cannot be forged
- Quest system and gate system are decoupled, easy to upgrade independently
- dApp provides quest progress tracking and one-click jump application

---

## Part 1: Quest System Contract

### `quest_registry.move`

```move
module quest_system::registry;

use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::event;
use sui::tx_context::TxContext;
use sui::transfer;

/// Quest types (using u8 enum)
const QUEST_DONATE_ORE: u8 = 0;
const QUEST_LEADER_CERT: u8 = 1;

/// Quest completion status (bit flags)
/// bit 0: QUEST_DONATE_ORE completed
/// bit 1: QUEST_LEADER_CERT completed
const QUEST_ALL_COMPLETE: u64 = 0b11;

/// Quest Registry (shared object)
public struct QuestRegistry has key {
    id: UID,
    gate_id: ID,                          // Which gate this corresponds to
    completions: Table<address, u64>,     // address → completion bit flags
}

/// Quest admin credential
public struct QuestAdminCap has key, store {
    id: UID,
    registry_id: ID,
}

/// Events
public struct QuestCompleted has copy, drop {
    registry_id: ID,
    player: address,
    quest_type: u8,
    all_done: bool,
}

/// Deploy: Create quest registry
public fun create_registry(
    gate_id: ID,
    ctx: &mut TxContext,
) {
    let registry = QuestRegistry {
        id: object::new(ctx),
        gate_id,
        completions: table::new(ctx),
    };

    let admin_cap = QuestAdminCap {
        id: object::new(ctx),
        registry_id: object::id(&registry),
    };

    transfer::share_object(registry);
    transfer::transfer(admin_cap, ctx.sender());
}

/// Admin marks quest complete (called by alliance Leader or management script)
public fun mark_quest_complete(
    registry: &mut QuestRegistry,
    cap: &QuestAdminCap,
    player: address,
    quest_type: u8,
    ctx: &TxContext,
) {
    assert!(cap.registry_id == object::id(registry), ECapMismatch);

    // Initialize player entry
    if !table::contains(&registry.completions, player) {
        table::add(&mut registry.completions, player, 0u64);
    };

    let flags = table::borrow_mut(&mut registry.completions, player);
    *flags = *flags | (1u64 << (quest_type as u64));

    let all_done = *flags == QUEST_ALL_COMPLETE;

    event::emit(QuestCompleted {
        registry_id: object::id(registry),
        player,
        quest_type,
        all_done,
    });
}

/// Query if player completed all quests
public fun is_all_complete(registry: &QuestRegistry, player: address): bool {
    if !table::contains(&registry.completions, player) {
        return false
    }
    *table::borrow(&registry.completions, player) == QUEST_ALL_COMPLETE
}

/// Query which quests player completed
public fun get_completion_flags(registry: &QuestRegistry, player: address): u64 {
    if !table::contains(&registry.completions, player) {
        return 0
    }
    *table::borrow(&registry.completions, player)
}

const ECapMismatch: u64 = 0;
```

---

### `quest_gate.move` (Gate Extension)

```move
module quest_system::quest_gate;

use quest_system::registry::{Self, QuestRegistry};
use world::gate::{Self, Gate};
use world::character::Character;
use sui::clock::Clock;
use sui::tx_context::TxContext;

/// Gate extension Witness
public struct QuestGateAuth has drop {}

/// Request jump permit after completing quests
public fun quest_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    quest_registry: &QuestRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Verify caller completed all quests
    assert!(
        registry::is_all_complete(quest_registry, ctx.sender()),
        EQuestsNotComplete,
    );

    // Issue jump permit (valid for 30 minutes)
    let expires_at = clock.timestamp_ms() + 30 * 60 * 1000;

    gate::issue_jump_permit(
        source_gate,
        dest_gate,
        character,
        QuestGateAuth {},
        expires_at,
        ctx,
    );
}

const EQuestsNotComplete: u64 = 0;
```

---

## Part 2: Quest Verification Logic (Quest 1: Donate Ore)

Quest 1 (donate ore) requires off-chain monitoring of SSU storage events, then admin manually (or script automatically) marks completion.

```typescript
// scripts/auto-quest-monitor.ts
import { SuiClient } from "@mysten/sui/client"
import { Transaction } from "@mysten/sui/transactions"
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519"

const QUEST_PACKAGE = "0x_QUEST_PACKAGE_"
const REGISTRY_ID = "0x_REGISTRY_ID_"
const QUEST_ADMIN_CAP_ID = "0x_QUEST_ADMIN_CAP_"
const STORAGE_UNIT_ID = "0x_SSU_ID_"
const DONATE_ORE_TYPE_ID = 12345 // Ore item type ID

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" })
const adminKeypair = Ed25519Keypair.fromSecretKey(/* ... */)

// Monitor SSU donation events
async function monitorDonations() {
  await client.subscribeEvent({
    filter: {
      MoveEventType: `${"0x_WORLD_PACKAGE_"}::storage_unit::ItemDeposited`,
    },
    onMessage: async (event) => {
      const { depositor, storage_unit_id, item_type_id } = event.parsedJson as any

      // Check if it's our SSU and specified item
      if (
        storage_unit_id === STORAGE_UNIT_ID &&
        Number(item_type_id) === DONATE_ORE_TYPE_ID
      ) {
        console.log(`Player ${depositor} donated ore, marking quest complete...`)
        await markQuestComplete(depositor, 0) // quest_type = 0 (QUEST_DONATE_ORE)
      }
    },
  })
}

async function markQuestComplete(player: string, questType: number) {
  const tx = new Transaction()
  tx.moveCall({
    target: `${QUEST_PACKAGE}::registry::mark_quest_complete`,
    arguments: [
      tx.object(REGISTRY_ID),
      tx.object(QUEST_ADMIN_CAP_ID),
      tx.pure.address(player),
      tx.pure.u8(questType),
    ],
  })

  const result = await client.signAndExecuteTransaction({
    signer: adminKeypair,
    transaction: tx,
  })
  console.log(`Quest marked successfully: ${result.digest}`)
}

monitorDonations()
```

---

## Part 3: Quest Tracker dApp

```tsx
// src/QuestTrackerApp.tsx
import { useState, useEffect } from 'react'
import { useConnection, getObjectWithJson } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'
import { SuiClient } from '@mysten/sui/client'

const QUEST_PACKAGE = "0x_QUEST_PACKAGE_"
const REGISTRY_ID = "0x_REGISTRY_ID_"
const SOURCE_GATE_ID = "0x..."
const DEST_GATE_ID = "0x..."
const CHARACTER_ID = "0x..."

const QUEST_NAMES = [
  { id: 0, name: 'Donate Ore', description: 'Deposit 100 units of ore into alliance storage' },
  { id: 1, name: 'Get Certified', description: 'Contact alliance Leader to issue on-chain certification' },
]

export function QuestTrackerApp() {
  const { isConnected, handleConnect, currentAddress } = useConnection()
  const dAppKit = useDAppKit()
  const [flags, setFlags] = useState<number>(0)
  const [isJumping, setIsJumping] = useState(false)
  const [status, setStatus] = useState('')

  const allComplete = flags === 0b11

  // Load quest completion status
  useEffect(() => {
    if (!currentAddress) return

    const loadFlags = async () => {
      // Read player entry in table via GraphQL
      const client = new SuiClient({ url: 'https://fullnode.testnet.sui.io:443' })
      const obj = await client.getDynamicFieldObject({
        parentId: REGISTRY_ID,
        name: {
          type: 'address',
          value: currentAddress,
        },
      })

      if (obj.data?.content?.dataType === 'moveObject') {
        setFlags(Number((obj.data.content.fields as any).value))
      } else {
        setFlags(0) // Player has no record yet
      }
    }

    loadFlags()
  }, [currentAddress])

  const handleJump = async () => {
    if (!allComplete) {
      setStatus('❌ Please complete all quests first')
      return
    }

    setIsJumping(true)
    setStatus('⏳ Requesting jump permit...')

    try {
      const tx = new Transaction()
      tx.moveCall({
        target: `${QUEST_PACKAGE}::quest_gate::quest_jump`,
        arguments: [
          tx.object(SOURCE_GATE_ID),
          tx.object(DEST_GATE_ID),
          tx.object(CHARACTER_ID),
          tx.object(REGISTRY_ID),
          tx.object('0x6'), // Clock
        ],
      })

      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('🚀 Jump permit obtained, enjoy the mining area!')
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    } finally {
      setIsJumping(false)
    }
  }

  return (
    <div className="quest-tracker">
      <h1>🌟 Alliance Membership Test</h1>

      {!isConnected ? (
        <button onClick={handleConnect}>Connect Wallet</button>
      ) : (
        <>
          <div className="quest-list">
            {QUEST_NAMES.map(quest => {
              const done = (flags & (1 << quest.id)) !== 0
              return (
                <div key={quest.id} className={`quest-item ${done ? 'done' : 'pending'}`}>
                  <span className="quest-icon">{done ? '✅' : '⬜'}</span>
                  <div>
                    <strong>{quest.name}</strong>
                    <p>{quest.description}</p>
                  </div>
                </div>
              )
            })}
          </div>

          <div className="progress">
            Completion Progress: {Object.keys(QUEST_NAMES)
              .filter(i => (flags & (1 << Number(i))) !== 0).length} / {QUEST_NAMES.length}
          </div>

          <button
            className={`jump-btn ${allComplete ? 'active' : 'locked'}`}
            onClick={handleJump}
            disabled={!allComplete || isJumping}
          >
            {allComplete
              ? (isJumping ? '⏳ Requesting...' : '🚀 Enter Mining Area')
              : '🔒 Complete all quests to enter'
            }
          </button>

          {status && <p className="status">{status}</p>}
        </>
      )}
    </div>
  )
}
```

---

## 🎯 Complete Review

```
Contract Layer
├── quest_registry.move
│   ├── QuestRegistry (shared object, stores player completion bit flags)
│   ├── QuestAdminCap (admin credential)
│   ├── mark_quest_complete() ← Admin calls
│   └── is_all_complete()     ← Gate contract calls
│
└── quest_gate.move
    ├── QuestGateAuth (gate extension Witness)
    └── quest_jump()          ← Player calls
        ├── registry::is_all_complete() → Verify quest completion
        └── gate::issue_jump_permit()   → Issue permit

Off-Chain Monitoring
└── auto-quest-monitor.ts
    ├── Subscribe to SSU ItemDeposited events
    └── Automatically call mark_quest_complete()

dApp Layer
└── QuestTrackerApp.tsx
    ├── Display quest progress (decode bit flags)
    └── One-click jump permit request
```

---

## 🔧 Extension Exercises

1. **Quest Expiration**: Quests valid for 7 days after completion, expired need re-completion (store timestamp alongside bit flags)
2. **On-Chain Quest 1** (no off-chain needed): Player actively calls `donate_ore()` function, directly transfers item, contract automatically marks quest complete
3. **Quest Points**: Each quest has different point weight, unlock gate when total reaches threshold

---

## 📚 Related Documentation

- [Chapter 11: OwnerCap & Keychain](./chapter-11.md)
- [Chapter 12: Bit Flags & Table](./chapter-12.md)
- [Smart Gate Documentation](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/gate/README.md)
