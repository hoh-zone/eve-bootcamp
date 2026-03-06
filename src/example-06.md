# 实战案例 6：动态 NFT 装备系统（可进化的飞船武器）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 创建一套飞船武器 NFT，其属性随游戏战斗结果自动升级；利用 Sui Display 标准确保 NFT 在所有钱包和市场中实时显示最新状态。

---

> 状态：教学示例。正文聚焦动态 NFT 和 Display 更新，完整目录以 `book/src/code/example-06/` 为准。

## 前置依赖

- 建议先读 [Chapter 14](./chapter-14.md)
- 需要本地 `sui` CLI 与 `pnpm`

## 对应代码目录

- [example-06](./code/example-06)
- [example-06/dapp](./code/example-06/dapp)

## 源码位置

- [Move.toml](./code/example-06/Move.toml)
- [plasma_rifle.move](./code/example-06/sources/plasma_rifle.move)
- [turret_combat.move](./code/example-06/sources/turret_combat.move)
- [dapp/readme.md](./code/example-06/dapp/readme.md)

## 关键测试文件

- [tests/README.md](./code/example-06/tests/README.md)

## 推荐阅读顺序

1. 先看 `plasma_rifle.move` 的 NFT 状态
2. 再读战斗结果如何驱动升级
3. 最后启动 dApp 对照 Display 展示

## 最小调用链

`玩家持有武器 NFT -> 击杀事件累加 -> 达到阈值升级 -> Display 元数据更新 -> 钱包/市场显示新外观`

## 验证步骤

1. 在 [example-06](./code/example-06) 运行 `sui move build`
2. 在 [example-06/dapp](./code/example-06/dapp) 运行 `pnpm install && pnpm dev`
3. 按测试矩阵核对等级提升与 Display 刷新

## 常见报错

- 链上等级更新了，但 Display 元数据没有同步刷新
- 升级阈值判断写在前端而不是链上状态机里

---

## 需求分析

**场景：** 你设计了一款"成长型武器"系统——玩家获得一把 `PlasmaRifle`，初始是一把普通武器，随着每次击杀积累，自动升级外观和属性：

- ⚪ **初级（0-9 击杀）**：Plasma Rifle Mk.1，基础伤害
- 🔵 **精英（10-49 击杀）**：Plasma Rifle Mk.2，图片变为精英版本，伤害+30%
- 🟡 **传奇（50+ 击杀）**：Plasma Rifle Mk.3 "Inferno"，图片变为传奇版本，特殊效果

---

## 第一部分：NFT 合约

```move
module dynamic_nft::plasma_rifle;

use sui::object::{Self, UID};
use sui::display;
use sui::package;
use sui::transfer;
use sui::event;
use std::string::{Self, String, utf8};

// ── 一次性见证 ─────────────────────────────────────────────

public struct PLASMA_RIFLE has drop {}

// ── 武器等级常量 ───────────────────────────────────────────

const TIER_BASIC: u8 = 1;
const TIER_ELITE: u8 = 2;
const TIER_LEGENDARY: u8 = 3;

const KILLS_FOR_ELITE: u64 = 10;
const KILLS_FOR_LEGENDARY: u64 = 50;

// ── 数据结构 ───────────────────────────────────────────────

public struct PlasmaRifle has key, store {
    id: UID,
    name: String,
    tier: u8,
    kills: u64,
    damage_bonus_pct: u64,   // 伤害加成（百分比）
    image_url: String,
    description: String,
    owner_history: u64,      // 历史流通次数
}

public struct ForgeAdminCap has key, store {
    id: UID,
}

// ── 事件 ──────────────────────────────────────────────────

public struct RifleEvolved has copy, drop {
    rifle_id: ID,
    from_tier: u8,
    to_tier: u8,
    total_kills: u64,
}

// ── 初始化 ────────────────────────────────────────────────

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
        // attributes 拼接多个字段
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

// ── 铸造初始武器 ──────────────────────────────────────────

public entry fun forge_rifle(
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

// ── 记录击杀（炮塔扩展调用此函数）────────────────────────

public entry fun record_kill(
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

// ── 读取函数 ──────────────────────────────────────────────

public fun get_tier(rifle: &PlasmaRifle): u8 { rifle.tier }
public fun get_kills(rifle: &PlasmaRifle): u64 { rifle.kills }
public fun get_damage_bonus(rifle: &PlasmaRifle): u64 { rifle.damage_bonus_pct }

// ── 转让追踪（可选） ─────────────────────────────────────

// 如果使用 TransferPolicy，可以追踪转让次数
// 此处简化为通过事件监听实现
```

