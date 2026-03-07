# 第26章：访问控制系统完整解析

> **学习目标**：深入理解 `world::access` 模块的完整权限架构——从 `GovernorCap`、`AdminACL`、`OwnerCap` 到 `Receiving` 模式，掌握 EVE Frontier 访问控制系统的精密设计。

---

> 状态：教学示例。访问控制细节较多，建议直接对照源码与测试逐段阅读，而不是只看概念图。

## 最小调用链

`调用入口 -> 权限对象/授权列表校验 -> 借出或消费 capability -> 执行业务动作 -> 归还或销毁能力对象`

## 对应代码目录

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)

## 关键 Struct

| 类型 | 作用 | 阅读重点 |
|------|------|------|
| `AdminACL` | 服务器授权白名单 | 看 sponsor 白名单如何维护 |
| `GovernorCap` | 系统级最高权限能力 | 看哪些动作必须走 governor 而不是 owner |
| `OwnerCap<T>` | 泛型所有权凭证 | 看借出、归还、转移三种生命周期 |
| `Receiving` 相关模式 | 安全借用 object-owned 资产 | 看 object-owned 和 address-owned 的差异 |
| `ServerAddressRegistry` | 服务端地址注册表 | 看签名身份和业务权限如何串起来 |

## 关键入口函数

| 入口 | 作用 | 你要确认什么 |
|------|------|------|
| `verify_sponsor` | 校验提交者是否在服务器白名单 | 它解决的是身份来源，不是全部业务约束 |
| `borrow_owner_cap` / `return_owner_cap` | 借出与归还所有权凭证 | 是否严格遵守 Borrow-Use-Return |
| governor / registry 管理入口 | 维护系统级权限配置 | 是否把系统管理权限错误下放给普通 owner |

## 最容易误读的点

- `ctx.sender()` 在 EVE Frontier 里通常不够用，很多场景必须看 capability 或 sponsor
- `OwnerCap<T>` 不是一次性消耗品，很多时候是临时借用后再归还
- object-owned 资产不能照搬 address-owned 的权限判断方式

理解这一章最有效的办法，是把权限拆成 3 个来源：**地址身份**、**能力对象**、**服务器背书**。地址身份回答“这笔交易是谁发的”；能力对象回答“他对哪个具体对象拥有什么控制权”；服务器背书回答“这是不是被游戏世界认可的一次系统动作”。EVE Frontier 同时使用这三套来源，是因为单靠 `ctx.sender()` 无法表达复杂的物品托管、建筑控制和链下状态注入。

## 1. 为什么访问控制系统复杂？

传统智能合约的权限通常只有两层：owner（所有者）和 public（公开）。EVE Frontier 需要更精密的控制：

```
游戏公司（CCP Level）      → GovernorCap：系统级别配置
  ├── 游戏服务器             → AdminACL/verify_sponsor：链上操作授权
  ├── 建筑所有者（Builder）  → OwnerCap<T>：建筑控制权
  └── 玩家（Character）      → 通过 OwnerCap 访问自己的物品
```

一个角色的物品在另一个玩家的建筑里——谁能操作这个物品？这就是 EVE Frontier 访问控制需要解决的核心问题。

所以你会看到 EVE 的权限不是围绕“某地址是不是 owner”展开，而是围绕“某个对象现在被谁持有、谁能临时借出、谁能代表服务器写入世界状态”展开。对象世界一旦复杂起来，传统合约里常见的单一 owner 字段就不够细了。

---

## 2. AdminACL：服务器授权白名单

```move
// world/sources/access/access_control.move

pub struct AdminACL has key {
    id: UID,
    authorized_sponsors: Table<address, bool>,  // 服务器地址白名单
}

/// 仅允许已注册服务器执行特权操作
pub fun verify_sponsor(admin_acl: &AdminACL, ctx: &TxContext) {
    assert!(
        admin_acl.authorized_sponsors.contains(ctx.sender()),
        EUnauthorizedSponsor,
    );
}
```

