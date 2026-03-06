# 实战案例 10：太空资源争夺战（综合实战）

> ⏱ 预计练习时间：2 小时（建议分两次进行）
>
> **目标：** 整合本课程所有知识，构建一个微型完整游戏：两个联盟争夺一片矿区的控制权，包含炮塔攻防、星门收费、物品存储、代币奖励和实时战报 dApp。

---

> 状态：综合案例。正文整合多个模块，是检验你是否真正把全书前半段串起来的最好案例。

## 前置依赖

- 建议先读 [Chapter 16](./chapter-16.md)、[Chapter 18](./chapter-18.md)、[Chapter 23](./chapter-23.md)
- 需要本地 `sui` CLI 与 `pnpm`

## 对应代码目录

- [example-10](./code/example-10)
- [example-10/dapp](./code/example-10/dapp)

## 源码位置

- [Move.toml](./code/example-10/Move.toml)
- [faction_nft.move](./code/example-10/sources/faction_nft.move)
- [faction_gate.move](./code/example-10/sources/faction_gate.move)
- [mining_depot.move](./code/example-10/sources/mining_depot.move)
- [war_token.move](./code/example-10/sources/war_token.move)
- [dapp/readme.md](./code/example-10/dapp/readme.md)

## 关键测试文件

- [tests/README.md](./code/example-10/tests/README.md)

## 推荐阅读顺序

1. 先看四个合约模块分别负责什么
2. 再画出矿区争夺战的状态流
3. 最后启动 dApp 对照全局战场面板

## 最小调用链

`发放势力 NFT -> 星门/炮塔按势力校验 -> 玩家采矿获奖 -> WAR Token 发放 -> dApp 展示战况`

## 验证步骤

1. 在 [example-10](./code/example-10) 运行 `sui move build`
2. 在 [example-10/dapp](./code/example-10/dapp) 运行 `pnpm install && pnpm dev`
3. 按测试矩阵逐项核对势力校验、采矿奖励与资源刷新

## 常见报错

- 多个模块状态更新不在同一事务里，导致战况面板和链上状态飘移
- 前端把“势力归属”当作缓存字段，而不是链上可查询状态

---

## 项目全景

```
┌─────────────────────────────────────────────┐
│              太空资源争夺战                    │
│                                             │
│    联盟 A                   联盟 B           │
│    Territory (炮塔 ×2)      Territory (炮塔 ×2)│
│         ↑                       ↑           │
│    ┌─[Gate A1]─── 中立矿区 ───[Gate B1]─┐   │
│    │           (存储箱 + 资源)           │   │
│    └─────────────────────────────────────┘  │
│                                             │
│  战斗规则：                                  │
│  • 进入中立矿区需要通过对方炮塔检查           │
│  • 持有"势力 NFT"才能通过己方星门            │
│  • 矿区资源每小时刷新，先到先得              │
│  • 每次采矿获得 WAR Token（联盟代币）        │
└─────────────────────────────────────────────┘
```

---

## 合约架构设计

```
war_game/
├── Move.toml
└── sources/
    ├── faction_nft.move    # 势力 NFT（加入联盟的凭证）
    ├── war_token.move      # WAR Token（战争代币）
    ├── faction_gate.move   # 星门扩展（势力检查）
    ├── faction_turret.move # 炮塔扩展（enemy 检测）
    ├── mining_depot.move   # 矿区存储箱扩展（资源采集）
    └── war_registry.move   # 游戏注册表（全局状态）
```

---

## 第一部分：核心合约

### `faction_nft.move`

```move
module war_game::faction_nft;

use sui::object::{Self, UID};
use sui::transfer;
use std::string::{Self, String, utf8};

public struct FACTION_NFT has drop {}

/// 势力枚举
const FACTION_ALPHA: u8 = 0;
const FACTION_BETA: u8 = 1;

/// 势力 NFT（入盟证明）
public struct FactionNFT has key, store {
    id: UID,
    faction: u8,                // 0 = Alpha, 1 = Beta
    member_since_ms: u64,
    name: String,
}

public struct WarAdminCap has key, store { id: UID }

public entry fun enlist(
    _admin: &WarAdminCap,
    faction: u8,
    member_name: vector<u8>,
    recipient: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction == FACTION_ALPHA || faction == FACTION_BETA, EInvalidFaction);
    let nft = FactionNFT {
        id: object::new(ctx),
        faction,
        member_since_ms: clock.timestamp_ms(),
        name: utf8(member_name),
    };
    transfer::public_transfer(nft, recipient);
}

public fun get_faction(nft: &FactionNFT): u8 { nft.faction }
public fun is_alpha(nft: &FactionNFT): bool { nft.faction == FACTION_ALPHA }
public fun is_beta(nft: &FactionNFT): bool { nft.faction == FACTION_BETA }

const EInvalidFaction: u64 = 0;
```