---

## 第二部分：炮塔扩展 — 战斗结果上报武器

```move
module dynamic_nft::turret_combat;

use dynamic_nft::plasma_rifle::{Self, PlasmaRifle};
use world::turret::{Self, Turret};
use world::character::Character;

public struct CombatAuth has drop {}

/// 炮塔击杀事件（炮塔扩展调用）
public entry fun on_kill(
    turret: &Turret,
    killer: &Character,
    weapon: &mut PlasmaRifle,       // 玩家使用的武器
    ctx: &TxContext,
) {
    // 验证是合法的炮塔扩展调用（需要 CombatAuth）
    turret::verify_extension(turret, CombatAuth {});

    // 记录击杀到武器
    plasma_rifle::record_kill(weapon, ctx);
}
```

---

## 第三部分：前端武器展示 dApp

```tsx
// src/WeaponDisplay.tsx
import { useState, useEffect } from 'react'
import { useSuiClient } from '@mysten/dapp-kit'
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
  '1': '#9CA3AF',  // 灰色（普通）
  '2': '#3B82F6',  // 蓝色（精英）
  '3': '#F59E0B',  // 金色（传奇）
}

const TIER_LABELS = { '1': 'Basic', '2': 'Elite', '3': 'Legendary' }

export function WeaponDisplay({ rifleId }: { rifleId: string }) {
  const client = useSuiClient()
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

  // 监听进化事件
  const evolutions = useRealtimeEvents<{
    rifle_id: string; from_tier: string; to_tier: string; total_kills: string
  }>(`${DYNAMIC_NFT_PKG}::plasma_rifle::RifleEvolved`)

  useEffect(() => {
    const myEvolution = evolutions.find(e => e.rifle_id === rifleId)
    if (myEvolution) {
      setJustEvolved(true)
      loadRifle() // 重新加载最新数据
      setTimeout(() => setJustEvolved(false), 5000)
    }
  }, [evolutions])

  if (!rifle) return <div className="loading">加载武器数据...</div>

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
          ✨ 武器已进化！
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
            <span>⚔️ 击杀数</span>
            <strong>{rifle.kills}</strong>
          </div>
          <div className="stat">
            <span>💥 伤害加成</span>
            <strong>+{rifle.damage_bonus_pct}%</strong>
          </div>
        </div>

        {killsForNextTier && (
          <div className="evolution-progress">
            <span>进化进度：{rifle.kills} / {killsForNextTier} 击杀</span>
            <div className="progress-bar">
              <div
                className="progress-fill"
                style={{ width: `${progress}%`, background: tierColor }}
              />
            </div>
          </div>
        )}

        {!killsForNextTier && (
          <div className="max-tier-badge">👑 已达最高等级</div>
        )}
      </div>
    </div>
  )
}
```

---

## 🎯 完整回顾

```
合约层
├── plasma_rifle.move
│   ├── PlasmaRifle（NFT 对象，字段随战斗更新）
│   ├── Display（模板引用字段 → 钱包自动同步显示）
│   ├── forge_rifle()    ← Owner 铸造发放
│   ├── record_kill()    ← 炮塔合约调用
│   └── check_and_evolve() ← 内部：检查阈值，升级字段 + 发事件
│
└── turret_combat.move
    └── on_kill()         ← 炮塔击杀时调用武器升级

dApp 层
└── WeaponDisplay.tsx
    ├── 订阅 RifleEvolved 事件（一旦进化立即刷新）
    ├── 动态颜色主题（按等级）
    └── 进化进度条
```

## 🔧 扩展练习

1. **武器磨损**：每次使用降低 `durability` 字段，质量下降后伤害减少（需要修理）
2. **特殊属性**：传奇等级随机获得特殊词缀（用随机数 + 动态字段）
3. **武器融合**：两把 Elite 武器销毁 → 铸造一把 Legendary（材料消耗型升级）

---

## 📚 关联文档

- [Chapter 14：NFT 设计与 Display 标准](./chapter-14.md)
- [Chapter 7：事件系统](./chapter-07.md)
- [Sui Display 文档](https://docs.sui.io/standards/display)
