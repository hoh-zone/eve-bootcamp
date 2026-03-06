# 实战案例 4：任务解锁系统（链上任务 + 条件星门）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 构建一套链上任务系统：玩家完成指定任务后，链上记录完成状态；星门扩展读取任务状态，只允许完成任务的玩家跃迁。同时提供任务发布和验证的 dApp。

---

> 状态：已映射到本地代码目录。正文以任务状态和条件星门解耦为核心，适合做权限型玩法入口。

## 前置依赖

- 建议先读 [Chapter 7](./chapter-07.md)、[Chapter 13](./chapter-13.md)
- 需要本地 `sui` CLI 与 `pnpm`

## 对应代码目录

- [example-04](./code/example-04)
- [example-04/dapp](./code/example-04/dapp)

## 源码位置

- [Move.toml](./code/example-04/Move.toml)
- [registry.move](./code/example-04/sources/registry.move)
- [quest_gate.move](./code/example-04/sources/quest_gate.move)
- [dapp/readme.md](./code/example-04/dapp/readme.md)

## 关键测试文件

- [tests/README.md](./code/example-04/tests/README.md)

## 推荐阅读顺序

1. 先看任务注册与状态存储
2. 再读星门如何读取任务完成状态
3. 最后启动 dApp 验证任务进度追踪

## 最小调用链

`注册任务 -> 玩家完成任务 -> 链上记录状态 -> 星门读取任务状态 -> 放行或拒绝`

## 验证步骤

1. 在 [example-04](./code/example-04) 运行 `sui move build`
2. 在 [example-04/dapp](./code/example-04/dapp) 运行 `pnpm install && pnpm dev`
3. 按测试矩阵验证任务完成和条件放行

## 常见报错

- 任务状态写在一个合约里，星门却读取另一份状态
- 前端显示完成，但链上状态未真正更新

---

## 需求分析

**场景：** 你运营着一个星门，通向一个高价值矿区。想要进入的玩家必须先完成一系列"入会考核"：

- 📋 **任务一**：向你的存储箱捐献 100 单位矿石（链上可验证）
- 🔑 **任务二**：获得联盟 Leader 的链上签发认证
- 🚪 **完成所有任务** → 可以通过星门进入矿区

**设计特点：**
- 任务状态全部在链上，无法伪造
- 任务系统和星门系统解耦，便于独立升级
- dApp 提供任务进度追踪和一键申请跃迁

---

## 第一部分：任务系统合约

### `quest_registry.move`

```move
module quest_system::registry;

use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::event;
use sui::tx_context::TxContext;
use sui::transfer;

/// 任务的类型（用 u8 枚举）
const QUEST_DONATE_ORE: u8 = 0;
const QUEST_LEADER_CERT: u8 = 1;

/// 任务完成状态（位标志）
/// bit 0: QUEST_DONATE_ORE 完成
/// bit 1: QUEST_LEADER_CERT 完成
const QUEST_ALL_COMPLETE: u64 = 0b11;

/// 任务注册表（共享对象）
public struct QuestRegistry has key {
    id: UID,
    gate_id: ID,                          // 对应哪个星门
    completions: Table<address, u64>,     // address → 完成标志位
}

/// 任务管理员凭证
public struct QuestAdminCap has key, store {
    id: UID,
    registry_id: ID,
}

/// 事件
public struct QuestCompleted has copy, drop {
    registry_id: ID,
    player: address,
    quest_type: u8,
    all_done: bool,
}

/// 部署：创建任务注册表
public entry fun create_registry(
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

/// 管理员标记任务完成（由联盟 Leader 或管理脚本调用）
public entry fun mark_quest_complete(
    registry: &mut QuestRegistry,
    cap: &QuestAdminCap,
    player: address,
    quest_type: u8,
    ctx: &TxContext,
) {
    assert!(cap.registry_id == object::id(registry), ECapMismatch);

    // 初始化玩家条目
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

/// 查询玩家是否完成了所有任务
public fun is_all_complete(registry: &QuestRegistry, player: address): bool {
    if !table::contains(&registry.completions, player) {
        return false
    }
    *table::borrow(&registry.completions, player) == QUEST_ALL_COMPLETE
}

/// 查询玩家完成了哪些任务
public fun get_completion_flags(registry: &QuestRegistry, player: address): u64 {
    if !table::contains(&registry.completions, player) {
        return 0
    }
    *table::borrow(&registry.completions, player)
}

const ECapMismatch: u64 = 0;
```

---

### `quest_gate.move`（星门扩展）

```move
module quest_system::quest_gate;

use quest_system::registry::{Self, QuestRegistry};
use world::gate::{Self, Gate};
use world::character::Character;
use sui::clock::Clock;
use sui::tx_context::TxContext;

/// 星门扩展 Witness
public struct QuestGateAuth has drop {}

/// 任务完成后申请跳跃许可
public entry fun quest_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    quest_registry: &QuestRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 验证调用者已完成所有任务
    assert!(
        registry::is_all_complete(quest_registry, ctx.sender()),
        EQuestsNotComplete,
    );

    // 签发跳跃许可（有效期 30 分钟）
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

## 第二部分：任务验证逻辑（任务一：捐献矿石）

任务一（捐献矿石）需要链下监控 SSU 的存储事件，然后管理员手动（或脚本自动）标记完成。

```typescript
// scripts/auto-quest-monitor.ts
import { SuiClient } from "@mysten/sui/client"
import { Transaction } from "@mysten/sui/transactions"
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519"

