# Chapter 4：智能组件开发与链上部署

> ⏱ 预计学习时间：2 小时
>
> **目标：** 理解每种智能组件的工作原理和 API，掌握从角色创建到合约部署的完整工作流。

---

## 4.1 完整的部署工作流

在你的代码能在真实游戏中生效之前，需要完成以下完整链路：

```
1. 创建链上角色 (Smart Character)
        ↓
2. 部署网络节点 (Network Node)，存入燃料并上线
        ↓
3. 锚定智能组件 (Anchor Assembly)
        ↓
4. 将组件上线 (Assembly Online)
        ↓
5. 编写并发布自定义 Move 扩展包
        ↓
6. 将扩展注册到组件 (authorize_extension)
        ↓
7. 玩家通过扩展 API 与组件交互
```

在本地开发中，步骤 1-5 可以用 `builder-scaffold` 的初始化脚本一键完成。

---

## 4.2 Smart Character（智能角色）

Smart Character 是你在链上的 **主体身份**，所有组件都归属于你的角色。

### 角色的链上结构

```move
public struct Character has key {
    id: UID,                        // 唯一对象 ID
    // 每个拥有的资产对应一个 OwnerCap
    // owner_caps 以 dynamic field 形式存储
}
```

### OwnerCap：资产所有权凭证

每当你拥有一个组件（网络节点/炮塔/星门/存储箱），角色就会持有对应的 `OwnerCap<T>` 对象。对该组件的所有写操作都需要先从角色中"借用"这个 OwnerCap：

```typescript
// TypeScript 脚本示例：借用 OwnerCap
const [ownerCap] = tx.moveCall({
    target: `${packageId}::character::borrow_owner_cap`,
    typeArguments: [`${packageId}::assembly::Assembly`],
    arguments: [tx.object(characterId), tx.object(ownerCapId)],
});

// ... 使用 ownerCap 执行操作 ...

// 用完必须归还
tx.moveCall({
    target: `${packageId}::character::return_owner_cap`,
    typeArguments: [`${packageId}::assembly::Assembly`],
    arguments: [tx.object(characterId), ownerCap],
});
```

> 💡 借用-归还 (Borrow & Return) 模式配合 Hot Potato 确保 OwnerCap 不会离开角色对象。

---

## 4.3 Network Node（网络节点）

### 什么是网络节点？

- 锚定在拉格朗日点（Lagrange Point）的能源站
- 为附近所有智能组件提供 **Energy（能量）**
- 每个组件上线时需要从网络节点"预留"一定量的能量

### 生命周期

```
Anchored（已锚定）
    ↓ depositFuel（存入燃料）
Fueled（已充能）
    ↓ online（上线）
Online（运行中）  ←→ offline（下线）
```

### 本地测试用的初始化脚本（来自 builder-scaffold）

```bash
# 在 builder-scaffold/ts-scripts 目录执行
pnpm setup:character      # 创建角色
pnpm setup:network-node   # 创建并启动网络节点
pnpm setup:assembly       # 创建并连接智能组件
```

---

## 4.4 Smart Storage Unit（智能存储单元）深度解析

### 两种仓库

| 仓库类型 | 持有者 | 容量 | 访问方式 |
|---------|--------|------|--------|
| **主仓库** (Primary) | 组件 Owner | 大 | `OwnerCap<StorageUnit>` |
| **临时仓库** (Ephemeral) | 交互角色 | 小 | 角色自己的 `OwnerCap` |

临时仓库用于非 Owner 的玩家与你的 SSU 交互（如：购买物品时先把物品转到临时仓库，玩家再取走）。

### 物品如何到达链上？

```
游戏内物品 → game_item_to_chain_inventory() → 链上 Item 对象
链上 Item 对象 → chain_item_to_game_inventory() → 游戏内物品（需要临近证明）
```

### 扩展 API 一览

```move
// 1. 注册扩展（Owner 调用）
public fun authorize_extension<Auth: drop>(
    storage_unit: &mut StorageUnit,
    owner_cap: &OwnerCap<StorageUnit>,
)

// 2. 扩展存入物品
public fun deposit_item<Auth: drop>(
    storage_unit: &mut StorageUnit,
    character: &Character,
    item: Item,
    _auth: Auth,           // Witness
    ctx: &mut TxContext,
)

// 3. 扩展取出物品
public fun withdraw_item<Auth: drop>(
    storage_unit: &mut StorageUnit,
    character: &Character,
    _auth: Auth,           // Witness
    type_id: u64,
    ctx: &mut TxContext,
): Item
```

---

## 4.5 Smart Gate（智能星门）深度解析

### 默认 vs 自定义行为

```
无扩展：任何人都可以跳跃
    ↓ authorize_extension<MyAuth>()
有扩展：玩家必须持有 JumpPermit 才能跳跃
```