### `war_token.move`

```move
module war_game::war_token;

/// WAR Token（标准 Coin 设计，参考 Chapter 8）
public struct WAR_TOKEN has drop {}

fun init(witness: WAR_TOKEN, ctx: &mut TxContext) {
    let (treasury, metadata) = sui::coin::create_currency(
        witness, 6, b"WAR", b"War Token",
        b"Earned through combat and mining in the Space Resource War",
        option::none(), ctx,
    );
    transfer::public_transfer(treasury, ctx.sender());
    transfer::public_freeze_object(metadata);
}
```

### `faction_gate.move`（星门扩展）

```move
module war_game::faction_gate;

use war_game::faction_nft::{Self, FactionNFT};
use world::gate::{Self, Gate};
use world::character::Character;
use sui::clock::Clock;
use sui::tx_context::TxContext;

public struct AlphaGateAuth has drop {}
public struct BetaGateAuth has drop {}

/// Alpha 联盟星门：只允许 Alpha 成员通过
public entry fun alpha_gate_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    faction_nft: &FactionNFT,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction_nft::is_alpha(faction_nft), EWrongFaction);
    gate::issue_jump_permit(
        source_gate, dest_gate, character, AlphaGateAuth {},
        clock.timestamp_ms() + 30 * 60 * 1000, ctx,
    );
}

/// Beta 联盟星门
public entry fun beta_gate_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    faction_nft: &FactionNFT,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction_nft::is_beta(faction_nft), EWrongFaction);
    gate::issue_jump_permit(
        source_gate, dest_gate, character, BetaGateAuth {},
        clock.timestamp_ms() + 30 * 60 * 1000, ctx,
    );
}

const EWrongFaction: u64 = 0;
```

### `mining_depot.move`（矿区核心）

```move
module war_game::mining_depot;

use war_game::faction_nft::{Self, FactionNFT};
use war_game::war_token::WAR_TOKEN;
use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use sui::coin::{Self, TreasuryCap};
use sui::clock::Clock;
use sui::object::{Self, UID};
use sui::event;

public struct MiningAuth has drop {}

/// 矿区状态
public struct MiningDepot has key {
    id: UID,
    resource_count: u64,       // 当前可采数量
    last_refresh_ms: u64,      // 上次刷新时间
    refresh_amount: u64,       // 每次刷新补充量
    refresh_interval_ms: u64,  // 刷新间隔
    alpha_total_mined: u64,
    beta_total_mined: u64,
}

public struct ResourceMined has copy, drop {
    miner: address,
    faction: u8,
    amount: u64,
    faction_total: u64,
}

/// 采矿（同时检查势力 NFT 并发放 WAR Token 奖励）
public entry fun mine(
    depot: &mut MiningDepot,
    storage_unit: &mut StorageUnit,
    character: &Character,
    faction_nft: &FactionNFT,       // 需要势力认证
    war_treasury: &mut TreasuryCap<WAR_TOKEN>,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 自动刷新资源
    maybe_refresh(depot, clock);

    assert!(amount > 0 && amount <= depot.resource_count, EInsufficientResource);

    depot.resource_count = depot.resource_count - amount;

    // 根据势力更新统计
    let faction = faction_nft::get_faction(faction_nft);
    if faction == 0 {
        depot.alpha_total_mined = depot.alpha_total_mined + amount;
    } else {
        depot.beta_total_mined = depot.beta_total_mined + amount;
    };

    // 取出资源（从 SSU）
    // storage_unit::withdraw_batch(storage_unit, character, MiningAuth {}, RESOURCE_TYPE_ID, amount, ctx)

    // 发放 WAR Token 奖励（每单位资源 = 10 WAR）
    let war_reward = amount * 10_000_000; // 10 WAR per unit，6 decimals
    let war_coin = sui::coin::mint(war_treasury, war_reward, ctx);
    sui::transfer::public_transfer(war_coin, ctx.sender());

    event::emit(ResourceMined {
        miner: ctx.sender(),
        faction,
        amount,
        faction_total: if faction == 0 { depot.alpha_total_mined } else { depot.beta_total_mined },
    });
}

fun maybe_refresh(depot: &mut MiningDepot, clock: &Clock) {
    let now = clock.timestamp_ms();
    if now >= depot.last_refresh_ms + depot.refresh_interval_ms {
        depot.resource_count = depot.resource_count + depot.refresh_amount;
        depot.last_refresh_ms = now;
    }
}

const EInsufficientResource: u64 = 0;
```

