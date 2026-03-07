# Chapter 11：所有权模型深度解析

> **目标：** 深入理解 EVE Frontier 的能力对象体系，掌握 OwnerCap 的完整生命周期，学会设计安全的委托授权和所有权转移方案。

---

> 状态：设计进阶章节。正文以 OwnerCap、委托与所有权生命周期为主。

##  11.1 为什么要有专门的所有权模型？

很多新手在第一次设计权限系统时，直觉都是：

- 记录一个 owner 地址
- 每次操作时检查调用者是不是这个地址

这种方式短期很省事，但一旦进入 EVE Frontier 这类“设施可经营、可转移、可委托、可组合”的世界，很快就会暴露问题：

- **不可委托**
  你很难安全地把部分权力临时交给别人
- **不可组合**
  权限规则散在各个函数里，系统越做越乱
- **不可细粒度表达**
  很难表达“可以操作这个炮塔，但不能操作那个星门”
- **不可自然转移**
  一旦设施、角色、经营权发生迁移，地址硬编码会变得很脆

EVE Frontier 使用的是 Sui 原生的 **Capability 对象体系**。它的核心思想不是“看你是谁”，而是：

> 看你手里拿着哪一个权限对象。

这会让所有权从“账户属性”变成“可组合、可转移、可验证的链上实体”。

---

##  11.2 权限层级结构

```
GovernorCap（部署者持有 — 最高权限）
    │
    └── AdminACL（共享对象 — 授权的服务器地址列表）
            │
            └── OwnerCap<T>（玩家持有 — 对特定对象的操作权）
```

### GovernorCap：游戏运营层

`GovernorCap` 在合约部署时创建，由 CCP Games（游戏运营方）持有。它可以：
- 向 `AdminACL` 添加/删除服务器授权地址
- 执行全局配置更改

作为 Builder，你无需关心 `GovernorCap`。

### AdminACL：服务器授权层

`AdminACL` 是一个**共享对象**，包含被授权的游戏服务器地址列表。

某些操作（如临近证明、跃迁验证）需要游戏服务器作为**赞助者（Sponsor）**签署交易：

```move
// 验证调用者是否为授权赞助者
public fun verify_sponsor(admin_acl: &AdminACL, ctx: &TxContext) {
    assert!(
        admin_acl.sponsors.contains(ctx.sponsor().unwrap()),
        EUnauthorizedSponsor
    );
}
```

这意味着：某些敏感操作玩家不能单独完成，必须经过游戏服务器验证。

### OwnerCap：玩家操作层

```move
public struct OwnerCap<phantom T> has key {
    id: UID,
    authorized_object_id: ID,  // 只对这一个具体对象有效
}
```

`phantom T` 使得 `OwnerCap<Gate>` 和 `OwnerCap<StorageUnit>` 是完全不同的类型，无法混用——这是类型系统级别的安全保证。

### 这三层权限为什么要分开？

你可以把它理解成三种完全不同的职责：

- **GovernorCap**
  解决“世界级规则和全局治理”
- **AdminACL**
  解决“哪些服务器或后端流程被信任”
- **OwnerCap**
  解决“具体哪个经营主体可以操作哪个设施”

把它们拆开最大的好处是：系统不会把“全局治理权”和“单设施操作权”混成一锅。

否则你很容易出现这种糟糕结构：

- 一个地址既是服务器授权者
- 又是所有设施管理员
- 又是某些临时业务的执行者

一旦这个地址出问题，整个系统的权限边界都会塌掉。

---

##  11.3 Character 作为钥匙串（Keychain）

玩家的所有 `OwnerCap` 都存储在 **Character 对象**中，而不是直接发给钱包地址。

```
玩家钱包地址
    └── Character（共享对象，映射到钱包地址）
            ├── OwnerCap<NetworkNode>  → 网络节点 0x...a1
            ├── OwnerCap<Gate>         → 星门 0x...b2
            ├── OwnerCap<StorageUnit>  → 存储箱 0x...c3
            └── OwnerCap<Gate>         → 星门 0x...d4（第二个星门）
```

**为什么这样设计？**
- 所有资产的所有权集中于 Character，转让 Character 等于转让所有资产
- 即使玩家更换钱包地址，Character 还在，资产不丢失
- 与联盟机制配合，可以实现集体所有权管理

这里要特别注意一件事：

> Character 不是简单的钱包映射层，而是一个真正的权限容器。

它把“人、角色、设施、权限”这几个维度组织在了一起：

- 钱包是签名入口
- Character 是经营主体
- OwnerCap 是具体设施权限
- 设施对象是被控制的资产

这样的好处是，当你以后做：

- 账号迁移
- 多签控制
- 联盟托管
- 角色转让