**用法**：World 合约中所有需要游戏服务器权限的操作都以 `admin_acl.verify_sponsor(ctx)` 开头：

```move
// 创建角色（必须由服务器触发）
pub fun create_character(..., admin_acl: &AdminACL, ...) {
    admin_acl.verify_sponsor(ctx);
    // ...
}

// 创建 KillMail（必须由服务器触发）
pub fun create_killmail(..., admin_acl: &AdminACL, ...) {
    admin_acl.verify_sponsor(ctx);
    // ...
}
```

### 服务器地址注册（只有 GovernorCap 可操作）

```move
pub fun add_sponsor_to_acl(
    admin_acl: &mut AdminACL,
    _: &GovernorCap,           // 需要最高权限
    sponsor: address,
) {
    admin_acl.authorized_sponsors.add(sponsor, true);
}
```

---

## 3. GovernorCap：系统最高权限

```move
// GovernorCap 是整个系统的"根密钥"
// 它的存在意味着游戏公司保留了系统级别的配置能力
pub struct GovernorCap has key, store { id: UID }
```

`GovernorCap` 用于：
- 向 `AdminACL` 添加/删除服务器地址
- 向 `ServerAddressRegistry` 注册服务器（用于签名验证）
- 设置全系统级别的配置参数

```move
pub fun register_server_address(
    server_address_registry: &mut ServerAddressRegistry,
    _: &GovernorCap,
    server_address: address,
) {
    server_address_registry.authorized_address.add(server_address, true);
}
```

---

## 4. OwnerCap\<T\>：泛型所有权凭证

这是 EVE Frontier 访问控制最精巧的设计：

```move
/// OwnerCap<T> 证明持有者对某个 T 类型对象的控制权
pub struct OwnerCap<phantom T: key> has key, store {
    id: UID,
    authorized_object_id: ID,   // 绑定了具体对象的 ID
}
```

**为什么用泛型？**

```move
OwnerCap<Gate>           // 对某个 Gate 的控制权
OwnerCap<Turret>         // 对某个 Turret 的控制权
OwnerCap<StorageUnit>    // 对某个 StorageUnit 的控制权
OwnerCap<Character>      // 对某个 Character 的控制权
```

类型系统天然保证了权限不会错误地跨类型使用。

### OwnerCap 的创建（只有 AdminACL 可创建）

```move
pub fun create_owner_cap<T: key>(
    admin_acl: &AdminACL,
    obj: &T,
    ctx: &mut TxContext,
): OwnerCap<T> {
    admin_acl.verify_sponsor(ctx);
    let object_id = object::id(obj);
    let owner_cap = OwnerCap<T> {
        id: object::new(ctx),
        authorized_object_id: object_id,
    };
    event::emit(OwnerCapCreatedEvent { ... });
    owner_cap
}
```

**重要约束**：玩家无法自己创建 `OwnerCap`，只能由游戏服务器（verify_sponsor）颁发。

这层约束的意义是把“权限对象的铸造权”牢牢关在系统边界内。否则一旦任何人都能自己 mint `OwnerCap<T>`，整个能力体系就失去可信度了。能力对象之所以可靠，不只是因为它是个链上对象，而是因为它的来源链条本身也受控。

---

## 5. Receiving 模式：OwnerCap 的安全借用

这是 EVE Frontier 最独特的模式之一——`OwnerCap` 平时存放在角色对象（Character）的控制下，借用时用 Sui 的 `Receiving<T>` 临时取出：

```
Character（共享对象）
  └── 持有 → OwnerCap<Gate>（通过 Sui transfer::transfer 存放）

玩家操作时：
  1. 玩家提交 Receiving<OwnerCap<Gate>> ticket（证明有权取出）
  2. character::receive_owner_cap() → 临时取出 OwnerCap<Gate>
  3. 执行操作（如修改 Gate 配置）
  4. 用 return_owner_cap_to_object() 将 OwnerCap 归还给 Character
```