---

## 第二部分：战报实时 dApp

```tsx
// src/WarDashboard.tsx
import { useState, useEffect } from 'react'
import { useRealtimeEvents } from './hooks/useRealtimeEvents'
import { useSuiClient } from '@mysten/dapp-kit'
import { useConnection } from '@evefrontier/dapp-kit'

const WAR_PKG = "0x_WAR_PACKAGE_"
const DEPOT_ID = "0x_DEPOT_ID_"

interface DepotState {
  resource_count: string
  alpha_total_mined: string
  beta_total_mined: string
  last_refresh_ms: string
}

interface MiningEvent {
  miner: string
  faction: string
  amount: string
  faction_total: string
}

const FACTION_COLOR = { '0': '#3B82F6', '1': '#EF4444' } // Alpha=蓝, Beta=红
const FACTION_NAME = { '0': 'Alpha 联盟', '1': 'Beta 联盟' }

export function WarDashboard() {
  const { isConnected, currentAddress } = useConnection()
  const client = useSuiClient()
  const [depot, setDepot] = useState<DepotState | null>(null)
  const [nextRefreshIn, setNextRefreshIn] = useState(0)

  // 加载矿区状态
  const loadDepot = async () => {
    const obj = await client.getObject({ id: DEPOT_ID, options: { showContent: true } })
    if (obj.data?.content?.dataType === 'moveObject') {
      setDepot(obj.data.content.fields as DepotState)
    }
  }

  useEffect(() => { loadDepot() }, [])

  // 刷新倒计时
  useEffect(() => {
    if (!depot) return
    const timer = setInterval(() => {
      const refreshInterval = 60 * 60 * 1000 // 1小时
      const nextRefresh = Number(depot.last_refresh_ms) + refreshInterval
      setNextRefreshIn(Math.max(0, nextRefresh - Date.now()))
    }, 1000)
    return () => clearInterval(timer)
  }, [depot])

  // 实时战报
  const miningEvents = useRealtimeEvents<MiningEvent>(
    `${WAR_PKG}::mining_depot::ResourceMined`,
    { maxEvents: 20 }
  )

  useEffect(() => {
    if (miningEvents.length > 0) loadDepot() // 有采矿事件就刷新矿区状态
  }, [miningEvents])

  // 计算领土控制百分比
  const alpha = Number(depot?.alpha_total_mined ?? 0)
  const beta = Number(depot?.beta_total_mined ?? 0)
  const total = alpha + beta
  const alphaPct = total > 0 ? Math.round(alpha * 100 / total) : 50

  return (
    <div className="war-dashboard">
      <h1>⚔️ 太空资源争夺战</h1>

      {/* 势力控制率 */}
      <section className="control-bar-section">
        <div className="control-labels">
          <span style={{ color: FACTION_COLOR['0'] }}>
            Alpha {alphaPct}%
          </span>
          <span style={{ color: FACTION_COLOR['1'] }}>
            {100 - alphaPct}% Beta
          </span>
        </div>
        <div className="control-bar">
          <div
            className="alpha-bar"
            style={{ width: `${alphaPct}%`, background: FACTION_COLOR['0'] }}
          />
        </div>
      </section>

      {/* 矿区状态 */}
      <section className="depot-status">
        <div className="stat-card">
          <span>⛏ 剩余资源</span>
          <strong>{depot?.resource_count ?? '-'}</strong>
        </div>
        <div className="stat-card">
          <span>⏳ 下次刷新</span>
          <strong>{Math.ceil(nextRefreshIn / 60000)} 分钟</strong>
        </div>
        <div className="stat-card alpha">
          <span style={{ color: FACTION_COLOR['0'] }}>Alpha 采矿总量</span>
          <strong>{depot?.alpha_total_mined ?? '-'}</strong>
        </div>
        <div className="stat-card beta">
          <span style={{ color: FACTION_COLOR['1'] }}>Beta 采矿总量</span>
          <strong>{depot?.beta_total_mined ?? '-'}</strong>
        </div>
      </section>

      {/* 实时战报 */}
      <section className="battle-log">
        <h3>📡 实时战报</h3>
        {miningEvents.length === 0 ? (
          <p className="quiet">矿区沉寂中...</p>
        ) : (
          <ul>
            {miningEvents.map((e, i) => (
              <li
                key={i}
                style={{ borderLeftColor: FACTION_COLOR[e.faction as '0' | '1'] }}
              >
                <span className="faction-tag" style={{ color: FACTION_COLOR[e.faction as '0' | '1'] }}>
                  [{FACTION_NAME[e.faction as '0' | '1']}]
                </span>
                {e.miner.slice(0, 8)}... 采集了 {e.amount} 单位资源
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
```

