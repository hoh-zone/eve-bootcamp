# Chapter 16：多租户架构与游戏服务器集成

> ⏱ 预计学习时间：2 小时
>
> **目标：** 理解 EVE Frontier 的多租户（Multi-tenant）世界合约设计，掌握如何构建可服务多个联盟的平台型合约，以及如何与游戏服务器双向集成。

---

> 状态：架构章节。正文以多租户设计和 Registry 模式为主。

## 前置依赖

- 建议先读 [Chapter 4](./chapter-04.md)
- 建议先读 [Chapter 11](./chapter-11.md)

## 源码位置

- [book/src/code/chapter-16](./code/chapter-16)

## 关键测试文件

- 当前目录以 `multi_toll.move` 与 `registry.move` 为主。

## 推荐阅读顺序

1. 先读单租户与多租户差异
2. 再打开 [book/src/code/chapter-16](./code/chapter-16)
3. 最后和 [Chapter 18](./chapter-18.md) 的全栈架构一起理解

## 验证步骤

1. 能解释 Registry 如何隔离多租户数据
2. 能说明何时应该做平台型合约而不是单联盟合约
3. 能识别多租户下最容易出错的权限边界

## 常见报错

- 共享一个对象服务所有租户，却没有显式的租户边界

---

## 16.1 什么是多租户合约？

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

---

## 16.2 多租户合约设计模式

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

---

## 16.3 游戏服务器集成模式

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

---

## 16.4 ObjectRegistry：全局查询表

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

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 多租户合约 | Table 按 gate_id 隔离配置，任意 Builder 可注册 |
| 服务端角色 | 事件监听 + 数据提供 + 临近性验证 |
| 双向同步 | 链上事件 → 游戏状态；游戏验证 → 链上记录 |
| ObjectRegistry | 全局命名表，方便其他合约和 dApp 查找对象 |

## 📚 延伸阅读

- [Chapter 11：赞助交易](./chapter-11.md)
- [EVE World Explainer](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/eve-frontier-world-explainer.md)
