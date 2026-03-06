# Chapter 6：所有权模型深度解析

> ⏱ 预计学习时间：2 小时
>
> **目标：** 深入理解 EVE Frontier 的能力对象体系，掌握 OwnerCap 的完整生命周期，学会设计安全的委托授权和所有权转移方案。

---

> 状态：设计进阶章节。正文以 OwnerCap、委托与所有权生命周期为主。

## 前置依赖

- 建议先读 [Chapter 3](./chapter-03.md)
- 建议先读 [Chapter 4](./chapter-04.md)

## 源码位置

- [book/src/code/chapter-06](./code/chapter-06)

## 关键测试文件

- 当前目录以所有权片段为主；建议重点对照 `snippets/`。

## 推荐阅读顺序

1. 先读 OwnerCap 生命周期
2. 再打开 [book/src/code/chapter-06](./code/chapter-06) 对照 Borrow-Use-Return 片段
3. 最后回看 [Chapter 30](./chapter-30.md) 的访问控制源码精读

## 验证步骤

1. 能画出 OwnerCap 借出和归还链路
2. 能区分所有权转移与临时借用
3. 能识别不安全的权限设计

## 常见报错

- 借出能力对象后忘记归还，导致后续事务逻辑不成立

---

## 6.1 为什么要有专门的所有权模型？

在传统区块链（如 Ethereum），所有权验证通常是：
```solidity
require(msg.sender == owner, "Not owner");
```

这个方法简单但有缺陷：
- **不可委托**：无法将权限安全地借给他人
- **不可组合**：权限检查散布代码各处，难以统一管理
- **不可分粒度**：要么是 owner，要么什么都不是

EVE Frontier 使用了 Sui 原生的 **Capability 对象体系**，解决了这些问题。

---

## 6.2 权限层级结构

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

---

## 6.3 Character 作为钥匙串（Keychain）

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

---

## 6.4 Borrow-Use-Return 完整模式

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

## 6.5 所有权转让场景

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

---

## 6.6 OwnerCap 的安全边界

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

### 丢失 OwnerCap 意味着失去控制权

如果 OwnerCap 所在的 Character 被转让，你就失去了对所有设施的控制。请**妥善保管你的 Character 对象的所有权私钥**。

---

## 6.7 高级：多签与联盟共有

通过 Sui 的多签（Multisig）功能，可以让一个联盟共同控制关键设施：

```bash
# 创建 2/3 多签地址（需要 3 个成员中的 2 个同意才能操作）
sui keytool multi-sig-address \
  --pks <pk1> <pk2> <pk3> \
  --weights 1 1 1 \
  --threshold 2
```

将 Character 的控制地址设置为多签地址，联盟关键资产就需要多人签名才能操作。

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
