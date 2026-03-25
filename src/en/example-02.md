# Practical Example 2: Space Highway Toll Station (Smart Stargate Toll System)

> **Goal:** Write a smart stargate extension that charges LUX tokens per jump; build a player-facing ticket purchase dApp interface.

---

> Status: Mapped to local code directory. The content covers toll stargate, tickets, and treasury triple set, one of the most typical Builder commercialization examples.

## Corresponding Code Directory

- [example-02](./code/example-02)
- [example-02/dapp](./code/example-02/dapp)

## Minimal Call Chain

`Player pays toll -> Treasury receives payment -> Mint JumpTicket -> Stargate verifies ticket -> Complete jump`

## Requirements Analysis

**Scenario:** You and your alliance control a strategic corridor consisting of two stargates, connecting two busy regions of the universe. You decide to commercialize this route:
- 🎟 Any player wanting to jump must pay **50 LUX** to purchase a `JumpTicket`
- 🏦 All collected LUX goes into the treasury (contract-managed shared object)
- 💰 Only the Owner (you) can withdraw LUX from the treasury
- 📊 dApp displays current ticket price, jump count, and treasury balance in real-time

---

## Part 1: Move Contract Development

### Directory Structure

```
toll-gate/
├── Move.toml
└── sources/
    ├── treasury.move       # Treasury: Collect and manage LUX
    └── toll_gate.move      # Stargate extension: Toll logic
```

### Step 1: Define Treasury Contract

```move
// sources/treasury.move
module toll_gate::treasury;

use sui::object::{Self, UID};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::tx_context::TxContext;
use sui::transfer;
use sui::event;

// ── Type Definitions ─────────────────────────────────────────────

/// Here we use SUI token to represent LUX (demo)
/// In actual deployment, replace with LUX Coin type

/// Treasury: Collect all tolls
public struct TollTreasury has key {
    id: UID,
    balance: Balance<SUI>,
    total_jumps: u64,      // Total jump count (for statistics)
    toll_amount: u64,      // Current ticket price (in MIST, 1 SUI = 10^9 MIST)
}

/// OwnerCap: Only holders can withdraw treasury funds
public struct TreasuryOwnerCap has key, store {
    id: UID,
}

// ── Events ──────────────────────────────────────────────────

public struct TollCollected has copy, drop {
    payer: address,
    amount: u64,
    total_jumps: u64,
}

public struct TollWithdrawn has copy, drop {
    recipient: address,
    amount: u64,
}

// ── Initialization ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    // Create treasury (shared object, anyone can deposit)
    let treasury = TollTreasury {
        id: object::new(ctx),
        balance: balance::zero(),
        total_jumps: 0,
        toll_amount: 50_000_000_000,  // 50 SUI (unit: MIST)
    };

    // Create Owner credential (transfer to deployer)
    let owner_cap = TreasuryOwnerCap {
        id: object::new(ctx),
    };

    transfer::share_object(treasury);
    transfer::transfer(owner_cap, ctx.sender());
}

// ── Public Functions ──────────────────────────────────────────────

/// Deposit toll (called by stargate extension)
public fun deposit_toll(
    treasury: &mut TollTreasury,
    payment: Coin<SUI>,
    payer: address,
) {
    let amount = coin::value(&payment);

    // Verify correct amount
    assert!(amount >= treasury.toll_amount, 1); // E_INSUFFICIENT_FEE

    treasury.total_jumps = treasury.total_jumps + 1;
    balance::join(&mut treasury.balance, coin::into_balance(payment));

    event::emit(TollCollected {
        payer,
        amount,
        total_jumps: treasury.total_jumps,
    });
}

/// Withdraw treasury LUX (only callable by TreasuryOwnerCap holder)
public fun withdraw(
    treasury: &mut TollTreasury,
    _cap: &TreasuryOwnerCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    let coin = coin::take(&mut treasury.balance, amount, ctx);
    transfer::public_transfer(coin, ctx.sender());

    event::emit(TollWithdrawn {
        recipient: ctx.sender(),
        amount,
    });
}

/// Change ticket price (Owner calls)
public fun set_toll_amount(
    treasury: &mut TollTreasury,
    _cap: &TreasuryOwnerCap,
    new_amount: u64,
) {
    treasury.toll_amount = new_amount;
}

/// Read current ticket price
public fun toll_amount(treasury: &TollTreasury): u64 {
    treasury.toll_amount
}

/// Read treasury balance
public fun balance_amount(treasury: &TollTreasury): u64 {
    balance::value(&treasury.balance)
}
```

