# Practical Example 1: Whitelisted Mining Zone Guard (Smart Turret Access Control)

> **Goal:** Write a smart turret extension that only allows players holding a "Mining Pass NFT" to pass; build a management interface that enables the Owner to issue passes online.

---

> Status: Mapped to local code directory. The content covers Pass NFT and turret whitelist logic, suitable as a complete Builder closed-loop example.

## Corresponding Code Directory

- [example-01](./code/example-01)
- [example-01/dapp](./code/example-01/dapp)

## Minimal Call Chain

`Owner issues pass -> Player holds MiningPass -> Turret extension reads credentials -> Grant passage or fire`

## Requirements Analysis

**Scenario:** Your alliance has mined a rare mineral zone in deep space and deployed a smart turret to protect the base. You want to treat different roles differently:
- ✅ **Alliance members**: Hold `MiningPass` NFT, turret grants passage
- ❌ **Non-members**: No `MiningPass`, turret automatically fires

**Additional requirements:**
- Owner (you) can issue `MiningPass` to trusted roles via dApp
- `MiningPass` can be revoked by Owner
- dApp displays current protection status and pass holder list

---

## Part 1: Move Contract Development

### Directory Structure

```
mining-guard/
├── Move.toml
└── sources/
    ├── mining_pass.move      # NFT definition
    └── guard_extension.move  # Turret extension
```

### Step 1: Define MiningPass NFT

```move
// sources/mining_pass.move
module mining_guard::mining_pass;

use sui::object::{Self, UID};
use sui::tx_context::TxContext;
use sui::transfer;
use sui::event;

/// Mining zone pass NFT
public struct MiningPass has key, store {
    id: UID,
    holder_name: vector<u8>,    // Holder name (for identification)
    issued_at_ms: u64,          // Issue timestamp
    zone_id: u64,               // Which mining zone (supports multiple zones)
}

/// Admin capability (only held by contract deployer)
public struct AdminCap has key, store {
    id: UID,
}

/// Event: New pass issued
public struct PassIssued has copy, drop {
    pass_id: ID,
    recipient: address,
    zone_id: u64,
}

/// Contract initialization: Deployer receives AdminCap
fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    // Transfer AdminCap to deployer address
    transfer::transfer(admin_cap, ctx.sender());
}

/// Issue mining zone pass (only callable by AdminCap holder)
public fun issue_pass(
    _admin_cap: &AdminCap,             // Verify caller is admin
    recipient: address,                 // Recipient address
    holder_name: vector<u8>,
    zone_id: u64,
    ctx: &mut TxContext,
) {
    let pass = MiningPass {
        id: object::new(ctx),
        holder_name,
        issued_at_ms: ctx.epoch_timestamp_ms(),
        zone_id,
    };

    // Emit event
    event::emit(PassIssued {
        pass_id: object::id(&pass),
        recipient,
        zone_id,
    });

    // Transfer pass to recipient
    transfer::transfer(pass, recipient);
}

/// Revoke pass
/// Owner can destroy a specific role's pass via admin_cap
/// (Actually, you can design "recall + destroy", here simplified to let holder burn it themselves)
public fun revoke_pass(
    _admin_cap: &AdminCap,
    pass: MiningPass,
) {
    let MiningPass { id, .. } = pass;
    id.delete();
}

/// Check if pass belongs to a specific zone
public fun is_valid_for_zone(pass: &MiningPass, zone_id: u64): bool {
    pass.zone_id == zone_id
}
```

### Step 2: Write Turret Extension

```move
// sources/guard_extension.move
module mining_guard::guard_extension;

use mining_guard::mining_pass::{Self, MiningPass};
use world::turret::{Self, Turret};
use world::character::Character;
use sui::tx_context::TxContext;

/// Turret extension Witness type
public struct GuardAuth has drop {}

/// Protected zone ID (this version protects zone 1)
const PROTECTED_ZONE_ID: u64 = 1;

/// Request safe passage (player with pass is allowed by turret)
///
/// Note: The actual turret's "no-fire" logic is executed by the game server,
/// this contract is used to verify and record the permission intent
public fun request_safe_passage(
    turret: &mut Turret,
    character: &Character,
    pass: &MiningPass,           // Must hold pass
    ctx: &mut TxContext,
) {
    // Verify pass belongs to correct zone
    assert!(
        mining_pass::is_valid_for_zone(pass, PROTECTED_ZONE_ID),
        0  // Error code: Invalid zone pass
    );

    // Call turret's safe passage function, pass GuardAuth{} as extension credential
    // (Actual API depends on world contract)
    turret::grant_safe_passage(
        turret,
        character,
        GuardAuth {},
        ctx,
    );
}
```

### Step 3: Compile and Publish

```bash
cd mining-guard

# Compile check
sui move build

# Publish to testnet
sui client publish

# Record output:
# Package ID: 0x_YOUR_PACKAGE_ID_
# AdminCap Object ID: 0x_YOUR_ADMIN_CAP_
```

### Step 4: Register Extension to Turret