const QUEST_PACKAGE = "0x_QUEST_PACKAGE_"
const REGISTRY_ID = "0x_REGISTRY_ID_"
const QUEST_ADMIN_CAP_ID = "0x_QUEST_ADMIN_CAP_"
const STORAGE_UNIT_ID = "0x_SSU_ID_"
const DONATE_ORE_TYPE_ID = 12345 // 矿石物品类型 ID

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" })
const adminKeypair = Ed25519Keypair.fromSecretKey(/* ... */)

// 监听 SSU 的捐献事件
async function monitorDonations() {
  await client.subscribeEvent({
    filter: {
      MoveEventType: `${"0x_WORLD_PACKAGE_"}::storage_unit::ItemDeposited`,
    },
    onMessage: async (event) => {
      const { depositor, storage_unit_id, item_type_id } = event.parsedJson as any

      // 检查是否是我们的 SSU 和指定物品
      if (
        storage_unit_id === STORAGE_UNIT_ID &&
        Number(item_type_id) === DONATE_ORE_TYPE_ID
      ) {
        console.log(`玩家 ${depositor} 捐献了矿石，标记任务完成...`)
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
  console.log(`任务标记成功: ${result.digest}`)
}

monitorDonations()
```

---

## 第三部分：任务追踪 dApp

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
  { id: 0, name: '捐献矿石', description: '向联盟存储箱存入 100 单位矿石' },
  { id: 1, name: '获得认证', description: '联系联盟 Leader 在链上为你签发认证' },
]

export function QuestTrackerApp() {
  const { isConnected, handleConnect, currentAddress } = useConnection()
  const dAppKit = useDAppKit()
  const [flags, setFlags] = useState<number>(0)
  const [isJumping, setIsJumping] = useState(false)
  const [status, setStatus] = useState('')

  const allComplete = flags === 0b11

  // 加载任务完成状态
  useEffect(() => {
    if (!currentAddress) return

    const loadFlags = async () => {
      // 通过 GraphQL 读取 table 中的玩家条目
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
        setFlags(0) // 玩家尚未有记录
      }
    }

    loadFlags()
  }, [currentAddress])

  const handleJump = async () => {
    if (!allComplete) {
      setStatus('❌ 请先完成所有任务')
      return
    }

    setIsJumping(true)
    setStatus('⏳ 申请跳跃许可...')

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
      setStatus('🚀 已获得跳跃许可，享受矿区之旅！')
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    } finally {
      setIsJumping(false)
    }
  }

  return (
    <div className="quest-tracker">
      <h1>🌟 联盟入会考核</h1>

      {!isConnected ? (
        <button onClick={handleConnect}>连接钱包</button>
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
            完成进度：{Object.keys(QUEST_NAMES)
              .filter(i => (flags & (1 << Number(i))) !== 0).length} / {QUEST_NAMES.length}
          </div>

          <button
            className={`jump-btn ${allComplete ? 'active' : 'locked'}`}
            onClick={handleJump}
            disabled={!allComplete || isJumping}
          >
            {allComplete
              ? (isJumping ? '⏳ 申请中...' : '🚀 进入矿区')
              : '🔒 完成所有任务才可进入'
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

## 🎯 完整回顾

```
合约层
├── quest_registry.move
│   ├── QuestRegistry（共享对象，存储玩家完成标志位）
│   ├── QuestAdminCap（管理员凭证）
│   ├── mark_quest_complete() ← 管理员调用
│   └── is_all_complete()     ← 星门合约调用
│
└── quest_gate.move
    ├── QuestGateAuth（星门扩展 Witness）
    └── quest_jump()          ← 玩家调用
        ├── registry::is_all_complete() → 验证任务完成
        └── gate::issue_jump_permit()   → 发放许可

链下监控
└── auto-quest-monitor.ts
    ├── 订阅 SSU ItemDeposited 事件
    └── 自动调用 mark_quest_complete()

dApp 层
└── QuestTrackerApp.tsx
    ├── 显示任务进度（位标志解码）
    └── 一键申请跳跃许可
```

---

## 🔧 扩展练习

1. **任务时效**：任务完成后 7 天内有效，过期需重新完成（在标志位旁存储时间戳）
2. **链上任务一**（不需要链下）：玩家主动调用 `donate_ore()` 函数，直接转移物品，合约自动标记任务完成
3. **任务积分**：每个任务赋予不同积分权重，累计达到阈值才解锁星门

---

## 📚 关联文档

- [Chapter 6：OwnerCap 与 Keychain](./chapter-06.md)
- [Chapter 7：位标志与 Table](./chapter-07.md)
- [Smart Gate 文档](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/gate/README.md)