你不需要重写一整套权限系统，而是围绕 `Character` 这层做变更。

---

##  11.4 Borrow-Use-Return 完整模式

执行任何需要 OwnerCap 的操作，都必须遵循「借用 → 使用 → 归还」三步原子事务：

```move
// Character 模块提供的接口
public fun borrow_owner_cap<T: key>(
    character: &mut Character,
    owner_cap_ticket: Receiving<OwnerCap<T>>,  // 使用 Receiving 模式
    ctx: &TxContext,
): (OwnerCap<T>, ReturnOwnerCapReceipt)        // 返回 Cap + 热土豆收据

public fun return_owner_cap<T: key>(
    character: &Character,
    owner_cap: OwnerCap<T>,
    receipt: ReturnOwnerCapReceipt,             // 必须消耗收据
)
```

`ReturnOwnerCapReceipt` 是一个热土豆（无 Abilities），确保 OwnerCap **必须被归还**，不能在交易外流失。

### 这个模式真正防的是什么？

它不是单纯为了“写法优雅”，而是在防几类非常真实的风险：

- 高权限对象在交易中途被截留
- 脚本忘记归还权限，留下悬空状态
- 扩展逻辑把权限对象带进了不该到达的路径
- 多步骤操作中，权限边界变得不再可审计

把 `borrow -> use -> return` 强制收束在同一笔事务里，相当于给高权限操作加了一条硬约束：

> 你可以临时拿来做事，但不能把它带走。

### 为什么要配合 Hot Potato Receipt？

因为只靠“开发者自觉调用 return”是不够的。

只要类型系统允许你漏掉归还步骤，迟早会有人：

- 在脚本里忘掉
- 在重构时删掉
- 在错误分支里直接 `return`

加入 receipt 之后，编译器和类型系统会一起逼你把流程走完。

### 完整 TypeScript 调用示例

```typescript
import { Transaction } from "@mysten/sui/transactions";

const WORLD_PKG = "0x...";

async function bringGateOnline(
  tx: Transaction,
  characterId: string,
  ownerCapId: string,
  gateId: string,
  networkNodeId: string,
) {
  // ① 借用 OwnerCap
  const [ownerCap, receipt] = tx.moveCall({
    target: `${WORLD_PKG}::character::borrow_owner_cap`,
    typeArguments: [`${WORLD_PKG}::gate::Gate`],
    arguments: [
      tx.object(characterId),
      tx.receivingRef({ objectId: ownerCapId, version: "...", digest: "..." }),
    ],
  });

  // ② 使用 OwnerCap：将星门上线
  tx.moveCall({
    target: `${WORLD_PKG}::gate::online`,
    arguments: [
      tx.object(gateId),
      tx.object(networkNodeId),
      tx.object(ENERGY_CONFIG_ID),
      ownerCap,
    ],
  });

  // ③ 归还 OwnerCap（receipt 被消耗，热土豆使此步不可跳过）
  tx.moveCall({
    target: `${WORLD_PKG}::character::return_owner_cap`,
    arguments: [tx.object(characterId), ownerCap, receipt],
  });
}
```

---

##  11.5 所有权转让场景

### 场景一：转让单个组件的控制权

如果你想把一个星门的控制权交给盟友（但保留你的 Character 和其他设施），可以只转让对应的 `OwnerCap`：

```typescript
// 从你的 Character 取出 OwnerCap，发给盟友
const tx = new Transaction();

// 取出 OwnerCap（注意这里不是借用，而是转移）
// 具体 API 以世界合约为准，此处仅展示思路
tx.moveCall({
  target: `${WORLD_PKG}::character::transfer_owner_cap`,
  typeArguments: [`${WORLD_PKG}::gate::Gate`],
  arguments: [
    tx.object(myCharacterId),
    tx.object(ownerCapId),
    tx.pure.address(allyAddress),  // 盟友的 Character 地址
  ],
});
```

### 场景二：转让完整角色（所有资产打包转让）

转移整个 Character 对象，则对应钱包地址即可控制所有绑定资产。适合联盟整体资产交割、账号交易等场景。

这里要区分三件听起来很像、但完全不同的动作：

- **转让单个 OwnerCap**
  只交出某一个设施的控制权
- **转让 Character**
  把一整串权限和资产一起交出去
- **委托操作**
  不转移所有权，只给对方有限操作能力

如果这三件事不分开，你的产品设计会很快乱掉。

比如联盟金库场景：

- 财产权可能属于联盟主体
- 日常操作权可能属于值班成员
- 紧急停机权可能只属于核心管理员

这就要求你不能只用“一个 owner”去表达全部关系。

### 场景三：委托操作（不转让所有权）

