# 实战案例 2：太空高速收费站（智能星门收费系统）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 编写一个智能星门扩展，实现按次收取 LUX 代币通行费；并建立一个面向玩家的购票 dApp 界面。

---

## 需求分析

**场景：** 你和联盟控制了两个星门组成的战略要道，连接了宇宙两个繁忙区域。你决定将这条航线商业化：
- 🎟 任何玩家想跳跃，必须支付 **50 LUX** 购买 `JumpTicket`
- 🏦 所有收取的 LUX 进入金库（合约管理的共享对象）
- 💰 只有 Owner（你）可以提取金库中的 LUX
- 📊 dApp 实时显示当前票价、跳跃次数、金库余额

---

## 第一部分：Move 合约开发

### 目录结构

```
toll-gate/
├── Move.toml
└── sources/
    ├── treasury.move       # 金库：收集和管理 LUX
    └── toll_gate.move      # 星门扩展：收费逻辑
```

### 第一步：定义金库合约

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

// ── 类型定义 ─────────────────────────────────────────────

/// 这里用 SUI 代币代表 LUX（演示）
/// 真实部署中换成 LUX 的 Coin 类型

/// 金库：收集所有通行费
public struct TollTreasury has key {
    id: UID,
    balance: Balance<SUI>,
    total_jumps: u64,      // 累计跳跃次数（统计用）
    toll_amount: u64,      // 当前票价（以 MIST 计，1 SUI = 10^9 MIST）
}

/// OwnerCap：只有持有此对象才能提取金库资金
public struct TreasuryOwnerCap has key, store {
    id: UID,
}

// ── 事件 ──────────────────────────────────────────────────

public struct TollCollected has copy, drop {
    payer: address,
    amount: u64,
    total_jumps: u64,
}

public struct TollWithdrawn has copy, drop {
    recipient: address,
    amount: u64,
}

// ── 初始化 ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    // 创建金库（共享对象，任何人可以存入）
    let treasury = TollTreasury {
        id: object::new(ctx),
        balance: balance::zero(),
        total_jumps: 0,
        toll_amount: 50_000_000_000,  // 50 SUI（单位：MIST）
    };

    // 创建 Owner 凭证（转给部署者）
    let owner_cap = TreasuryOwnerCap {
        id: object::new(ctx),
    };

    transfer::share_object(treasury);
    transfer::transfer(owner_cap, ctx.sender());
}

// ── 公开函数 ──────────────────────────────────────────────

/// 存入通行费（由星门扩展调用）
public fun deposit_toll(
    treasury: &mut TollTreasury,
    payment: Coin<SUI>,
    payer: address,
) {
    let amount = coin::value(&payment);

    // 验证金额正确
    assert!(amount >= treasury.toll_amount, 1); // E_INSUFFICIENT_FEE

    treasury.total_jumps = treasury.total_jumps + 1;
    balance::join(&mut treasury.balance, coin::into_balance(payment));

    event::emit(TollCollected {
        payer,
        amount,
        total_jumps: treasury.total_jumps,
    });
}

