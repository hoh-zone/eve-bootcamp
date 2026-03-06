# 实战案例 16：NFT 合成与拆解系统

> ⏱ 预计练习时间：2 小时
>
> **目标：** 构建材料合成系统——销毁多个低级 NFT 合成一个高级 NFT（概率性），也支持高级 NFT 拆解为材料；利用链上随机数确保结果公平。

---

## 需求分析

**场景：** 你设计了三层装备体系：

- **材料碎片**（Fragment）：普通，随机掉落
- **精炼组件**（Component）：3 个碎片 → 60% 概率合成
- **传世神器**（Artifact）：3 个精炼组件 → 30% 概率合成，失败返回 1 个组件

---

## 合约

```move
module crafting::forge;

use sui::object::{Self, UID, ID};
use sui::random::{Self, Random};
use sui::transfer;
use sui::event;
use std::string::{Self, String, utf8};

// ── 常量 ──────────────────────────────────────────────────

const TIER_FRAGMENT: u8 = 0;
const TIER_COMPONENT: u8 = 1;
const TIER_ARTIFACT: u8 = 2;

// 合成成功率（BPS）
const FRAGMENT_TO_COMPONENT_BPS: u64 = 6_000; // 60%
const COMPONENT_TO_ARTIFACT_BPS: u64 = 3_000; // 30%

// ── 数据结构 ───────────────────────────────────────────────

public struct ForgeItem has key, store {
    id: UID,
    tier: u8,
    name: String,
    image_url: String,
    power: u64,    // 属性值（越高级越强）
}

public struct ForgeAdminCap has key, store { id: UID }

// ── 事件 ──────────────────────────────────────────────────

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

// ── 初始化 ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::public_transfer(ForgeAdminCap { id: object::new(ctx) }, ctx.sender());
}

/// 铸造基础碎片（Admin only，比如任务奖励）
public entry fun mint_fragment(
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

// ── 合成：3 个低级 → 1 个高级（带随机成功率）────────────

public entry fun craft(
    input1: ForgeItem,
    input2: ForgeItem,
    input3: ForgeItem,
    random: &Random,
    ctx: &mut TxContext,
) {
    // 三个输入必须同一阶段
    assert!(input1.tier == input2.tier && input2.tier == input3.tier, EMismatchedTier);
    let input_tier = input1.tier;
    assert!(input_tier < TIER_ARTIFACT, EMaxTierReached);

    let target_tier = input_tier + 1;

    // 获取链上随机数（0-9999）
    let mut rng = random::new_generator(random, ctx);
    let roll = rng.generate_u64() % 10_000;

    let success_threshold = if target_tier == TIER_COMPONENT {
        FRAGMENT_TO_COMPONENT_BPS
    } else {
        COMPONENT_TO_ARTIFACT_BPS
    };

    // 无论成功与否，都销毁三个输入
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
        // 合成神器失败时，安慰奖：返还 1 个精炼组件
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
    // 合成组件失败时不返还任何东西（60% 成功率，风险在于玩家）

    event::emit(CraftAttempted {
        crafter: ctx.sender(),
        input_tier,
        success,
        result_tier: if success { target_tier } else { input_tier },
    });
}

// ── 拆解：1 个高级 → 多个低级 ────────────────────────────

public entry fun disassemble(
    item: ForgeItem,
    ctx: &mut TxContext,
) {
    assert!(item.tier > TIER_FRAGMENT, ECannotDisassembleFragment);

    let target_tier = item.tier - 1;
    let fragments_to_return = 2u64; // 拆解只返还 2 个（有损耗）
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

## dApp（铸造台界面）

```tsx
// ForgingStation.tsx
import { useState } from 'react'
import { useSuiClient, useCurrentAccount } from '@mysten/dapp-kit'
import { useQuery } from '@tanstack/react-query'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const CRAFTING_PKG = "0x_CRAFTING_PACKAGE_"
const TIER_NAMES = ['💎 碎片', '⚙️ 精炼组件', '🌟 传世神器']
const CRAFT_RATES = ['60%', '30%', '—']

export function ForgingStation() {
  const client = useSuiClient()
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
        tx.object('0x8'), // Random 系统对象
      ],
    })
    try {
      setStatus('⏳ 合成中（链上随机数判定）...')
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      // 从事件读取合成结果
      const craftEvent = result.events?.find(e => e.type.includes('CraftAttempted'))
      if (craftEvent) {
        const { success, result_tier } = craftEvent.parsedJson as any
        setLastCraft({ success, tier: TIER_NAMES[Number(result_tier)] })
        setStatus(success ? `✅ 合成成功！获得 ${TIER_NAMES[Number(result_tier)]}` : '❌ 合成失败')
      }
      setSelected([])
      refetch()
    } catch (e: any) { setStatus(`❌ ${e.message}`) }
  }

  const selectedTier = selected.length > 0 && userItems
    ? userItems.find(i => i.id === selected[0])?.tier
    : null

  return (
    <div className="forging-station">
      <h1>⚒ 神秘铸造台</h1>

      {lastCraft && (
        <div className={`craft-result ${lastCraft.success ? 'success' : 'fail'}`}>
          {lastCraft.success ? '✨ 合成成功！' : '💔 合成失败'} → {lastCraft.tier}
        </div>
      )}

      <div className="craft-info">
        <div>碎片 × 3 → 精炼组件（成功率 {CRAFT_RATES[0]}）</div>
        <div>精炼组件 × 3 → 传世神器（成功率 {CRAFT_RATES[1]}）</div>
      </div>

      <h3>选择 3 件同阶物品进行合成</h3>
      <div className="items-grid">
        {userItems?.map(item => (
          <div
            key={item.id}
            className={`item-slot ${selected.includes(item.id) ? 'selected' : ''}`}
            onClick={() => toggleSelect(item.id)}
          >
            <div className="tier-badge">{TIER_NAMES[item.tier]}</div>
            <div className="power">⚡ {item.power}</div>
          </div>
        ))}
      </div>

      <button
        className="craft-btn"
        disabled={selected.length !== 3}
        onClick={handleCraft}
      >
        🔥 开始合成（{selected.length}/3 已选）
      </button>

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 📚 关联文档
- [Sui 链上随机数](https://docs.sui.io/guides/developer/advanced/randomness-onchain)
- [Chapter 14：NFT 设计](./chapter-14.md)
- [Chapter 20：未来展望](./chapter-20.md)
