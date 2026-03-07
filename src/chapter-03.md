# Chapter 3：Move 智能合约基础

> **目标：** 掌握 Move 语言的核心概念，理解 Sui 对象模型，能看懂并修改 EVE Frontier 的合约代码。

---

> 状态：基础章节。正文以 Move 语言、对象模型和最小示例为主。

##  3.1 Move 语言概览

Move 是 Sui 使用的智能合约语言，专门为“链上资产不能乱复制、乱丢弃、乱转移”这个问题设计。它不是先写一套通用编程语言，再靠库去约束资产；而是从语言层面就把“资源”当成最重要的对象。

你可以先抓住三个直觉：

- **资产不是一串余额数字**
  在 Sui 上，很多资产真的是一个独立对象，有自己的 `id`、字段、所有权和生命周期
- **类型决定你能不能复制、存储、丢弃**
  Move 会用能力系统限制一个值能做什么，避免你误把“珍贵资产”当成普通变量
- **合约更像模块 + 对象系统**
  你写的不是“一份全局大状态”，而是一组模块函数去创建、读取、修改对象

所以学 Move，不是只学语法。你真正要建立的是一套新的思维方式：

1. 先分清什么是普通数据，什么是资源
2. 再分清对象是谁拥有、谁能改、谁能转
3. 最后才是把这些规则写进函数入口和业务流程

这也正适合 EVE Frontier。因为在 EVE 里，很多东西天然就不是“数据库里的一行记录”，而更像独立存在的资产或设施：

- 一张通行证 NFT
- 一个智能星门
- 一个仓储单元
- 一个权限凭证
- 一条击杀记录

这些东西放到 Move 里，表达会非常自然。

---

##  3.2 模块 (Module) 结构

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

上面这段代码虽然很短，但已经包含了 Move 最常见的四类元素：

- **模块声明**
  `module my_package::my_module` 表示“这个文件里定义了一个模块”
- **依赖导入**
  `use` 用来引入别的模块暴露出来的类型或函数
- **结构体定义**
  `MyObject` 描述链上对象长什么样
- **函数入口**
  `init`、`set_value` 这些函数定义对象如何被创建和修改

### 模块和包到底是什么关系？

很多新手会把“包”和“模块”混成一件事，实际上它们不是一个层级：

- **包（Package）**
  是一整个 Move 工程目录，通常包含 `Move.toml`、`sources/`、`tests/`
- **模块（Module）**
  是包内部的代码单元，一个包里可以有多个模块

举个更接近真实项目的结构：

```text
my-extension/
├── Move.toml
├── sources/
│   ├── gate_logic.move
│   ├── gate_auth.move
│   └── pricing.move
└── tests/
    └── gate_tests.move
```

这里：

- `my-extension` 是一个包
- `gate_logic`、`gate_auth`、`pricing` 是三个模块

你可以把“包”理解为部署单位，把“模块”理解为代码组织单位。

### `init` 为什么重要？

`init` 会在包首次发布时执行一次，常见用途包括：

- 创建共享对象
- 给部署者发 `AdminCap`
- 初始化全局配置
- 建立注册表对象

它通常是“系统第一次上线时的开机动作”。如果你在 `init` 里把关键对象没建好，后面很多入口函数都没法正常使用。

### 字段为什么几乎总是从 `id: UID` 开始？

因为在 Sui 上，一个真正的链上对象必须带 `UID`，这代表它有全局唯一身份。没有 `UID` 的 struct 往往只是：

- 普通嵌套数据
- 配置项
- 事件载荷
- 一次性凭证

这也是你以后读 EVE 合约时判断“这是不是独立对象”的第一眼线索。

---

##  3.3 Move 的 Abilities（能力系统）

这是 Move 中最重要的概念之一。每个结构体类型可以拥有以下能力（abilities）：

| 能力 | 关键字 | 含义 |
|------|--------|------|
| **Key** | `has key` | 可以作为 Sui 对象，存储在全局状态中 |
| **Store** | `has store` | 可以嵌套存储在其他对象中 |
| **Copy** | `has copy` | 可以被隐式复制（谨慎使用！） |
| **Drop** | `has drop` | 函数结束时可以自动丢弃（不使用也没关系） |

不要把 abilities 当成“语法装饰”。它们本质上是在回答一个非常严肃的问题：

> 这个值，允许开发者怎样处理？

### 四个能力分别意味着什么？

#### 1. `key`

`has key` 说明这个类型可以作为顶层链上对象存在。

常见特征：

- 通常包含 `id: UID`
- 可以被地址拥有、共享、或被对象拥有
- 可以作为交易读写的核心对象

如果没有 `key`，这个类型就不能独立挂在链上全局状态里。

#### 2. `store`

`has store` 说明这个类型可以被安全地放进别的对象字段里。

例如：

- 把某个配置 struct 放进 `StorageUnit`
- 把某个白名单规则放进 `SmartAssembly`
- 把某个元数据结构嵌入 NFT

很多时候，一个类型不是独立对象，但它必须能作为别的对象的组成部分存在，这时就需要 `store`。

#### 3. `copy`

`has copy` 说明这个值可以被复制。

这通常只适合：

- 小型纯数据
- 不代表稀缺资源的值
- 类似 ID、布尔标记、枚举、简单配置

如果一个东西代表“权限”、“资产”、“唯一凭证”，通常就不应该给 `copy`。

#### 4. `drop`

`has drop` 说明这个值如果不用了，可以直接被丢弃。

这个能力看似不起眼，其实很关键。因为 Move 默认是很严格的：一个值如果没有被正确消费，编译器会追着你问“你到底打算怎么处理它？”

所以：