/// 提取金库 LUX（只有持有 TreasuryOwnerCap 才能调用）
public entry fun withdraw(
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

/// 修改票价（Owner 调用）
public entry fun set_toll_amount(
    treasury: &mut TollTreasury,
    _cap: &TreasuryOwnerCap,
    new_amount: u64,
) {
    treasury.toll_amount = new_amount;
}

/// 读取当前票价
public fun toll_amount(treasury: &TollTreasury): u64 {
    treasury.toll_amount
}

/// 读取金库余额
public fun balance_amount(treasury: &TollTreasury): u64 {
    balance::value(&treasury.balance)
}
```

### 第二步：编写星门扩展

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

/// 星门扩展的 Witness 类型
public struct TollAuth has drop {}

/// 默认跳跃许可有效期：15 分钟
const PERMIT_DURATION_MS: u64 = 15 * 60 * 1000;

/// 支付通行费并获得跳跃许可
public entry fun pay_toll_and_get_permit(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    treasury: &mut TollTreasury,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. 收取通行费
    treasury::deposit_toll(treasury, payment, ctx.sender());

    // 2. 计算 Permit 过期时间
    let expires_at = clock.timestamp_ms() + PERMIT_DURATION_MS;

    // 3. 向星门申请跳跃许可（TollAuth{} 是扩展凭证）
    gate::issue_jump_permit(
        source_gate,
        destination_gate,
        character,
        TollAuth {},
        expires_at,
        ctx,
    );

    // 注意：JumpPermit 对象会被自动转给 character 的 Owner
}
```

### 第三步：发布合约

```bash
cd toll-gate

sui move build

sui client publish 

# 记录：
# Package ID: 0x_TOLL_PACKAGE_
# TollTreasury ID: 0x_TREASURY_ID_（共享对象）
# TreasuryOwnerCap ID: 0x_OWNER_CAP_ID_
```

### 第四步：注册扩展到星门

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

  // 借用星门 OwnerCap
  const [ownerCap] = tx.moveCall({
    target: `${WORLD_PACKAGE}::character::borrow_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::gate::Gate`],
    arguments: [tx.object(CHARACTER_ID), tx.object(GATE_OWNER_CAP_ID)],
  });

  // 注册 TollAuth 作为授权扩展
  tx.moveCall({
    target: `${WORLD_PACKAGE}::gate::authorize_extension`,
    typeArguments: [`${TOLL_PACKAGE}::toll_gate_ext::TollAuth`],
    arguments: [tx.object(GATE_ID), ownerCap],
  });

  // 归还 OwnerCap
  tx.moveCall({
    target: `${WORLD_PACKAGE}::character::return_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::gate::Gate`],
    arguments: [tx.object(CHARACTER_ID), ownerCap],
  });

  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
  });
  console.log("收费站扩展注册成功！", result.digest);
}
```

---

## 第二部分：玩家购票 dApp

### 完整购票界面

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

  // 加载金库数据
  const loadTreasury = async () => {
    const data = await getObjectWithJson(TREASURY_ID)
    if (data?.content?.dataType === 'moveObject') {
      setTreasury(data.content.fields as TreasuryData)
    }
  }

  useEffect(() => {
    loadTreasury()
    const interval = setInterval(loadTreasury, 10_000) // 每 10 秒刷新
    return () => clearInterval(interval)
  }, [])

  const payAndJump = async () => {
    if (!isConnected) {
      setTxStatus('❌ 请先连接钱包')
      return
    }

    setIsPaying(true)
    setTxStatus('⏳ 提交交易中...')

    const tollAmount = BigInt(treasury?.toll_amount ?? 50_000_000_000)
    const tx = new Transaction()

    // 分割出票价金额的 SUI
    const [paymentCoin] = tx.splitCoins(tx.gas, [
      tx.pure.u64(tollAmount)
    ])

    // 调用收费并获取 Permit
    tx.moveCall({
      target: `${TOLL_PACKAGE}::toll_gate_ext::pay_toll_and_get_permit`,
      arguments: [
        tx.object(SOURCE_GATE_ID),
        tx.object(DEST_GATE_ID),
        tx.object(CHARACTER_ID),
        tx.object(TREASURY_ID),
        paymentCoin,
        tx.object('0x6'), // Clock 系统对象
      ],
    })

    try {
      const result = await dAppKit.signAndExecuteTransaction({
        transaction: tx,
      })
      setTxStatus(`✅ 已获得跳跃许可！ Tx: ${result.digest.slice(0, 12)}...`)
      loadTreasury() // 刷新金库数据
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
      {/* 星门信息 */}
      <header className="gate-header">
        <div className="gate-icon">🌀</div>
        <div>
          <h1>{loading ? '...' : assembly?.name ?? '星门'}</h1>
          <span className={`status-badge ${assembly?.status?.toLowerCase()}`}>
            {assembly?.status ?? '检测中...'}
          </span>
        </div>
      </header>

      {/* 通行费信息 */}
      <section className="toll-info">
        <div className="info-card">
          <span className="label">💰 当前票价</span>
          <span className="value">{tollInSui} SUI</span>
        </div>
        <div className="info-card">
          <span className="label">🚀 累计跳跃</span>
          <span className="value">{treasury?.total_jumps ?? '...'} 次</span>
        </div>
        <div className="info-card">
          <span className="label">🏦 金库余额</span>
          <span className="value">{balanceInSui} SUI</span>
        </div>
      </section>

      {/* 跳跃操作 */}
      <section className="jump-section">
        {!isConnected ? (
          <button className="connect-btn" onClick={handleConnect}>
            🔗 连接 EVE Vault 钱包
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
              {isPaying ? '⏳ 处理中...' : `🛸 支付 ${tollInSui} SUI 并跃迁`}
            </button>
          </>
        )}

        {txStatus && (
          <div className={`tx-status ${txStatus.startsWith('✅') ? 'success' : 'error'}`}>
            {txStatus}
          </div>
        )}
      </section>

      {/* 目的地信息 */}
      <section className="destination-info">
        <p>📍 目的地：<strong>Alpha Centauri 矿区</strong></p>
        <p>⏱ 许可证有效期：<strong>15 分钟</strong></p>
      </section>
    </div>
  )
}
```