通过编写扩展合约，可以允许特定地址在**有限范围内**操作你的设施，而无需转让 OwnerCap：

```move
// 在你的扩展合约中，维护一个操作员白名单
public struct OperatorRegistry has key {
    id: UID,
    operators: Table<address, bool>,
}

public fun delegated_action(
    registry: &OperatorRegistry,
    ctx: &TxContext,
) {
    // 验证调用者在操作员名单中
    assert!(registry.operators.contains(ctx.sender()), ENotOperator);
    // ... 执行操作
}
```

### 委托最容易踩的坑

很多人第一次做委托，会把白名单当成“弱化版所有权”。这是不够的。

一个安全的委托设计，至少要回答：

- 委托人能做哪些动作，不能做哪些动作？
- 委托有没有时间限制？
- 委托能不能撤销？
- 委托是不是只对某一个设施有效？
- 被委托人能不能再次转授？

如果这些边界没有写清，委托就会从“灵活授权”变成“隐形送权”。

---

##  11.6 OwnerCap 的安全边界

### 每个 OwnerCap 只对一个对象有效

```move
public fun verify_owner_cap<T: key>(
    obj: &T,
    owner_cap: &OwnerCap<T>,
) {
    // authorized_object_id 确保这个 OwnerCap 只能用于对应的那个对象
    assert!(
        owner_cap.authorized_object_id == object::id(obj),
        EOwnerCapMismatch
    );
}
```

这意味着如果你有两个星门，就有两个 `OwnerCap<Gate>`，它们不能互换使用。

### 为什么 `authorized_object_id` 这么关键？

因为 `phantom T` 只解决了“对象类别不能混用”，但还没解决“同类不同实例不能混用”。

例如：

- `OwnerCap<Gate>` 只能用于 Gate，没有问题
- 但如果没有 `authorized_object_id`
  你的一张 Gate 权限就可能错误地操作另一座 Gate

所以完整安全边界其实是两层：

1. **类型边界**
   `Gate` 和 `StorageUnit` 不能混
2. **实例边界**
   这座 Gate 和那座 Gate 也不能混

### 丢失 OwnerCap 意味着失去控制权

如果 OwnerCap 所在的 Character 被转让，你就失去了对所有设施的控制。请**妥善保管你的 Character 对象的所有权私钥**。

从运营角度看，更准确地说，你要保护的不是“某个按钮权限”，而是整条经营控制链：

- 钱包签名权
- Character 控制权
- Character 内部的 OwnerCap 集合
- 关键委托配置和多签设置

一旦这条链断掉，恢复成本会非常高。

---

##  11.7 高级：多签与联盟共有

通过 Sui 的多签（Multisig）功能，可以让一个联盟共同控制关键设施：

```bash
# 创建 2/3 多签地址（需要 3 个成员中的 2 个同意才能操作）
sui keytool multi-sig-address \
  --pks <pk1> <pk2> <pk3> \
  --weights 1 1 1 \
  --threshold 2
```

将 Character 的控制地址设置为多签地址，联盟关键资产就需要多人签名才能操作。

### 多签适合什么，不适合什么？

多签非常适合：

- 联盟金库
- 超高价值基础设施
- 关键参数调整
- 升级与紧急停机

多签不一定适合：

- 高频日常操作
- 玩家需要秒级响应的交互
- 大量小额重复管理动作

所以现实做法通常不是“全部都上多签”，而是分层：

- 核心控制权放多签
- 日常运营权限通过受限委托释放给执行层

这才更接近真实组织结构。

---

## 🔖 本章小结

| 概念 | 核心要点 |
|------|--------|
| 权限层级 | GovernorCap > AdminACL > OwnerCap<T> |
| Character 钥匙串 | 所有 OwnerCap 集中存储，转让 Character = 转让所有资产 |
| Borrow-Use-Return | 三步原子操作，ReturnReceipt（热土豆）确保必须归还 |
| 类型安全 | `OwnerCap<Gate>` ≠ `OwnerCap<StorageUnit>`，无法混用 |
| 委托操作 | 通过扩展合约 + 白名单实现，无需转让 OwnerCap |
| 多签 | Sui 原生多签地址适合联盟共有资产场景 |

## 📚 延伸阅读

- [Ownership Model 文档](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/ownership-model.md)
- [Smart Character 文档](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/smart-character.md)
- [character.move 源码](https://github.com/evefrontier/world-contracts/blob/main/contracts/world/sources/character/character.move)
- [Sui 多签文档](https://docs.sui.io/guides/developer/cryptography/multisig)
- [Receiving 对象模式](https://docs.sui.io/guides/developer/objects/transfers/transfer-to-object)