- 有 `drop`，可以不用也没关系
- 没 `drop`，你必须显式消费或转移它

### 为什么 abilities 会直接影响安全？

因为很多安全边界其实不是靠 `if` 判断守住的，而是靠“类型根本不允许你这么做”。

例如：

- 一个 NFT 没有 `copy`，你就没法复制出第二份
- 一个热土豆对象没有 `drop`，你就不能偷偷忽略它
- 一个权限对象没有公开构造路径，外部就伪造不出来

这就是 Move 很强的一点：它把很多业务约束前移到类型系统里。

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

这两个例子可以一起看：

- `JumpPermit` 是真正要存在链上的对象，所以有 `key`
- `VendingAuth` 只是某个调用流程里的见证值，不需要链上持久化，所以只给 `drop`

读 EVE 合约时，你经常能通过 abilities 直接猜出作者想表达什么：

- `has key, store`：大概率是真对象或准对象
- 只有 `drop`：大概率是 witness、receipt、一次性中间态
- `copy, drop, store`：大概率是普通值类型或配置数据

---

##  3.4 Sui 对象模型详解

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

这三种所有权不是抽象分类，而是你设计业务模型时最核心的决策之一。

### 1. 地址拥有：最像“我的资产”

地址拥有对象通常适合：

- 玩家个人 NFT
- `OwnerCap`
- 角色私有凭证
- 可转移的门票、许可证、勋章

特点是：

- 归某个地址控制
- 交易里通常要由该地址签名
- 很适合表达“谁拥有、谁支配”

### 2. 共享对象：最像“公共设施”

共享对象适合：

- 市场
- 星门
- 仓储单元
- 联盟金库
- 全服登记表

它的重点不是“谁拥有这个对象”，而是“谁在什么规则下可以对它执行什么操作”。

这正是 EVE Frontier 很多设施合约的核心形态。因为一个设施虽然也有经营者，但它首先是一个会被很多玩家共同交互的公共对象。

### 3. 对象拥有：最像“设施内部组件”

对象拥有常用于隐藏复杂内部状态，例如：

- 某个设施内部的配置对象
- 某个组件内部的库存表
- 某个注册表内部的辅助索引

它的好处是把状态封装起来，不让外部随便直接拿出来乱用。

### 为什么对象模型比“全局 mapping”更容易表达游戏世界？

因为游戏里的很多实体本来就是独立存在、可被引用、可被转让、可被组合的：

- 一座炮塔
- 一张许可证
- 一个角色权限
- 一份联盟条约

如果都塞进一张大表里，逻辑会越来越像“数据库管理脚本”。而对象模型更接近真实世界中的“实体 + 关系 + 所有权”。

### 对象不是只有“有没有”两个状态

你在设计时还要考虑对象生命周期：

1. **创建**
   谁来创建？在 `init` 里还是在业务入口里？
2. **持有**
   创建后由谁拥有？地址、共享还是对象内部？
3. **修改**
   谁能拿到 `&mut`？什么前提下允许修改？
4. **转移**
   能不能转让？转让后权限是否跟着走？
5. **销毁**
   什么时候可以消失？销毁前要不要结算余额或回收资源？

### 对象 ID 的确定性推导

EVE Frontier 中每个游戏内实体在链上的 ObjectID 是通过 `TenantItemId` 确定性推导的：

```move
public struct TenantItemId has copy, drop, store {
    item_id: u64,          // 游戏内的唯一 ID
    tenant: String,        // 区分不同游戏服务器实例
}
```

这意味着在游戏服务器知道 `item_id` 后，可以**提前计算**出该物品在链上的 ObjectID，无需等待链上响应。

这件事在 EVE 场景里非常重要，因为链下服务器和链上对象需要长期对齐：

- 游戏服务器知道某个设施、角色、物品的业务 ID
- 合约需要用稳定规则把它映射成链上对象键
- 前端和索引服务再按同样规则去查询

如果这个映射不稳定，整个系统都会乱：

- 链下认为是同一个设施
- 链上却找到了另一个对象
- 前端显示的数据和真实可交互对象对不上

所以你以后看到 `TenantItemId`、`derived_object`、注册表时，要先意识到：作者在解决的不是“代码怎么写”，而是“跨系统身份如何保持一致”。

---

##  3.5 关键安全模式

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

你可以把 Capability 当成“权限实体化”：

- 传统思路常常是“判断 `sender == admin`”
- Move/Sui 更常见的思路是“你有没有拿着某个权限对象”

这会带来几个直接好处：

- 权限可以转让
- 权限可以拆分
- 权限可以做成 NFT / Badge / Cap
- 权限关系更容易被链上审计

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

这个模式第一次看会觉得怪，因为 `Auth {}` 里什么数据都没有。但它真正要表达的是：

> “我不是靠字段内容证明身份，我是靠类型本身证明我来自哪个模块。”

为什么这很强？

- 外部模块不能随便伪造你的 witness 类型
- 组件可以只信任白名单里的 witness 类型
- 于是“谁能调用某个底层能力”就可以被限制在特定扩展包里

这正是 EVE Frontier 可扩展组件的核心。很多组件不是简单地暴露一个 `public entry` 给任何人调，而是要求你带着特定 witness 来进入。

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

这种模式特别适合做“前置检查不可跳过”的流程：

- 先验证资格，再铸造凭证
- 先检查网络状态，再执行设施动作
- 先读取并锁定某个上下文，再做结算

它的重点不是存数据，而是用类型系统强迫调用者按顺序办事。

---

##  3.6 函数可见性与访问控制

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

##  3.7 编写你的第一个 Move 扩展模块

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

##  3.8 编译与测试

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
