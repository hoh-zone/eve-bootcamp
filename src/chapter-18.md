# Chapter 18：多租户架构与游戏服务器集成

> **目标：** 理解 EVE Frontier 的多租户（Multi-tenant）世界合约设计，掌握如何构建可服务多个联盟的平台型合约，以及如何与游戏服务器双向集成。

---

> 状态：架构章节。正文以多租户设计和 Registry 模式为主。

##  18.1 什么是多租户合约？

**单租户**：一个合约只服务于一个 Owner（你的联盟）。

**多租户**：一个合约部署后，可以同时服务多个不相关的 Owner（多个联盟），彼此数据隔离。

```
单租户例子（Example 1-5 的模式）：
  合约 → 专属 TollGate（只有你的星门）

多租户例子：
  合约 → 注册 Alliance A 的星门收费配置
        → 注册 Alliance B 的星门收费配置
        → 注册 Alliance C 的存储箱市场配置
        →（每个联盟彼此隔离，数据独立）
```

**适用场景**：打造一个可供多个联盟使用的"SaaS"级工具。例如：通用拍卖平台、版税市场基础设施、任务系统框架。

多租户这件事最容易被误解成“把很多用户塞进一个合约”。真正要解决的问题其实是：

> 如何让很多彼此不信任的经营者，共享同一套协议能力，但又互不串线、互不越权、互不污染数据。

所以多租户设计的核心不是“省部署次数”，而是三件事：

- **隔离**
  A 租户不能碰 B 租户状态
- **复用**
  同一套逻辑不必为每个联盟重新发一遍包
- **可运营**
  平台方自己还能持续维护、升级和计费

---

##  18.2 多租户合约设计模式

```move
module platform::multi_toll;

use sui::table::{Self, Table};
use sui::object::{Self, ID};

/// 平台注册表（共享对象，所有租户共用）
public struct TollPlatform has key {
    id: UID,
    registrations: Table<ID, TollConfig>,  // gate_id → 收费配置
}

/// 每个租户（星门）的独立配置
public struct TollConfig has store {
    owner: address,          // 这个配置的 Owner（星门拥有者）
    toll_amount: u64,
    fee_recipient: address,
    total_collected: u64,
}

/// 租户注册（任意 Builder 都可以把自己的星门注册进来）
public entry fun register_gate(
    platform: &mut TollPlatform,
    gate: &Gate,
    owner_cap: &OwnerCap<Gate>,          // 证明你是这个星门的 Owner
    toll_amount: u64,
    fee_recipient: address,
    ctx: &TxContext,
) {
    // 验证 OwnerCap 和 Gate 对应
    assert!(owner_cap.authorized_object_id == object::id(gate), ECapMismatch);

    let gate_id = object::id(gate);
    assert!(!table::contains(&platform.registrations, gate_id), EAlreadyRegistered);

    table::add(&mut platform.registrations, gate_id, TollConfig {
        owner: ctx.sender(),
        toll_amount,
        fee_recipient,
        total_collected: 0,
    });
}

/// 调整租户配置（只有自己的配置才能修改）
public entry fun update_toll(
    platform: &mut TollPlatform,
    gate: &Gate,
    owner_cap: &OwnerCap<Gate>,
    new_toll_amount: u64,
    ctx: &TxContext,
) {
    assert!(owner_cap.authorized_object_id == object::id(gate), ECapMismatch);

    let config = table::borrow_mut(&mut platform.registrations, object::id(gate));
    assert!(config.owner == ctx.sender(), ENotConfigOwner);

    config.toll_amount = new_toll_amount;
}

/// 多租户跳跃（收费逻辑复用，但配置各自独立）
public entry fun multi_tenant_jump(
    platform: &mut TollPlatform,
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 读取该星门的专属收费配置
    let gate_id = object::id(source_gate);
    assert!(table::contains(&platform.registrations, gate_id), EGateNotRegistered);

    let config = table::borrow_mut(&mut platform.registrations, gate_id);
    assert!(coin::value(&payment) >= config.toll_amount, EInsufficientPayment);

    // 转给各自的 fee_recipient
    let toll = payment.split(config.toll_amount, ctx);
    transfer::public_transfer(toll, config.fee_recipient);
    config.total_collected = config.total_collected + config.toll_amount;

    // 还回找零
    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    // 发放跳跃许可
    gate::issue_jump_permit(
        source_gate, dest_gate, character, MultiTollAuth {}, clock.timestamp_ms() + 15 * 60 * 1000, ctx,
    );
}

public struct MultiTollAuth has drop {}
const ECapMismatch: u64 = 0;
const EAlreadyRegistered: u64 = 1;
const ENotConfigOwner: u64 = 2;
const EGateNotRegistered: u64 = 3;
const EInsufficientPayment: u64 = 4;
```

### 多租户设计真正要先决定的，是“租户键”是什么

在这个例子里，`gate_id` 充当租户边界。现实里常见的租户键还有：

- 某个 `assembly_id`
- 某个 `character_id`
- 某个联盟对象 ID
- 某个经过规范化的业务主键

这个选择非常关键，因为它决定了：

- 数据如何隔离
- 权限如何校验
- 前端和索引层如何检索

如果租户键选得不稳定，后面你会频繁遇到“这到底算一个租户还是两个”的脏边界问题。

### 多租户合约最常见的三类事故

#### 1. 隔离做得不彻底

看起来是多租户，实际某些路径仍然用全局共享参数，导致不同联盟之间互相影响。

#### 2. 平台参数和租户参数混在一起

结果是：

