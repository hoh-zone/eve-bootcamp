# Chapter 3：Move 智能合约基础

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握 Move 语言的核心概念，理解 Sui 对象模型，能看懂并修改 EVE Frontier 的合约代码。

---

## 3.1 Move 语言概览

Move 是 Sui 使用的智能合约语言，专为数字资产安全设计。它最大的特点是：**资产是一等公民**，语言层面就保证了资产不会被意外复制或丢失。

### 与 Solidity 的对比

| 特性 | Solidity (Ethereum) | Move (Sui) |
|------|--------------------|----|
| 资产管理 | 账本余额，易出现重入攻击 | 资源类型，不可隐式复制/丢弃 |
| 对象模型 | 合约存储的 mapping | 独立的链上对象 |
| 模块化 | 合约文件 | Move 模块（module） |
| 升级性 | 不可变（默认） | 支持包升级（Package Upgrade） |

---

## 3.2 模块 (Module) 结构

一个 Move 合约由一个或多个**模块**组成：

```move
// 文件：sources/my_contract.move

// 模块声明：包名::模块名
module my_package::my_module {

    // 导入依赖
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::transfer;

    // 结构体定义（资产/数据）
    public struct MyObject has key, store {
        id: UID,
        value: u64,
    }

    // 初始化函数（合约部署时自动执行一次）
    fun init(ctx: &mut TxContext) {
        let obj = MyObject {
            id: object::new(ctx),
            value: 0,
        };
        transfer::share_object(obj);
    }

    // 公开函数（可被外部调用）
    public fun set_value(obj: &mut MyObject, new_value: u64) {
        obj.value = new_value;
    }
}
```

---

## 3.3 Move 的 Abilities（能力系统）

这是 Move 中最重要的概念之一。每个结构体类型可以拥有以下能力（abilities）：

| 能力 | 关键字 | 含义 |
|------|--------|------|
| **Key** | `has key` | 可以作为 Sui 对象，存储在全局状态中 |
| **Store** | `has store` | 可以嵌套存储在其他对象中 |
| **Copy** | `has copy` | 可以被隐式复制（谨慎使用！） |
| **Drop** | `has drop` | 函数结束时可以自动丢弃（不使用也没关系） |

### 在 EVE Frontier 中的应用

```move
// JumpPermit：有 key + store，是真实的链上资产，不可复制
public struct JumpPermit has key, store {
    id: UID,
    character_id: ID,
    route_hash: vector<u8>,
    expires_at_timestamp_ms: u64,
}

// VendingAuth：只有 drop，是一次性的"凭证"（Witness Pattern）
public struct VendingAuth has drop {}
```

---

## 3.4 Sui 对象模型详解

在 Sui 上，所有带 `key` ability 的结构体都是**对象**，分三种所有权类型：

### 所有权类型

```
1. 地址拥有（Address-owned）
   └── 只有持有该地址的人能访问
   └── 例如：玩家角色的 OwnerCap

2. 共享对象（Shared Object）
   └── 任何人都可以在链上读写（受合约逻辑控制）
   └── 例如：智能存储单元、星门本体

3. 对象拥有（Object-owned）
   └── 被另一个对象持有，外部无法直接访问
   └── 例如：存储在组件内部的配置
```

### 对象 ID 的确定性推导

EVE Frontier 中每个游戏内实体在链上的 ObjectID 是通过 `TenantItemId` 确定性推导的：

```move
public struct TenantItemId has copy, drop, store {
    item_id: u64,          // 游戏内的唯一 ID
    tenant: String,        // 区分不同游戏服务器实例
}
```

这意味着在游戏服务器知道 `item_id` 后，可以**提前计算**出该物品在链上的 ObjectID，无需等待链上响应。

---

## 3.5 关键安全模式

EVE Frontier 和其他 Sui 项目广泛使用几个 Move 特有的安全设计模式：

### 模式一：Capability Pattern（能力模式）

权限通过持有对象来表示，不是账户角色。

```move
// 定义能力对象
public struct OwnerCap<phantom T> has key, store {
    id: UID,
}

// 需要 OwnerCap 才能调用的函数
public fun withdraw_by_owner<T: key>(
    storage_unit: &mut StorageUnit,
    owner_cap: &OwnerCap<T>,  // 必须持有此凭证
    ctx: &mut TxContext,
): Item {
    // ...
}
```

**优势**：`OwnerCap` 可以转让，可以委托，比账号级别的权限更灵活。

### 模式二：Typed Witness Pattern（类型见证模式）

**这是 EVE Frontier 扩展系统的核心！** 用于验证调用者是特定包的模块。

