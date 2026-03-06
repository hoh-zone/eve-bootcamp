# Chapter 4：智能组件开发与链上部署

> **目标：** 理解每种智能组件的工作原理和 API，掌握从角色创建到合约部署的完整工作流。

---

> 状态：基础章节。正文以部署工作流和链上组件操作为主。

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

很多人第一次接触这一章时，会误以为“发布合约”才是主流程。实际上不是。对 EVE Builder 来说，真正的主流程是：

1. 先有链上主体
2. 再有可运行的设施
3. 然后才有自定义扩展逻辑
4. 最后把扩展挂到设施上供玩家消费

也就是说，你写出来的 Move 包并不是凭空就能独立工作。它必须挂接到一个真实存在、已经上线、已经归属到角色体系中的智能组件上。

### 这一章最容易混淆的三个“ID”

在部署过程中，至少会同时出现三类 ID：

- **Package ID**
  代表你发布到链上的 Move 包
- **Object ID**
  代表具体对象，例如角色、星门、炮塔、存储箱
- **业务 ID**
  代表游戏服务器里的角色、物品、设施编号

这三者不要混：

- `Package ID` 决定“你的代码在哪里”
- `Object ID` 决定“你的设施和资产在哪里”
- 业务 ID 决定“游戏世界里的东西是谁”

后面你会频繁地在“代码地址”和“设施对象地址”之间来回切换。如果这两个概念不分开，调试时会非常痛苦。

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

### 为什么不是把 OwnerCap 直接取出来永久持有？

因为 `OwnerCap` 不是普通钥匙，而是高权限凭证。把它设计成“借用后必须归还”，有几个直接好处：

- 权限不会轻易脱离角色体系
- 一笔交易结束后，不会留下悬空的高权限对象
- 组件所有权仍然稳定地归属于角色，而不是散落到脚本地址或临时对象里

从设计上看，这相当于在链上实现了“临时提权”：

- 你先证明自己是角色的合法操作者
- 系统暂时借给你权限对象
- 你完成高权限操作后，必须把权限交还

这比“管理员地址硬编码”更灵活，也更适合游戏场景中的委托、转移、继承、换壳运营等需求。

### Character 在业务上到底扮演什么角色？

不要把 `Character` 只理解成钱包地址的别名。它更像一个链上“经营主体”：

- 组件挂在角色名下，而不是直接挂在钱包地址名下
- 角色内部可以统一管理多个 `OwnerCap`
- 角色可以作为链上权限和游戏内身份的桥梁

所以在很多 Builder 场景里，真正稳定的主体不是“哪个钱包点了按钮”，而是“哪个角色在经营这些设施”。

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

这里最重要的不是记住状态名字，而是理解：

> 设施能不能工作，不只是“合约有没有发布”，还取决于它在游戏世界里有没有被真正供能。

这正是 EVE Frontier 和普通 dApp 的一个关键差异。普通 dApp 里，合约发布成功后，理论上任何人都能调用；但在 EVE 里，很多设施的可用性还会受到“世界状态”的约束：

- 有没有网络节点
- 网络节点有没有燃料
- 设施有没有被正确锚定
- 设施是不是在线

### 从 Builder 视角看，Network Node 实际解决了什么？

它解决的是“设施不应该无条件永久在线”这个问题。

如果没有这层设计：

- 星门可以永远开放
- 炮塔可以永远工作
- 仓储设施可以一直响应

那游戏里的运营、维护、补给、占领都会失去很多意义。加入网络节点之后，设施就会变成一种真正需要维护的资产，而不是“一次部署永久印钞机”。

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

这里真正难的不是“调用哪个函数”，而是理解两边库存并不是简单镜像。

很多新手会默认认为：

- 游戏背包里有一把枪
- 上链后就只是“复制一条记录”

实际上正确理解更接近：

- 某件游戏内物品通过可信流程被映射成链上对象
- 这件对象之后进入链上库存体系
- 当它被取回游戏世界时，又需要经过另一条可信回流路径

所以 `Storage Unit` 的本质不是“链上柜子”，而是**链上与游戏世界之间的资产交换节点**。

### 为什么要区分主仓库和临时仓库？

因为很多交互都不是“Owner 自己打开仓库拿东西”，而是“第三方玩家和你的设施发生一次受控交互”。

比如自动售货机：

1. 玩家支付代币
2. 设施把对应物品先转入一个临时中间区
3. 玩家再从该路径领取

这样做的好处是：

- 不必把主仓库完全暴露给外部
- 交易中间态更容易审计
- 失败时更容易做回滚和结算

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

`JumpPermit` 的关键不在于“它是一张票”，而在于它把一次复杂判断拆成了两段：

1. 先决定“你有没有资格拿到票”
2. 再决定“你拿着票能不能执行跃迁”

这种拆法非常适合游戏规则扩展，因为“资格判断”可以很复杂：

- 你是不是白名单成员
- 你有没有付费
- 你是不是完成了前置任务
- 你是不是在有效时间窗内

但一旦票已经发出，真正执行跃迁时的逻辑就可以更标准、更统一。

这也是很多扩展设计的通用思路：

> 把复杂业务判断前移成“凭证发放”，把底层设施动作收敛成“凭证消费”。

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

### `authorize_extension` 到底在授权什么？

它授权的不是“某个地址”，也不是“某次交易”，而是**某种类型身份**。

也就是说，组件真正相信的是：

- 只有带着某个指定 witness 类型的调用
- 才能进入底层能力入口

这让组件扩展具备两个重要性质：

- 组件内核不用知道你的业务逻辑长什么样
- 但它可以非常明确地知道“哪些扩展类型有资格接入”

所以 Builder 的工作，很多时候不是“改官方逻辑”，而是“把自己的逻辑封装成官方允许接入的类型化扩展”。

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

发布完成后，你至少要立即记录三类信息：

- 你的 `Package ID`
- 你要绑定的组件对象 ID
- 交易 digest

因为后面排查问题时，几乎所有链路都要从这三样东西往回追：

- 合约有没有成功发布
- 设施是不是你以为的那个对象
- 这次授权或注册到底有没有成功上链

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

这里要特别注意一件事：

> “发布成功”不等于“扩展已经生效”。

你至少还要确认三层绑定关系都成立：

1. 你的包已经在链上
2. 你的组件对象是正确的那个组件
3. 组件已经把你的 witness 类型加入允许列表

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

### 为什么部署章节里还要讲读取状态？

因为实际开发中，部署和读取从来不是两件分开的事。你每做完一步，都需要立刻验证：

- 对象有没有创建出来
- 状态有没有切到在线
- 扩展有没有注册成功
- 组件字段有没有按预期变化

所以真实节奏通常是：

```text
执行一步
  -> 立刻读链上状态
  -> 确认对象和字段变化
  -> 再继续下一步
```

如果你只会“发交易”，不会“立刻验证状态”，那你很难判断到底是：

- 交易没发出去
- 发出去了但对象不对
- 对象对了但状态没变
- 状态变了但前端查错了地方

### 从开发者视角看，本章的最小闭环是什么？

最小闭环不是“我发布了一个包”，而是：

1. 有角色
2. 有设施
3. 有权限凭证
4. 有自定义扩展包
5. 有成功注册记录
6. 有一次真实可验证的玩家交互

只有这 6 件事都打通，你才算真正完成了一个 Builder 设施扩展。

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

- [Smart Storage Unit 文档](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/storage-unit/README.md)
- [Smart Gate 文档](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/gate/README.md)
- [Interfacing with the World](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [builder-scaffold ts-scripts](https://github.com/evefrontier/builder-scaffold/tree/main/ts-scripts)
