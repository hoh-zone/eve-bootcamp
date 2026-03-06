# 第24章：KillMail 系统深度解析

> **学习目标**：理解 EVE Frontier 链上战斗死亡记录的完整架构——从源码结构到与 Builder 扩展的交互方式。

---

## 2.1 什么是 KillMail？

在 EVE Frontier 中，每一次玩家对玩家（PvP）的击杀事件都会在链上生成一条不可篡改的记录，称为 **KillMail（击杀邮件）**。这不只是一个日志——它是一个具有唯一对象 ID 的共享对象，任何人都可以在链上查询。

```
链上结构关系：
KillmailRegistry（注册表）
    └── Killmail（共享对象）
            ├── killer_id    : 击杀者 TenantItemId
            ├── victim_id    : 被击杀者 TenantItemId
            ├── kill_timestamp (Unix 秒)
            ├── loss_type    : SHIP | STRUCTURE
            └── solar_system_id : 发生地星系
```

---

## 2.2 KillMail 的核心数据结构

### 源码精读（`world/sources/killmail/killmail.move`）

```move
// === Enums ===
/// 击杀类型：飞船 or 建筑
public enum LossType has copy, drop, store {
    SHIP,
    STRUCTURE,
}

/// 链上 KillMail 共享对象
public struct Killmail has key {
    id: UID,
    key: TenantItemId,                  // 来自 item_id + tenant 的确定性 ID
    killer_id: TenantItemId,
    victim_id: TenantItemId,
    reported_by_character_id: TenantItemId,
    kill_timestamp: u64,                // Unix timestamp（秒，非毫秒！）
    loss_type: LossType,
    solar_system_id: TenantItemId,
}
```

> **关键设计**：Killmail 的 `id` 不是随机生成的，而是通过 `derived_object::claim(registry, key)` 从 `KillmailRegistry` 确定性派生而来，保证了 `item_id → object_id` 的映射唯一性。

### TenantItemId 是什么？

```move
// world/sources/primitives/in_game_id.move
public struct TenantItemId has copy, drop, store {
    item_id: u64,    // 游戏内部的业务 ID
    tenant: String,  // 游戏租户标识（如 "evefrontier"）
}
```

```move
// 创建方式
let key = in_game_id::create_key(item_id, tenant);
```

这个设计让同一个 `item_id` 可以在不同 tenant（不同服务器/游戏版本）中复用，互不冲突。

---

## 2.3 KillMail 的创建流程

### 全流程解析

```move
public fun create_killmail(
    registry: &mut KillmailRegistry,
    admin_acl: &AdminACL,           // 只有授权服务器才能创建
    item_id: u64,                   // 击杀记录的 in-game ID
    killer_id: u64,
    victim_id: u64,
    reported_by_character: &Character,  // 提交报告的角色（必须在场）
    kill_timestamp: u64,            // Unix 秒
    loss_type: u8,                  // 1=SHIP, 2=STRUCTURE
    solar_system_id: u64,
    ctx: &mut TxContext,
) {
    // 1. 验证调用者是授权服务器
    admin_acl.verify_sponsor(ctx);

    // 2. 用报告者的 tenant 生成 key
    let tenant = reported_by_character.tenant();
    let killmail_key = in_game_id::create_key(item_id, tenant);

    // 3. 防止重复创建
    assert!(!registry.object_exists(killmail_key), EKillmailAlreadyExists);

    // 4. 验证关键字段非零
    assert!(item_id != 0, EKillmailIdEmpty);
    assert!(killer_id != 0, ECharacterIdEmpty);
    // ...

    // 5. 从注册表派生确定性 UID（核心机制）
    let killmail_uid = derived_object::claim(registry.borrow_registry_id(), killmail_key);

    // 6. 创建并共享
    let killmail = Killmail { id: killmail_uid, ... };
    transfer::share_object(killmail);
}
```

### 流程图

```
游戏服务器 → create_killmail()
                ↓
       verify_sponsor (AdminACL 检查)
                ↓
       create_key(item_id, tenant)
                ↓
       object_exists? → 是 → ABORT EKillmailAlreadyExists
                ↓ 否
       derived_object::claim → 确定性 UID
                ↓
       Killmail {..} → share_object
                ↓
       emit KillmailCreatedEvent
```

---

## 2.4 事件系统与链下索引

```move
public struct KillmailCreatedEvent has copy, drop {
    key: TenantItemId,
    killer_id: TenantItemId,
    victim_id: TenantItemId,
    reported_by_character_id: TenantItemId,
    loss_type: LossType,
    kill_timestamp: u64,
    solar_system_id: TenantItemId,
}
```

KillMail 采用**事件索引 + 对象存储双轨制**：