```move
// Builder 在自己的包中定义一个 Witness 类型
module my_extension::custom_gate {
    // 只有这个模块能创建 Auth 实例（因为它没有公开构造函数）
    public struct Auth has drop {}

    // 调用星门 API 时，把 Auth {} 作为凭证传入
    public entry fun request_jump(
        gate: &mut Gate,
        character: &Character,
        ctx: &mut TxContext,
    ) {
        // 自定义逻辑（例如检查费用）
        // ...

        // 用 Auth {} 证明调用来自这个已授权的模块
        gate::issue_jump_permit(
            gate, destination, character,
            Auth {},      // Witness：证明我是 my_extension::custom_gate
            expires_at,
            ctx,
        )
    }
}
```

Star Gate 组件知道你的 `Auth` 类型已被注册在白名单中，因此允许调用。

### 模式三：Hot Potato（热土豆模式）

一种没有 `copy`、`store`、`drop` 能力的对象，必须在同一个交易中被消耗：

```move
// 没有任何 ability = 热土豆，必须在本次 tx 中处理掉
public struct NetworkCheckReceipt {}

public fun check_network(node: &NetworkNode): NetworkCheckReceipt {
    // 执行检查...
    NetworkCheckReceipt {}  // 返回热土豆
}

public fun complete_action(
    assembly: &mut Assembly,
    receipt: NetworkCheckReceipt,  // 必须传入，保证检查被执行过
) {
    let NetworkCheckReceipt {} = receipt; // 消耗热土豆
    // 正式执行操作
}
```

**用途**：强制某些操作必须原子组合完成（如"先检查网络节点 → 再执行组件操作"）。

---

## 3.6 函数可见性与访问控制

```move
module example::access_demo {

    // 私有函数：只能在本模块内调用
    fun internal_logic() { }

    // 包内可见：同一个包的其他模块可调用（Layer 1 Primitives 使用这个）
    public(package) fun package_only() { }

    // Entry：可以直接作为交易（Transaction）的顶层调用
    public entry fun user_action(ctx: &mut TxContext) { }

    // 公开：任何模块都可以调用
    public fun read_data(): u64 { 42 }
}
```

---

## 3.7 编写你的第一个 Move 扩展模块

让我们把上面的概念结合起来，写一个最简单的 Storage Unit 扩展：

```move
module my_extension::simple_vault;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::tx_context::TxContext;

// 我们的 Witness 类型
public struct VaultAuth has drop {}

/// 任何人都可以存入物品（开放存款）
public entry fun deposit_item(
    storage_unit: &mut StorageUnit,
    character: &Character,
    item: Item,
    ctx: &mut TxContext,
) {
    // 使用 VaultAuth{} 作为见证，证明这个调用是合法绑定的扩展
    storage_unit::deposit_item(
        storage_unit,
        character,
        item,
        VaultAuth {},
        ctx,
    )
}

/// 只有拥有特定 Badge（NFT）的角色才能取出物品
public entry fun withdraw_item_with_badge(
    storage_unit: &mut StorageUnit,
    character: &Character,
    _badge: &MemberBadge,  // 必须持有成员勋章才能调用
    type_id: u64,
    ctx: &mut TxContext,
): Item {
    storage_unit::withdraw_item(
        storage_unit,
        character,
        VaultAuth {},
        type_id,
        ctx,
    )
}
```

---

## 3.8 编译与测试

```bash
# 在你的 Move 包目录下
cd my-extension

# 编译（会检查类型和逻辑）
sui move build

# 运行单元测试
sui move test

# 发布到测试网
sui client publish 
```

发布成功后，你会得到一个 `Package ID`（如 `0xabcdef...`），这是你的合约在链上的地址。

---

## 🔖 本章小结

| 概念 | 关键要点 |
|------|--------|
| Move 模块 | `module package::name { }` 是代码组织单元 |
| Abilities | `key`(对象) `store`(嵌套) `copy`(可复制) `drop`(可丢弃) |
| 三种所有权 | 地址拥有 / 共享对象 / 对象拥有 |
| Capability 模式 | 权限 = 持有对象，可转让可委托 |
| Witness 模式 | 唯一实例化的类型作为调用凭证，EVE Frontier 扩展核心 |
| Hot Potato | 无能力结构体，强制原子操作 |

## 📚 延伸阅读

- [Move Book（官方）](https://move-book.com)
- [Sui Move 概念](https://docs.sui.io/concepts/sui-move-concepts)
- [Typed Witness 模式](https://move-book.com/programmability/witness-pattern)
- [Capability 模式](https://move-book.com/programmability/capability)
- [EVE Frontier World 合约代码](https://github.com/evefrontier/world-contracts)