### 源码实现

```move
/// 从 Character 借出 OwnerCap
pub(package) fun receive_owner_cap<T: key>(
    receiving_id: &mut UID,
    ticket: Receiving<OwnerCap<T>>,   // Sui 原生 Receiving ticket
): OwnerCap<T> {
    transfer::receive(receiving_id, ticket)
}

/// 归还 OwnerCap 给 Character
pub fun return_owner_cap_to_object<T: key>(
    owner_cap: OwnerCap<T>,
    character: &mut Character,
    receipt: ReturnOwnerCapReceipt,   // 操作结束的收据
) {
    validate_return_receipt(receipt, object::id(&owner_cap), ...);
    transfer::transfer(owner_cap, character.character_address);
}
```

### ReturnOwnerCapReceipt 防止遗失

```move
pub struct ReturnOwnerCapReceipt {
    owner_id: address,
    owner_cap_id: ID,
}
```

在借用 OwnerCap 的函数签名中，必须返回 `ReturnOwnerCapReceipt`，否则编译报错。这样确保了：
1. OwnerCap 一定会被归还（不能被遗失）
2. 必须配对使用（无法伪造收据）

`Receiving` 模式表面上看有点繁琐，本质上是在把 object-owned 生命周期显式化。普通地址持有的东西，你拿引用就能用；但 Character、StorageUnit 这类对象持有的能力，如果没有一套“借出-使用-归还”的显式流程，就很容易在复杂调用链里丢失或被截留。EVE 选择把这个过程做得啰嗦一点，换来的是权限流转可审计、可回滚、可强约束。

---

## 6. 完整的权限层级图

```
GovernorCap（根密钥，CCP 持有）
    │
    ▼ 配置
AdminACL（服务器白名单）
    │
    ▼ verify_sponsor
所有特权操作（创建角色、创建建筑、颁发 OwnerCap...）
    │
    ▼ create_owner_cap<T>
OwnerCap<Gate>  OwnerCap<Turret>  OwnerCap<StorageUnit>...
    │                                      │
    ▼ 转给 Character                       ▼ 转给 Builder 玩家
Character 保管（Receiving 模式）           直接持有
    │
    ▼ receive_owner_cap (Receiving<OwnerCap<Gate>>)
临时借出 → 使用 → 归还
```

---

## 7. ServerAddressRegistry：签名验证白名单

与 `AdminACL` 不同，`ServerAddressRegistry` 专门用于签名验证（不是函数调用权限）：

```move
pub struct ServerAddressRegistry has key {
    id: UID,
    authorized_address: Table<address, bool>,
}

pub fun is_authorized_server_address(
    registry: &ServerAddressRegistry,
    server_address: address,
): bool {
    registry.authorized_address.contains(server_address)
}
```

**用途**：在 `location::verify_proximity` 中验证签名来源：

```move
assert!(
    access::is_authorized_server_address(server_registry, message.server_address),
    EUnauthorizedServer,
);
```

这里也能看出 `AdminACL` 和 `ServerAddressRegistry` 的分工：前者偏“谁能直接代表服务器发交易”，后者偏“谁的链下签名可以被链上承认”。两者经常来自同一批后台系统，但语义并不一样。把它们混成一个表，短期省事，长期会让权限面变得很难收缩。

---

## 8. Builder 视角：如何正确使用 OwnerCap

### 创建建筑时

```move
// 游戏服务器为 Builder 创建 Gate 时，自动创建并转移 OwnerCap<Gate>
pub fun create_gate_with_owner(...) {
    admin_acl.verify_sponsor(ctx);
    let gate = Gate { ... };
    let owner_cap = create_owner_cap(&admin_acl, &gate, ctx);
    // owner_cap 转移给 builder，builder 掌控这个 Gate
    transfer::share_object(gate);
    transfer::public_transfer(owner_cap, builder_address);
}
```