### JumpPermit 机制

```move
// 跳跃许可证：有时效性的链上对象
public struct JumpPermit has key, store {
    id: UID,
    character_id: ID,
    route_hash: vector<u8>,   // A↔B 双向有效
    expires_at_timestamp_ms: u64,
}
```

**完整跳跃流程：**
1. 玩家调用你的扩展函数（例如 `pay_and_request_permit()`）
2. 扩展验证条件（检查代币、检查白名单等）
3. 扩展调用 `gate::issue_jump_permit()` 发放 Permit
4. Permit 转给玩家
5. 玩家调用 `gate::jump_with_permit()` 跃迁，Permit 被消耗

### 扩展 API

```move
// 注册扩展
public fun authorize_extension<Auth: drop>(
    gate: &mut Gate,
    owner_cap: &OwnerCap<Gate>,
)

// 发放跳跃许可（只有已注册的 Auth 类型才能调用）
public fun issue_jump_permit<Auth: drop>(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    _auth: Auth,
    expires_at_timestamp_ms: u64,
    ctx: &mut TxContext,
)

// 使用许可跳跃（消耗 JumpPermit）
public fun jump_with_permit(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    jump_permit: JumpPermit,
    admin_acl: &AdminACL,
    clock: &Clock,
    ctx: &mut TxContext,
)
```

---

## 4.6 Smart Turret（智能炮塔）深度解析

炮塔的扩展模式与星门类似，通过 Typed Witness 授权。

### 默认行为
炮塔使用游戏服务器提供的标准攻击逻辑。

### 自定义行为
Builder 可以注册扩展，改变炮塔的**目标判断**逻辑。例如：
- 允许持有特定 NFT 的角色安全通过
- 只攻击不在联盟名单里的角色
- 根据时间段开关攻击（白天开放，夜晚封闭）

---

## 4.7 将扩展发布并注册到组件

### 第一步：发布你的扩展包

```bash
# 在你的 Move 包目录下
sui client publish 

# 输出示例：
# Package ID: 0x1234abcd...
# Transaction Digest: HMNaf...
```

记下 **Package ID**，这是你的合约地址。

### 第二步：授权扩展到组件

通过 TypeScript 脚本（或 dApp 调用）将你的扩展注册：

```typescript
import { Transaction } from "@mysten/sui/transactions";

const tx = new Transaction();

// 从角色借用 OwnerCap
const [ownerCap] = tx.moveCall({
    target: `${WORLD_PACKAGE}::character::borrow_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::gate::Gate`],
    arguments: [tx.object(CHARACTER_ID), tx.object(OWNER_CAP_ID)],
});

// 授权扩展（告诉星门：允许 my_extension::custom_gate::Auth 类型调用）
tx.moveCall({
    target: `${WORLD_PACKAGE}::gate::authorize_extension`,
    typeArguments: [`${MY_PACKAGE}::custom_gate::Auth`],  // 你的 Witness 类型
    arguments: [tx.object(GATE_ID), ownerCap],
});

// 归还 OwnerCap
tx.moveCall({
    target: `${WORLD_PACKAGE}::character::return_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::gate::Gate`],
    arguments: [tx.object(CHARACTER_ID), ownerCap],
});

await client.signAndExecuteTransaction({ signer: keypair, transaction: tx });
```

### 第三步：验证注册成功

```bash
# 查询星门对象，确认扩展类型已被添加到 allowed_extensions
sui client object <GATE_ID>
```

---

## 4.8 使用 TypeScript 读取链上状态

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });

// 读取星门对象
const gateObject = await client.getObject({
    id: GATE_ID,
    options: { showContent: true },
});

console.log(gateObject.data?.content);

// GraphQL 查询所有指定类型的组件
const query = `
  query {
    objects(filter: { type: "${WORLD_PACKAGE}::gate::Gate" }) {
      nodes {
        address
        asMoveObject { contents { json } }
      }
    }
  }
`;
```

---

## 🔖 本章小结

| 部署步骤 | 关键操作 |
|---------|--------|
| 1. 角色 | 链上身份，持有所有 OwnerCap |
| 2. 网络节点 | 存燃料 → 上线 → 输出能量 |
| 3. 组件 | 锚定 → 连接节点 → 上线 |
| 4. 扩展包 | `sui client publish` |
| 5. 注册扩展 | `authorize_extension<MyAuth>(gate, owner_cap)` |
| 6. 玩家交互 | 调用你的 Entry functions，通过 Witness 调用世界合约 |

## 📚 延伸阅读

- [Smart Storage Unit 文档](../smart-assemblies/storage-unit/README.md)
- [Smart Gate 文档](../smart-assemblies/gate/README.md)
- [Interfacing with the World](../smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [builder-scaffold ts-scripts](https://github.com/evefrontier/builder-scaffold/tree/main/ts-scripts)