### Step 2: Write Stargate Extension

```move
// sources/toll_gate.move
module toll_gate::toll_gate_ext;

use toll_gate::treasury::{Self, TollTreasury};
use world::gate::{Self, Gate};
use world::character::Character;
use sui::coin::Coin;
use sui::sui::SUI;
use sui::clock::Clock;
use sui::tx_context::TxContext;

/// Stargate extension Witness type
public struct TollAuth has drop {}

/// Default jump permit validity: 15 minutes
const PERMIT_DURATION_MS: u64 = 15 * 60 * 1000;

/// Pay toll and get jump permit
public fun pay_toll_and_get_permit(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    treasury: &mut TollTreasury,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. Collect toll
    treasury::deposit_toll(treasury, payment, ctx.sender());

    // 2. Calculate Permit expiration time
    let expires_at = clock.timestamp_ms() + PERMIT_DURATION_MS;

    // 3. Request jump permit from stargate (TollAuth{} is extension credential)
    gate::issue_jump_permit(
        source_gate,
        destination_gate,
        character,
        TollAuth {},
        expires_at,
        ctx,
    );

    // Note: JumpPermit object is automatically transferred to character's Owner
}
```

### Step 3: Publish Contract

```bash
cd toll-gate

sui move build

sui client publish

# Record:
# Package ID: 0x_TOLL_PACKAGE_
# TollTreasury ID: 0x_TREASURY_ID_ (shared object)
# TreasuryOwnerCap ID: 0x_OWNER_CAP_ID_
```

### Step 4: Register Extension to Stargate

```typescript
// scripts/authorize-toll-gate.ts
import { Transaction } from "@mysten/sui/transactions";
import { SuiClient } from "@mysten/sui/client";

const WORLD_PACKAGE = "0x...";
const TOLL_PACKAGE = "0x_TOLL_PACKAGE_";
const GATE_ID = "0x...";
const CHARACTER_ID = "0x...";
const GATE_OWNER_CAP_ID = "0x...";

async function authorizeTollGate() {
  const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });
  const tx = new Transaction();

  // Borrow stargate OwnerCap
  const [ownerCap] = tx.moveCall({
    target: `${WORLD_PACKAGE}::character::borrow_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::gate::Gate`],
    arguments: [tx.object(CHARACTER_ID), tx.object(GATE_OWNER_CAP_ID)],
  });

  // Register TollAuth as authorized extension
  tx.moveCall({
    target: `${WORLD_PACKAGE}::gate::authorize_extension`,
    typeArguments: [`${TOLL_PACKAGE}::toll_gate_ext::TollAuth`],
    arguments: [tx.object(GATE_ID), ownerCap],
  });

  // Return OwnerCap
  tx.moveCall({
    target: `${WORLD_PACKAGE}::character::return_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::gate::Gate`],
    arguments: [tx.object(CHARACTER_ID), ownerCap],
  });

  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
  });
  console.log("Toll station extension registered successfully!", result.digest);
}
```

---

## Part 2: Player Ticket Purchase dApp

### Complete Ticket Purchase Interface