```typescript
// scripts/register-extension.ts
import { Transaction } from "@mysten/sui/transactions";
import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

const WORLD_PACKAGE = "0x...";
const MY_PACKAGE = "0x_YOUR_PACKAGE_ID_";
const TURRET_ID = "0x...";
const CHARACTER_ID = "0x...";
const OWNER_CAP_ID = "0x...";

async function registerExtension() {
  const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });
  const keypair = Ed25519Keypair.fromSecretKey(/* your key */);

  const tx = new Transaction();

  // 1. Borrow turret's OwnerCap from character
  const [ownerCap] = tx.moveCall({
    target: `${WORLD_PACKAGE}::character::borrow_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::turret::Turret`],
    arguments: [tx.object(CHARACTER_ID), tx.object(OWNER_CAP_ID)],
  });

  // 2. Register our extension
  tx.moveCall({
    target: `${WORLD_PACKAGE}::turret::authorize_extension`,
    typeArguments: [`${MY_PACKAGE}::guard_extension::GuardAuth`],
    arguments: [tx.object(TURRET_ID), ownerCap],
  });

  // 3. Return OwnerCap
  tx.moveCall({
    target: `${WORLD_PACKAGE}::character::return_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::turret::Turret`],
    arguments: [tx.object(CHARACTER_ID), ownerCap],
  });

  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
  });
  console.log("Extension registration successful! Tx:", result.digest);
}

registerExtension();
```

---

## Part 2: Admin dApp

### Feature: Pass Issuance Interface

```tsx
// src/AdminPanel.tsx
import { useState } from 'react'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { useConnection } from '@evefrontier/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'

const MY_PACKAGE = "0x_YOUR_PACKAGE_ID_"
const ADMIN_CAP_ID = "0x_YOUR_ADMIN_CAP_"

export function AdminPanel() {
  const { isConnected, handleConnect } = useConnection()
  const dAppKit = useDAppKit()
  const [recipient, setRecipient] = useState('')
  const [holderName, setHolderName] = useState('')
  const [status, setStatus] = useState('')

  const issuePass = async () => {
    if (!recipient || !holderName) {
      setStatus('❌ Please fill in recipient address and name')
      return
    }

    const tx = new Transaction()
    tx.moveCall({
      target: `${MY_PACKAGE}::mining_pass::issue_pass`,
      arguments: [
        tx.object(ADMIN_CAP_ID),
        tx.pure.address(recipient),
        tx.pure.vector('u8', Array.from(new TextEncoder().encode(holderName))),
        tx.pure.u64(1), // Zone ID
      ],
    })

    try {
      setStatus('⏳ Submitting transaction...')
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ Pass issued! Tx: ${result.digest.slice(0, 12)}...`)
    } catch (e: any) {
      setStatus(`❌ Failed: ${e.message}`)
    }
  }

  if (!isConnected) {
    return (
      <div className="admin-panel">
        <button onClick={handleConnect}>🔗 Connect Admin Wallet</button>
      </div>
    )
  }

  return (
    <div className="admin-panel">
      <h2>🛡 Mining Pass Management</h2>

      <div className="form-group">
        <label>Recipient Sui Address</label>
        <input
          value={recipient}
          onChange={e => setRecipient(e.target.value)}
          placeholder="0x..."
        />
      </div>

      <div className="form-group">
        <label>Holder Name</label>
        <input
          value={holderName}
          onChange={e => setHolderName(e.target.value)}
          placeholder="Mining Corp Alpha"
        />
      </div>

      <button className="issue-btn" onClick={issuePass}>
        📜 Issue Mining Pass
      </button>

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## Part 3: Player dApp

```tsx
// src/PlayerPanel.tsx
import { useConnection, useSmartObject } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

const MY_PACKAGE = "0x_YOUR_PACKAGE_ID_"
const TURRET_ID = "0x..."
const CHARACTER_ID = "0x..."

export function PlayerPanel() {
  const { isConnected, handleConnect } = useConnection()
  const { assembly, loading } = useSmartObject()
  const dAppKit = useDAppKit()
  const [passId, setPassId] = useState('')
  const [status, setStatus] = useState('')

  const requestPassage = async () => {
    const tx = new Transaction()
    tx.moveCall({
      target: `${MY_PACKAGE}::guard_extension::request_safe_passage`,
      arguments: [
        tx.object(TURRET_ID),
        tx.object(CHARACTER_ID),
        tx.object(passId),  // Player's MiningPass Object ID
      ],
    })

    try {
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('✅ Safe passage recorded, turret will grant access')
    } catch (e: any) {
      setStatus('❌ Pass verification failed, cannot enter mining zone')
    }
  }

  if (!isConnected) return <button onClick={handleConnect}>Connect Wallet</button>
  if (loading) return <div>Loading turret status...</div>

  return (
    <div className="player-panel">
      <h2>⚡ {assembly?.name ?? 'Mining Zone Guard Turret'}</h2>
      <p>Status: {assembly?.status}</p>

      <div className="pass-input">
        <label>Enter your Mining Pass Object ID</label>
        <input
          value={passId}
          onChange={e => setPassId(e.target.value)}
          placeholder="0x..."
        />
        <button onClick={requestPassage}>🛡 Request Safe Passage</button>
      </div>

      {status && <p>{status}</p>}
    </div>
  )
}
```

---

## 🎯 Complete Implementation Review

```
1. Move Contracts
   ├── mining_pass.move → Define MiningPass NFT + AdminCap + issue_pass / revoke_pass
   └── guard_extension.move → Turret extension + request_safe_passage (verify pass then call turret API)

2. Registration Flow
   └── authorize_extension<GuardAuth>(turret, owner_cap)

3. Admin dApp
   └── Enter address and name → Call issue_pass → Transfer NFT to target role

4. Player dApp
   └── Enter pass ID → Call request_safe_passage → Turret passage record on-chain
```

## 🔧 Extension Exercises

1. Add expiration time to `MiningPass`, turret denies passage after expiration
2. Record all active passes in contract for dApp query and display
3. Implement "team license": one pass can be used by multiple predefined members

---

## 📚 Related Documentation

- [Smart Turret Documentation](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/turret/README.md)
- [Chapter 3: Move Security Patterns](./chapter-03.md#35-关键安全模式)
- [Chapter 4: Register Extensions to Components](./chapter-04.md#47-将扩展发布并注册到组件)