- 有些配置本来应该全局统一
- 却被某个租户私自改了

或者反过来：

- 本来应该每租户独立的费率
- 却被做成全局唯一值

#### 3. 查询模型没跟上

链上写了多租户结构，但前端和索引层仍然只会按“单对象”思路读取，最后平台根本不好用。

---

##  18.3 游戏服务器集成模式

### 模式一：服务器作为事件监听器

```typescript
// game-server/event-listener.ts
// 游戏服务器监听链上事件，更新游戏状态

import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: process.env.SUI_RPC! });

// 监听玩家成就，触发游戏内奖励
await client.subscribeEvent({
  filter: { Package: MY_PACKAGE },
  onMessage: async (event) => {
    if (event.type.includes("AchievementUnlocked")) {
      const { player, achievement_type } = event.parsedJson as any;

      // 游戏服务器处理：给玩家发放游戏内物品
      await gameServerAPI.grantItemToPlayer(player, achievement_type);
    }

    if (event.type.includes("GateJumped")) {
      const { character_id, destination_gate_id } = event.parsedJson as any;

      // 游戏服务器处理：传送玩家到目的地星系
      await gameServerAPI.teleportCharacter(character_id, destination_gate_id);
    }
  },
});
```

### 模式二：服务器作为数据提供者

```typescript
// game-server/api.ts
// 游戏服务器提供链下数据，dApp 调用

import express from "express";

const app = express();

// 提供星系名称（解密位置哈希）
app.get("/api/location/:hash", async (req, res) => {
  const { hash } = req.params;
  const geoInfo = await locationDB.getByHash(hash);
  res.json(geoInfo);
});

// 验证临近性（供 Sponsor 服务调用）
app.post("/api/proximity/verify", async (req, res) => {
  const { player_id, assembly_id, max_distance_km } = req.body;

  const playerPos = await getPlayerPosition(player_id);
  const assemblyPos = await getAssemblyPosition(assembly_id);
  const distance = calculateDistance(playerPos, assemblyPos);

  res.json({
    is_near: distance <= max_distance_km,
    distance_km: distance,
  });
});

// 获取玩家实时游戏状态
app.get("/api/character/:id/status", async (req, res) => {
  const status = await gameServerAPI.getCharacterStatus(req.params.id);
  res.json({
    online: status.online,
    system: status.current_system,
    ship: status.current_ship,
    fleet: status.fleet_id,
  });
});
```

### 模式三：双向状态同步

```
链上事件 ──────────────► 游戏服务器
（NFT 铸造、任务完成）     （更新游戏世界状态）

游戏服务器 ──────────────► 链上交易
（物理验证、赞助签名）      （记录结果、发放奖励）
```

### 这三种模式不要混成一锅

它们虽然都叫“服务端集成”，但职责完全不同：

- **事件监听器**
  偏消费型，把链上结果同步回游戏世界
- **数据提供者**
  偏查询型，为前端和后端提供链下解释层
- **双向同步**
  偏协同型，让链上和游戏服互相推动状态变化

如果你不分层，最后很容易出现：

- 一个服务既管监听，又管赞助，又管所有查询
- 出问题时完全不知道是哪条链路坏了

### 游戏服务器和链上之间最关键的不是“联通”，而是“口径一致”

例如：

- 链上认的 `assembly_id` 和游戏服认的设施编号是否同一件事
- 位置哈希和链下地图坐标是否一一对应
- 事件里的角色 ID 与游戏数据库里的角色主键是否稳定映射

这些映射一旦漂移，系统表面上还是通的，业务却会慢慢失真。

---

##  18.4 ObjectRegistry：全局查询表

当你的合约有多个共享对象时，需要一个注册表让其他合约和 dApp 找到它们：

```move
module platform::registry;

/// 全局注册表（类似域名系统）
public struct ObjectRegistry has key {
    id: UID,
    entries: Table<String, ID>,  // 名称 → ObjectID
}

/// 注册一个命名对象
public entry fun register(
    registry: &mut ObjectRegistry,
    name: vector<u8>,
    object_id: ID,
    _admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    table::add(
        &mut registry.entries,
        std::string::utf8(name),
        object_id,
    );
}

/// 查询
public fun resolve(registry: &ObjectRegistry, name: String): ID {
    *table::borrow(&registry.entries, name)
}
```

```typescript
// 通过注册表查找 Treasury ID
const registry = await getObjectWithJson(REGISTRY_ID);
const treasuryId = registry?.entries?.["alliance_treasury"];
```

Registry 的价值，不只是“方便查一个 ID”，而是把“分散的对象发现逻辑”统一下来。

这会直接改善三件事：

- 前端不必硬编码一堆对象地址
- 其他合约知道该去哪里找关键对象
- 升级或迁移后，可以通过注册表做平滑切换

### 但 Registry 也有边界

不要把它当成万能数据库。它最适合做：

- 命名解析
- 核心对象入口发现
- 少量稳定映射

不适合做：

- 高频变化的大列表
- 重型业务统计
- 大规模时间序列数据

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 多租户合约 | Table 按 gate_id 隔离配置，任意 Builder 可注册 |
| 服务端角色 | 事件监听 + 数据提供 + 临近性验证 |
| 双向同步 | 链上事件 → 游戏状态；游戏验证 → 链上记录 |
| ObjectRegistry | 全局命名表，方便其他合约和 dApp 查找对象 |

## 📚 延伸阅读

- [Chapter 8：赞助交易](./chapter-08.md)
- [EVE World Explainer](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/eve-frontier-world-explainer.md)