```tsx
// src/TollGateApp.tsx
import { useState, useEffect } from 'react'
import { useConnection, useSmartObject, getObjectWithJson } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

const WORLD_PACKAGE = "0x..."
const TOLL_PACKAGE = "0x_TOLL_PACKAGE_"
const SOURCE_GATE_ID = "0x..."
const DEST_GATE_ID = "0x..."
const CHARACTER_ID = "0x..."
const TREASURY_ID = "0x_TREASURY_ID_"

interface TreasuryData {
  toll_amount: string
  total_jumps: string
  balance: string
}

export function TollGateApp() {
  const { isConnected, handleConnect, currentAddress } = useConnection()
  const { assembly, loading } = useSmartObject()
  const dAppKit = useDAppKit()

  const [treasury, setTreasury] = useState<TreasuryData | null>(null)
  const [txStatus, setTxStatus] = useState('')
  const [isPaying, setIsPaying] = useState(false)

  // Load treasury data
  const loadTreasury = async () => {
    const data = await getObjectWithJson(TREASURY_ID)
    if (data?.content?.dataType === 'moveObject') {
      setTreasury(data.content.fields as TreasuryData)
    }
  }

  useEffect(() => {
    loadTreasury()
    const interval = setInterval(loadTreasury, 10_000) // Refresh every 10 seconds
    return () => clearInterval(interval)
  }, [])

  const payAndJump = async () => {
    if (!isConnected) {
      setTxStatus('❌ Please connect wallet first')
      return
    }

    setIsPaying(true)
    setTxStatus('⏳ Submitting transaction...')

    const tollAmount = BigInt(treasury?.toll_amount ?? 50_000_000_000)
    const tx = new Transaction()

    // Split out ticket price amount of SUI
    const [paymentCoin] = tx.splitCoins(tx.gas, [
      tx.pure.u64(tollAmount)
    ])

    // Call toll and get Permit
    tx.moveCall({
      target: `${TOLL_PACKAGE}::toll_gate_ext::pay_toll_and_get_permit`,
      arguments: [
        tx.object(SOURCE_GATE_ID),
        tx.object(DEST_GATE_ID),
        tx.object(CHARACTER_ID),
        tx.object(TREASURY_ID),
        paymentCoin,
        tx.object('0x6'), // Clock system object
      ],
    })

    try {
      const result = await dAppKit.signAndExecuteTransaction({
        transaction: tx,
      })
      setTxStatus(`✅ Jump permit obtained! Tx: ${result.digest.slice(0, 12)}...`)
      loadTreasury() // Refresh treasury data
    } catch (e: any) {
      setTxStatus(`❌ ${e.message}`)
    } finally {
      setIsPaying(false)
    }
  }

  const tollInSui = treasury
    ? (Number(treasury.toll_amount) / 1e9).toFixed(2)
    : '...'

  const balanceInSui = treasury
    ? (Number(treasury.balance) / 1e9).toFixed(2)
    : '...'

  return (
    <div className="toll-gate-app">
      {/* Stargate Info */}
      <header className="gate-header">
        <div className="gate-icon">🌀</div>
        <div>
          <h1>{loading ? '...' : assembly?.name ?? 'Stargate'}</h1>
          <span className={`status-badge ${assembly?.status?.toLowerCase()}`}>
            {assembly?.status ?? 'Detecting...'}
          </span>
        </div>
      </header>

      {/* Toll Info */}
      <section className="toll-info">
        <div className="info-card">
          <span className="label">💰 Current Price</span>
          <span className="value">{tollInSui} SUI</span>
        </div>
        <div className="info-card">
          <span className="label">🚀 Total Jumps</span>
          <span className="value">{treasury?.total_jumps ?? '...'} times</span>
        </div>
        <div className="info-card">
          <span className="label">🏦 Treasury Balance</span>
          <span className="value">{balanceInSui} SUI</span>
        </div>
      </section>

      {/* Jump Action */}
      <section className="jump-section">
        {!isConnected ? (
          <button className="connect-btn" onClick={handleConnect}>
            🔗 Connect EVE Vault Wallet
          </button>
        ) : (
          <>
            <div className="wallet-info">
              ✅ {currentAddress?.slice(0, 6)}...{currentAddress?.slice(-4)}
            </div>
            <button
              className="jump-btn"
              onClick={payAndJump}
              disabled={isPaying || assembly?.status !== 'Online'}
            >
              {isPaying ? '⏳ Processing...' : `🛸 Pay ${tollInSui} SUI and Jump`}
            </button>
          </>
        )}

        {txStatus && (
          <div className={`tx-status ${txStatus.startsWith('✅') ? 'success' : 'error'}`}>
            {txStatus}
          </div>
        )}
      </section>

      {/* Destination Info */}
      <section className="destination-info">
        <p>📍 Destination: <strong>Alpha Centauri Mining Zone</strong></p>
        <p>⏱ Permit Validity: <strong>15 minutes</strong></p>
      </section>
    </div>
  )
}
```