---

## 第三部分：Owner 管理面板

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
      setStatus(`✅ 已提取 ${withdrawAmount} SUI`)
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
      setStatus(`✅ 票价已更新为 ${newToll} SUI`)
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="owner-panel">
      <h2>⚙️ 收费站管理</h2>

      <div className="panel-section">
        <h3>💵 提取收入</h3>
        <p>金库余额：{(treasuryBalance / 1e9).toFixed(2)} SUI</p>
        <input
          type="number"
          value={withdrawAmount}
          onChange={e => setWithdrawAmount(e.target.value)}
          placeholder="提取金额（SUI）"
        />
        <button onClick={withdraw}>提取到钱包</button>
      </div>

      <div className="panel-section">
        <h3>🏷 调整票价</h3>
        <input
          type="number"
          value={newToll}
          onChange={e => setNewToll(e.target.value)}
          placeholder="新票价（SUI）"
        />
        <button onClick={updateToll}>更新票价</button>
      </div>

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 🎯 完整实现回顾

```
Move 合约层
├── treasury.move
│   ├── TollTreasury（共享金库对象）
│   ├── TreasuryOwnerCap（提款权凭证）
│   ├── deposit_toll()      ← 扩展调用
│   ├── withdraw()          ← Owner 调用
│   └── set_toll_amount()   ← Owner 调用
│
└── toll_gate_ext.move
    ├── TollAuth（Witness 类型）
    └── pay_toll_and_get_permit()  ← 玩家调用
        ├── 1. 验证并收费 → treasury.deposit_toll()
        └── 2. 颁发许可 → gate::issue_jump_permit()

dApp 层
├── TollGateApp.tsx       → 玩家购票界面
│   ├── 实时显示票价、跳跃次数、金库余额
│   └── 一键支付并获取 JumpPermit
└── OwnerPanel.tsx        → 管理员面板
    ├── 提取金库收入
    └── 调整票价
```

---

## 🔧 扩展练习

1. **等级会员制**：联盟成员持有会员 NFT 可享受折扣（检查 NFT 后应用不同票价）
2. **限时免费通道**：在特定时间段（如维护期）自动接受 0 LUX Permit
3. **收益分配**：金库收入自动按比例分配给多个联盟股东地址
4. **历史记录 dApp**：监听 `TollCollected` 事件，展示最近 50 次跳跃记录

---

## 📚 关联文档

- [Smart Gate 文档](../smart-assemblies/gate/README.md)
- [Interfacing with the World](../smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [Chapter 3：Move 资源与 Coin 模型](./chapter-03.md)
- [Chapter 5：dApp 发起链上交易](./chapter-05.md#55-执行链上交易)
- [builder-scaffold Smart Gate 示例](https://github.com/evefrontier/builder-scaffold/tree/main/move-contracts/smart_gate)