---

## 完整部署流程

```bash
# 1. 编译并发布合约
cd war_game
sui move build
sui client publish --gas-budget 200000000

# 2. 初始化游戏对象
# 运行 scripts/init-game.ts：创建 MiningDepot、注册星门/炮塔扩展

# 3. 测试角色入盟
# scripts/enlist-player.ts：给测试玩家发放 FactionNFT

# 4. 启动 dApp
cd dapp
npm run dev
```

---

## 🎯 知识综合运用

| 本课程知识点 | 在本例的应用 |
|-----------|-----------|
| Chapter 3：Witness 模式 | `MiningAuth`, `AlphaGateAuth`, `BetaGateAuth` |
| Chapter 4：组件扩展注册 | 炮塔 + 星门 + 存储箱均有独立扩展 |
| Chapter 5：dApp + Hooks | `useRealtimeEvents` 驱动战报实时更新 |
| Chapter 6：OwnerCap | 联盟 Leader 持有各组件的 OwnerCap |
| Chapter 7：事件系统 | `ResourceMined` 事件驱动 dApp |
| Chapter 8：代币经济 | WAR Token 作为采矿奖励 |
| Chapter 9：安全审计 | 权限验证 + 资源不超量扣减 |
| Chapter 10：发布流程 | 多合约同时发布 + 初始化脚本 |
| Chapter 11：赞助交易 | 炮塔攻击验证需服务器签名 |
| Chapter 12：GraphQL | 实时查询矿区和战役状态 |
| Chapter 13：跨合约 | mining_depot 调用 faction_nft 的只读视图 |
| Chapter 14：NFT | FactionNFT 的 Display 展示势力信息 |

---

## 🔧 进阶挑战

1. **联盟驱逐**：Leader 可以将不活跃成员的 FactionNFT 撤销（转回 Admin 或销毁）
2. **资源市场**：在矿区附近部署 SSU，玩家可以把挖到的资源卖回给联盟换取更多 WAR Token
3. **战争结算**：7 天后，采矿总量领先的联盟自动获得奖池，合约自动结算分红

---

## 🎓 恭喜！你已完成所有实战案例

至此，你已经：
- ✅ 用 Move 从头编写了 10 种不同类型的合约
- ✅ 构建了 10 个完整的前端 dApp
- ✅ 掌握了从 NFT、市场到 DAO、竞赛的完整技术栈
- ✅ 理解了链上与链下的协同设计模式

**你现在具备了在 EVE Frontier 中构建完整商业产品的所有技术能力。**

---

## 📚 全课程关联文档

- [EVE Frontier 官方文档](https://github.com/evefrontier/builder-documentation)
- [Sui 开发者文档](https://docs.sui.io)
- [Move Book](https://move-book.com)
- [builder-scaffold](https://github.com/evefrontier/builder-scaffold)