---

## Part 3: Owner Management Panel

```tsx
// src/OwnerPanel.tsx
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

const TOLL_PACKAGE = "0x_TOLL_PACKAGE_"
const TREASURY_ID = "0x_TREASURY_ID_"
const OWNER_CAP_ID = "0x_OWNER_CAP_ID_"

export function OwnerPanel({ treasuryBalance }: { treasuryBalance: number }) {
  const dAppKit = useDAppKit()
  const [withdrawAmount, setWithdrawAmount] = useState('')
  const [newToll, setNewToll] = useState('')
  const [status, setStatus] = useState('')

  const withdraw = async () => {
    const amountMist = Math.floor(parseFloat(withdrawAmount) * 1e9)

    const tx = new Transaction()
    tx.moveCall({
      target: `${TOLL_PACKAGE}::treasury::withdraw`,
      arguments: [
        tx.object(TREASURY_ID),
        tx.object(OWNER_CAP_ID),
        tx.pure.u64(amountMist),
      ],
    })

    try {
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ Withdrawn ${withdrawAmount} SUI`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  const updateToll = async () => {
    const amountMist = Math.floor(parseFloat(newToll) * 1e9)

    const tx = new Transaction()
    tx.moveCall({
      target: `${TOLL_PACKAGE}::treasury::set_toll_amount`,
      arguments: [
        tx.object(TREASURY_ID),
        tx.object(OWNER_CAP_ID),
        tx.pure.u64(amountMist),
      ],
    })

    try {
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ Ticket price updated to ${newToll} SUI`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="owner-panel">
      <h2>⚙️ Toll Station Management</h2>

      <div className="panel-section">
        <h3>💵 Withdraw Revenue</h3>
        <p>Treasury Balance: {(treasuryBalance / 1e9).toFixed(2)} SUI</p>
        <input
          type="number"
          value={withdrawAmount}
          onChange={e => setWithdrawAmount(e.target.value)}
          placeholder="Withdraw amount (SUI)"
        />
        <button onClick={withdraw}>Withdraw to Wallet</button>
      </div>

      <div className="panel-section">
        <h3>🏷 Adjust Price</h3>
        <input
          type="number"
          value={newToll}
          onChange={e => setNewToll(e.target.value)}
          placeholder="New price (SUI)"
        />
        <button onClick={updateToll}>Update Price</button>
      </div>

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 🎯 Complete Implementation Review

```
Move Contract Layer
├── treasury.move
│   ├── TollTreasury (shared treasury object)
│   ├── TreasuryOwnerCap (withdrawal credential)
│   ├── deposit_toll()      ← Extension calls
│   ├── withdraw()          ← Owner calls
│   └── set_toll_amount()   ← Owner calls
│
└── toll_gate_ext.move
    ├── TollAuth (Witness type)
    └── pay_toll_and_get_permit()  ← Player calls
        ├── 1. Verify and charge → treasury.deposit_toll()
        └── 2. Issue permit → gate::issue_jump_permit()

dApp Layer
├── TollGateApp.tsx       → Player ticket purchase interface
│   ├── Real-time display of price, jump count, treasury balance
│   └── One-click payment and get JumpPermit
└── OwnerPanel.tsx        → Admin panel
    ├── Withdraw treasury revenue
    └── Adjust ticket price
```

---

## 🔧 Extension Exercises

1. **Tiered Membership**: Alliance members holding membership NFT get discounts (check NFT then apply different prices)
2. **Limited-Time Free Passage**: Automatically accept 0 LUX Permits during specific time periods (e.g., maintenance)
3. **Revenue Distribution**: Treasury revenue automatically distributed to multiple alliance stakeholder addresses by proportion
4. **History dApp**: Listen to `TollCollected` events, display recent 50 jump records

---

## 📚 Related Documentation

- [Smart Gate Documentation](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/gate/README.md)
- [Interfacing with the World](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [Chapter 3: Move Resources and Coin Model](./chapter-03.md)
- [Chapter 5: dApp Initiating On-Chain Transactions](./chapter-05.md#55-执行链上交易)
- [builder-scaffold Smart Gate Example](https://github.com/evefrontier/builder-scaffold/tree/main/move-contracts/smart_gate)