| 组件 | 用途 |
|------|------|
| 链上共享对象 `Killmail` | 可被合约读取，Builder 扩展可查询 |
| `KillmailCreatedEvent` | 供索引服务实时监听，构建排行榜/统计 |

---

## 2.5 Builder 如何使用 KillMail？

### 场景：击杀积分奖励系统

Builder 可以监听 `KillmailCreatedEvent` 事件，在自己的扩展合约中接收奖励请求：

```move
module my_pvp::kill_reward;

use world::killmail::Killmail;
use world::access::OwnerCap;
use sui::coin::{Self, Coin};
use sui::sui::SUI;

public struct RewardPool has key {
    id: UID,
    balance: Balance<SUI>,
    reward_per_kill: u64,
    owner: address,
}

/// 玩家提交 KillMail 对象领取 SUI 奖励
pub fun claim_kill_reward(
    pool: &mut RewardPool,
    killmail: &Killmail,           // 传入链上 KillMail 对象
    character_id: ID,              // 调用者的角色 ID
    ctx: &mut TxContext,
) {
    // 验证 killmail.killer_id 对应当前调用者的角色
    // （实际需要结合 OwnerCap 验证）
    assert!(balance::value(&pool.balance) >= pool.reward_per_kill, 0);

    let reward = coin::take(&mut pool.balance, pool.reward_per_kill, ctx);
    transfer::public_transfer(reward, ctx.sender());
}
```

### 场景：基于 KillMail 的 NFT 勋章

```move
/// 击杀 100 次后铸造"百杀勋章"NFT
public fun mint_centurion_badge(
    tracker: &KillTracker,           // 自建的击杀次数追踪对象
    recipient: address,
    ctx: &mut TxContext,
) {
    assert!(tracker.kill_count >= 100, ENotEnoughKills);
    // 铸造 NFT...
}
```

---

## 2.6 `derived_object` 模式深度解析

KillMail 使用了 Sui 的 `derived_object`（确定性对象 ID）模式，这是 EVE Frontier World 合约中的重要设计：

```move
// 从注册表派生确定性 UID
let killmail_uid = derived_object::claim(registry.borrow_registry_id(), killmail_key);
```

**为什么不用 `object::new(ctx)`？**

| 对比 | `object::new(ctx)` | `derived_object::claim()` |
|---|---|---|
| ID 来源 | 随机（基于 tx digest） | 确定性（基于 key） |
| 重复创建 | 无法防止（每次都是新 ID） | 自动防止（key 只能用一次） |
| 链下预计算 | 不可能 | 可以（已知 key 即知 ID） |
| 适用场景 | 普通对象 | 游戏资产、KillMail 等有业务 ID 的对象 |

---

## 2.7 KillMail 注册表的设计

```move
// world/sources/registry/killmail_registry.move
public struct KillmailRegistry has key {
    id: UID,
    // 注意：没有其他字段！所有数据通过 derived_object 存储
}

pub fun object_exists(registry: &KillmailRegistry, key: TenantItemId): bool {
    derived_object::exists(&registry.id, key)
}
```

这个注册表极其精简——它只是一个 `UID` 容器，所有的 KillMail 作为其 `derived children` 存在于 Sui 的状态树中。

---

## 2.8 安全性分析

### 仅服务器可创建

```move
admin_acl.verify_sponsor(ctx);
```

`verify_sponsor` 检查调用者是否在 `AdminACL.authorized_sponsors` 列表中。普通玩家**无法**伪造 KillMail——每条击杀记录都由链接到游戏服务器密钥的地址签发。

### 防重放

```move
assert!(!registry.object_exists(killmail_key), EKillmailAlreadyExists);
```

使用 `derived_object` 的存在性检查，天然防止同一场战斗被重复提交。

---

## 2.9 实战练习

1. **读取 KillMail**：写一个 PTB（可编程交易块），传入一个 KillMail 对象 ID，打印 `killer_id`、`victim_id`、`kill_timestamp`
2. **击杀积分合约**：基于 KillMail 实现一个积分系统，每次击杀飞船得 100 分，击杀建筑得 50 分
3. **KillMail NFT 凭证**：设计一个 Builder 扩展，允许受害者（victim）凭借 KillMail 对象 ID 申请"死亡补偿金"

---

## 本章小结

| 概念 | 要点 |
|------|------|
| `Killmail` | 不可变的共享对象，记录 PvP 击杀事件 |
| `TenantItemId` | `item_id + tenant` 的复合键，支持多租户 |
| `derived_object` | 确定性对象 ID，防止重复，支持链下预计算 |
| `KillmailRegistry` | 用 UID 作为 derived children 的父节点 |
| 安全机制 | AdminACL 验证 + derived_object 防重放 |

> 下一章：**链下签名 × 链上验证** —— 游戏服务器如何用密钥签名事件，合约如何验证这些签名的真实性。