### Builder 修改建筑配置时

```move
// Builder 用 OwnerCap 证明自己有权操作该 Gate
pub fun set_gate_config(
    gate: &mut Gate,
    owner_cap: &OwnerCap<Gate>,      // 持有就有权限
    new_config: GateConfig,
    ctx: &TxContext,
) {
    // 验证 OwnerCap 对应的对象 ID 与 gate 一致
    assert!(owner_cap.authorized_object_id == object::id(gate), EOwnerCapMismatch);
    gate.config = new_config;
}
```

---

## 9. 比较：EVE vs 传统合约权限

| 场景 | 传统合约 | EVE Frontier |
|------|---------|-------------|
| 建筑所有权 | 记录 owner 地址 | `OwnerCap<T>` 对象 |
| 转移所有权 | 更新地址字段 | 转移 `OwnerCap<T>` 对象 |
| 借出权限 | 无标准机制 | Receiving 模式 + ReturnReceipt |
| 服务器权限 | 硬编码地址 | `AdminACL`（可更新白名单） |
| 签名验证 | 无 | `ServerAddressRegistry` |

---

## 10. 安全陷阱：不要持有过多 OwnerCap

OwnerCap 是 `has key, store` 的，这意味着它可以被存入任何对象或表中。Builder 需要小心：

```
❌ 不好的设计：将 OwnerCap 存入公共共享对象
   → 任何人都可能借助某个漏洞调用

✅ 正确设计：
   - OwnerCap 存在部署者的个人钱包地址
   - 或通过 Character 的 Receiving 模式管理
   - 重要操作使用多签钱包配合 OwnerCap
```

更直白地说，`OwnerCap<T>` 应该被当成控制面密钥，而不是普通业务资产。它不该随便放进公共共享对象里，也不该为了“方便前端调用”而暴露给过多中间合约。你可以把它和运维里的 root key 类比：真正安全的系统不是没有 root key，而是 root key 极少出现、极少流转、出现时总伴随额外流程约束。

---

## 11. 实战练习

1. **权限分析**：列出 World 合约中所有需要 `admin_acl.verify_sponsor(ctx)` 的函数，分析哪些是玩家永远无法直接调用的
2. **OwnerCap 委托系统**：设计一个合约，让 Gate Owner 可以将部分权限（如修改通行费）委托给另一个地址，而不需要转移 OwnerCap 本身
3. **多签 OwnerCap 托管**：实现一个 2-of-3 多签账户，三个维护者需要其中两个同意才能修改建筑配置

---

## 本章小结

| 组件 | 层级 | 作用 |
|------|-----|------|
| `GovernorCap` | 最高（CCP） | 系统级配置，注册服务器 |
| `AdminACL` | 服务器层 | 游戏操作的函数调用授权 |
| `ServerAddressRegistry` | 服务器层 | Ed25519 签名来源验证 |
| `OwnerCap<T>` | 建筑层 | 泛型建筑控制权凭证 |
| Receiving 模式 | 玩家层 | OwnerCap 安全借用机制 |
| `ReturnOwnerCapReceipt` | 安全机制 | 强制 OwnerCap 归还，防丢失 |

---

## 课程完结

恭喜你完成了 **EVE Frontier Builder 完整课程**！

从基础的 Move 2024 语法，到链上 PvP 记录（KillMail），再到签名验证、位置证明、能量燃料系统、Extension 模式、炮塔 AI 和访问控制——你已经掌握了在 EVE Frontier 上构建复杂应用所需的全部核心知识。

**接下来的路**：
1. 加入 [EVE Frontier Builders Discord](https://discord.gg/evefrontier)
2. 在测试网部署属于你的第一个 Extension
3. 在游戏中找到属于你的星系，点亮一个 Smart Gate

> *在星际中建设，是一种文明的延伸。*
