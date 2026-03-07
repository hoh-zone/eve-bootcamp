# 第30章：Extension 模式实战——官方示例精读

> **学习目标**：通过精读 `world-contracts/contracts/extension_examples/` 中两个真实的官方扩展示例，掌握 EVE Frontier Builder 扩展的标准开发模式。

---

> 状态：已映射到官方示例目录。正文是结构化讲解，建议边读边打开扩展示例源码。

## 最小调用链

`authorize_extension<XAuth> -> 写入 ExtensionConfig -> 业务入口校验规则 -> 调用 World Assembly API`

## 对应代码目录

- [world-contracts/contracts/extension_examples](https://github.com/evefrontier/world-contracts/tree/main/contracts/extension_examples)

## 关键 Struct

| 类型 | 作用 | 阅读重点 |
|------|------|------|
| `AdminCap` | 配置扩展规则的管理能力 | 看谁能写配置、谁只能读配置 |
| `XAuth` / witness 类型 | 绑定扩展授权身份 | 看 witness 类型如何成为扩展开关 |
| 配置对象 / 动态字段键 | 保存扩展规则 | 看规则 key 与业务入口读取是否一致 |

## 关键入口函数

| 入口 | 作用 | 你要确认什么 |
|------|------|------|
| `authorize_extension<XAuth>` | 把 witness 授权到 World 建筑 | 授权类型和扩展包类型是否完全一致 |
| 配置写入入口 | 初始化 tribe / bounty 等规则 | 写入 key 和读取 key 是否匹配 |
| 扩展业务入口 | 实际执行业务规则 | 是否只读自己配置，不假设 World 内核被改写 |

## 最容易误读的点

- Extension 模式不是“改 World 合约源码”，而是通过 witness 和配置对象挂接行为
- 授权成功不代表业务就能跑，配置 key 不一致一样会读不到规则
- witness 类型一旦写错，问题通常不在逻辑，而在授权链本身

Extension 模式真正厉害的地方，不是“可以插一段自定义代码”，而是它把扩展能力控制在一个很清晰的边界里：**World 继续掌握核心资产和核心状态，Builder 只在被允许的切面上改写规则**。这让 EVE 的扩展更像受约束的组合，而不是任意 monkey patch。你可以改变谁能过门、过门前要交什么、满足什么配置，但不能偷偷改写 Gate 本身的底层所有权和世界规则。

## 1. Extension 模式是什么？

EVE Frontier 的 Builder 扩展系统允许任何开发者修改游戏建筑（Gate、Turret、StorageUnit 等）的行为，而无需修改 World 合约本身。

核心设计：**Typed Witness 授权模式**

```
World 合约                           Builder 扩展包
─────────────                        ─────────────
Gate has key {                       pub struct XAuth {}
  extension: Option<TypeName>  ←──── gate::authorize_extension<XAuth>()
}
                                     当 gate 激活 XAuth 时，游戏引擎
                                     会调用 XAuth 所在包的扩展函数
```

---

## 2. 官方示例概览

`extension_examples` 包含两个典型示例：

| 示例文件 | 功能 | 授权类型 |
|---------|------|---------|
| `tribe_permit.move` | 只允许特定部族的角色使用传送门 | 身份过滤 |
| `corpse_gate_bounty.move` | 提交尸体作为"通行费"才能使用传送门 | 物品消耗 |

两者都依赖共同的配置框架：`config.move`

---

## 3. 共享配置框架：`config.move`

```move
module extension_examples::config;

use sui::dynamic_field as df;

/// 管理员能力
public struct AdminCap has key, store { id: UID }

/// 扩展的授权见证类型（Typed Witness）
public struct XAuth has drop {}

/// 扩展配置共享对象（用动态字段存储各种规则）
public struct ExtensionConfig has key {
    id: UID,
    admin: address,
}

/// 动态字段操作：添加/更新规则
public fun set_rule<K: copy + drop + store, V: store>(
    config: &mut ExtensionConfig,
    _: &AdminCap,           // 只有 AdminCap 持有者可以设置规则
    key: K,
    value: V,
) {
    if (df::exists_(&config.id, key)) {
        df::remove<K, V>(&mut config.id, key);
    };
    df::add(&mut config.id, key, value);
}

/// 检查规则是否存在
pub fun has_rule<K: copy + drop + store>(config: &ExtensionConfig, key: K): bool {
    df::exists_(&config.id, key)
}

/// 读取规则
pub fun borrow_rule<K: copy + drop + store, V: store>(
    config: &ExtensionConfig,
    key: K,
): &V {
    df::borrow(&config.id, key)
}

/// 获取 XAuth 实例（只能在包内调用）
pub(package) fun x_auth(): XAuth { XAuth {} }
```

**设计亮点**：`ExtensionConfig` 用动态字段存储不同类型的"规则"，每个规则有自己的 Key 类型（如 `TribeConfigKey`、`BountyConfigKey`），互不干扰，可以任意组合。

这也是为什么这里同时用了 dynamic field 和 typed witness。dynamic field 解决的是“规则怎么存、怎么扩”，typed witness 解决的是“谁有资格触发这套规则”。前者偏数据面，后者偏权限面。很多新手第一次写扩展时只顾着把配置表建出来，却忘了最关键的那条授权链，最后表现就是配置都在、代码也能编译，但 World 根本不会认这套扩展身份。

---

## 4. 示例一：部族通行证（`tribe_permit.move`）

### 功能

只有属于特定 `tribe`（部族）的角色才能通过这个 Gate。

### 核心结构

```move
module extension_examples::tribe_permit;

/// 动态字段 Key
public struct TribeConfigKey has copy, drop, store {}

/// 动态字段 Value
public struct TribeConfig has drop, store {
    tribe: u32,   // 允许通过的部族 ID
}
```

### 颁发通行证（核心逻辑）

```move
pub fun issue_jump_permit(
    extension_config: &ExtensionConfig,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    _: &AdminCap,           // 需要 AdminCap（防止滥用）
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. 读取部族配置
    assert!(extension_config.has_rule<TribeConfigKey>(TribeConfigKey {}), ENoTribeConfig);
    let tribe_cfg = extension_config.borrow_rule<TribeConfigKey, TribeConfig>(TribeConfigKey {});

    // 2. 验证角色部族
    assert!(character.tribe() == tribe_cfg.tribe, ENotStarterTribe);

    // 3. 有效期 5 天（以毫秒计）
    let expires_at_timestamp_ms = clock.timestamp_ms() + 5 * 24 * 60 * 60 * 1000;

    // 4. 调用 world::gate 颁发 JumpPermit NFT
    gate::issue_jump_permit<XAuth>(   // 用 XAuth 作为见证
        source_gate,
        destination_gate,
        character,
        config::x_auth(),               // 获取见证实例
        expires_at_timestamp_ms,
        ctx,
    );
}
```

### 管理员配置

```move
pub fun set_tribe_config(
    extension_config: &mut ExtensionConfig,
    admin_cap: &AdminCap,
    tribe: u32,
) {
    extension_config.set_rule<TribeConfigKey, TribeConfig>(
        admin_cap,
        TribeConfigKey {},
        TribeConfig { tribe },
    );
}
```

---

## 5. 示例二：尸体悬赏传送（`corpse_gate_bounty.move`）

### 功能

玩家必须将背包中一个特定类型的"尸体物品"存入 Builder 的 StorageUnit，才能获得通过 Gate 的许可。

### 完整流程

```move
pub fun collect_corpse_bounty<T: key + store>(
    extension_config: &ExtensionConfig,
    storage_unit: &mut StorageUnit,      // Builder 的物品库
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,               // 玩家角色
    player_inventory_owner_cap: &OwnerCap<T>,  // 玩家的物品所有权凭证
    corpse_item_id: u64,                 // 要提交的尸体 item_id
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. 读取悬赏配置（需要什么类型的尸体）
    assert!(extension_config.has_rule<BountyConfigKey>(BountyConfigKey {}), ENoBountyConfig);
    let bounty_cfg = extension_config.borrow_rule<BountyConfigKey, BountyConfig>(BountyConfigKey {});

    // 2. 从玩家背包取出尸体物品
    //    OwnerCap<T> 证明玩家有权操作该物品
    let corpse = storage_unit.withdraw_by_owner<T>(
        character,
        player_inventory_owner_cap,
        corpse_item_id,
        1,    // 数量
        ctx,
    );

    // 3. 验证尸体类型是否匹配悬赏要求
    assert!(corpse.type_id() == bounty_cfg.bounty_type_id, ECorpseTypeMismatch);

    // 4. 将尸体存入 Builder 的 StorageUnit（作为"收藏"）
    storage_unit.deposit_item<XAuth>(
        character,
        corpse,
        config::x_auth(),
        ctx,
    );

    // 5. 颁发有效期 5 天的 JumpPermit
    let expires_at_timestamp_ms = clock.timestamp_ms() + 5 * 24 * 60 * 60 * 1000;
    gate::issue_jump_permit<XAuth>(
        source_gate, destination_gate, character,
        config::x_auth(), expires_at_timestamp_ms, ctx,
    );
}
```

---

## 6. 两种模式的对比

```
tribe_permit（身份验证）：
  玩家 → [提供 Character 对象] → 验证 tribe_id → 颁发 JumpPermit

corpse_gate_bounty（物品消耗）：
  玩家 → [提供尸体物品] → 转移给 Builder → 颁发 JumpPermit
```

| 属性 | tribe_permit | corpse_gate_bounty |
|------|-------------|-------------------|
| 验证方式 | 角色属性 | 物品所有权 |
| 消耗资源 | 无（通行证有时效） | 消耗一个尸体物品 |
| 可重复使用 | 是（每次需 AdminCap 签发） | 每次都需消耗物品 |
| 适用场景 | 社交门控（如联盟专属） | 经济激励（如赏金猎人） |

这两个官方例子其实对应了 Builder 最常见的两类扩展思路：**身份过滤**和**资源交换**。前者重点在“你是谁”，后者重点在“你拿什么来换”。一旦看懂这两个母模式，很多别的玩法都只是变体，例如白名单市场、战利品兑换、任务门票、会籍权限、耗材开启等，都可以沿着这两条路去组合。

---

## 7. Builder 开发清单

根据两个官方示例，开发一个标准 Extension 的步骤：

```
1. 定义 XAuth 见证类型（每个扩展包一个）
2. 创建 ExtensionConfig 共享对象
3. 创建 AdminCap（用于管理配置）
4. 定义规则结构体（XxxConfig）和对应的 Key 类型（XxxConfigKey）
5. 实现管理函数：set_xxx_config（需要 AdminCap）
6. 实现核心逻辑：检查规则 → 业务逻辑 → 调用 gate::issue_jump_permit<XAuth>
7. 在 init() 中创建并转移 ExtensionConfig 和 AdminCap
```

真正落地时，建议再多检查一件事：**扩展失败后，World 的核心状态是否仍然安全**。一个好的扩展即使读不到配置、权限不匹配、付款不足，也应该只是让本次业务 abort，而不是让 Gate、StorageUnit、Character 进入半完成状态。这也是为什么 World 把核心资产操作口收得很紧，尽量让失败回滚停留在扩展边界内。

---

## 8. 我的第一个 Extension：付费通道

```move
module my_toll::paid_gate;

use my_toll::config::{Self, AdminCap, XAuth, ExtensionConfig};
use world::{character::Character, gate::{Self, Gate}};
use sui::{coin::{Self, Coin}, sui::SUI, balance::{Self, Balance}};
use sui::clock::Clock;

public struct TollConfigKey has copy, drop, store {}
public struct TollConfig has drop, store { toll_amount: u64 }

public struct TollVault has key {
    id: UID,
    balance: Balance<SUI>,
}

public fun pay_toll_and_jump(
    extension_config: &ExtensionConfig,
    vault: &mut TollVault,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let toll_cfg = extension_config.borrow_rule<TollConfigKey, TollConfig>(TollConfigKey {});
    assert!(coin::value(&payment) >= toll_cfg.toll_amount, 0);

    let toll = coin::split(&mut payment, toll_cfg.toll_amount, ctx);
    balance::join(&mut vault.balance, coin::into_balance(toll));
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    let expires = clock.timestamp_ms() + 60 * 60 * 1000; // 1 小时通行证
    gate::issue_jump_permit<XAuth>(
        source_gate, destination_gate, character,
        config::x_auth(), expires, ctx,
    );
}
```

---

## 本章小结

| 概念 | 要点 |
|------|------|
| Typed Witness (`XAuth`) | 每个扩展包的唯一授权凭证，传入 `gate::issue_jump_permit<XAuth>` |
| `ExtensionConfig` | 用动态字段存储可扩展规则，支持任意规则类型组合 |
| `TribeConfigKey/BountyConfigKey` | 不同规则的标识 Key，避免类型碰撞 |
| `AdminCap` | 控制谁能修改扩展配置 |
| `OwnerCap<T>` | 玩家物品操作的授权凭证 |

> 下一章：**炮塔 AI 扩展开发** —— 通过 `world::turret` 分析目标优先级队列系统，开发自定义的炮塔 AI 扩展。
