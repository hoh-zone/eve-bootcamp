# Chapter 1：EVE Frontier 宏观架构与核心概念

> ⏱ 预计学习时间：2 小时
>
> **目标：** 理解 EVE Frontier 是什么，它为什么选择 Sui 区块链，以及"可编程宇宙"的核心哲学。

---

## 1.1 为什么 EVE Frontier 不一样？

传统网络游戏的世界规则由开发商独断——经济系统、战斗公式、内容更新，玩家只是参与者。EVE Frontier 挑战了这一范式：游戏的核心机制是**开放的**，开发者（Builders）可以在游戏服务器限定的框架内，真正**重写和扩展游戏规则**。

这不是简单的"MOD 插件"——你写下的逻辑会作为智能合约运行在 Sui 公链上，永久可查、无需中心化服务器托管、7×24 自动执行。

### 三种玩家角色

| 角色 | 主要动作 |
|------|--------|
| **Builder（构建者）** | 编写 Move 合约，部署智能组件，构建 dApp 界面 |
| **Operator（经营者）** | 购买/拥有设施，配置 Builder 的模块，经营经济势力 |
| **Player（玩家）** | 与 Builder/Operator 搭建的设施交互，组成游戏世界 |

> 本课程的目标受众是 **Builder**，但理解另外两个角色有助于你设计更有价值的产品。

---

## 1.2 智能组件 (Smart Assemblies)：可编程的星空基础设施

**Smart Assemblies** 是 EVE Frontier 中被玩家建造在太空中的物理设施。它们既是游戏对象，也是区块链上的可编程合约对象。

### 主要组件类型

#### 🏗 网络节点 (Network Node)
- 锚定在拉格朗日点（Lagrange Point）
- 为整个基地提供能源（Energy）
- 所有设施必须连接网络节点才能运行
- **不可直接编程**，但是其他组件的运行基础

#### 📦 智能存储单元 (Smart Storage Unit, SSU)
- 链上存储物品，支持"主仓库"与"临时仓库"（Ephemeral Inventory）
- 默认只允许 Owner 取放物品
- 通过自定义合约可变身为：自动售货机、拍卖行、公会金库

#### ⚡ 智能炮塔 (Smart Turret)
- 自动防御设施
- 默认行为是标准攻击逻辑
- 通过合约可自定义锁定目标的判断逻辑（例如：只攻击没有许可证的角色）

#### 🌀 智能星门 (Smart Gate)
- 链接两个位置，允许角色跃迁
- 默认所有人可跳跃
- 通过合约引入"跳跃许可证 (JumpPermit)"机制，可实现白名单、收费、时效控制等

---

## 1.3 三层架构：游戏世界是如何构建的？

EVE Frontier 的世界合约使用了严格的三层架构，这是理解后续所有内容的关键：

```
┌────────────────────────────────────────────────────┐
│  Layer 3: Player Extensions（玩家扩展层）              │
│  你写的 Move 合约就在这里                              │
└────────────────┬───────────────────────────────────┘
                 │  通过 Typed Witness Pattern 调用
┌────────────────▼───────────────────────────────────┐
│  Layer 2: Smart Assemblies（智能组件层）               │
│  storage_unit.move  gate.move  turret.move          │
└────────────────┬───────────────────────────────────┘
                 │  内部调用
┌────────────────▼───────────────────────────────────┐
│  Layer 1: Primitives（基础原语层）                     │
│  status  location  inventory  fuel  energy          │
└────────────────────────────────────────────────────┘
```

- **Layer 1 - 基础原语**：不可直接调用的底层模块，实现"数字物理学"（如位置、库存、燃料）
- **Layer 2 - 智能组件**：面向玩家开放的组件对象，每一个都是 Sui 共享对象（Shared Object）
- **Layer 3 - 玩家扩展**：**你作为 Builder 工作的地方**，通过类型见证（Typed Witness）安全插入自定义逻辑

> **关键理解**：你无法直接修改 Layer 1/2，但你可以在 Layer 3 编写逻辑，通过官方授权的 API 与组件交互。这既保证了游戏世界的安全性，又为 Builders 提供了足够的自由度。

---

## 1.4 为什么选择 Sui 区块链？

EVE Frontier 迁移到 Sui 不是偶然，而是深思熟虑的技术选型。

### Sui 的核心优势

| 特性 | 传统区块链 | Sui |
|------|-----------|-----|
| **资产模型** | 账户余额模型 | 以**对象(Object)**为中心，每个资产有唯一 ID 和所有权历史 |
| **并发处理** | 串行执行 | 独立对象可并行执行，极高吞吐量 |
| **Transaction 延迟** | 秒级到分钟级 | 亚秒级最终确认 |
| **玩家体验** | 需要管理助记词 | zkLogin：使用 Google/Twitch 账号登录 |
| **Gas 费** | 用户自付 | 支持赞助交易（Sponsored Tx），开发者可代付 |

### 对象模型意味着什么？

在 Sui 上，游戏内的**每一件物品、每一个角色、每一个组件**都是独立的链上对象，具有：
- 唯一的 `ObjectID`
- 明确的所有权（`owned by address` / `shared` / `owned by object`）
- 完整可追溯的操作历史

这使得去中心化的所有权、交易和游戏历史存档变成了天然成立的能力。

---

## 1.5 EVE Vault：你的身份与钱包

**EVE Vault** 是官方提供的浏览器扩展 + Web 钱包，是你作为 Builder 和玩家的数字身份。

### 核心功能

- 存储 LUX、EVE Token 及游戏内 NFT
- 通过 **zkLogin** 用 EVE Frontier SSO 账号创建 Sui 钱包，**无需管理助记词**
- 作为 dApp 连接协议，在游戏内和外部浏览器中授权第三方 dApp 访问
- FusionAuth OAuth 将游戏角色身份与钱包绑定

### 两种货币

| 货币 | 用途 |
|------|------|
| **LUX** | 游戏内主要交易货币，用于购买、服务、收费等 |
| **EVE Token** | 生态参与代币，用于开发者激励、特殊资产购买 |

---

## 1.6 可编程经济：Builder 的商业可能性

回顾一下 Builder 可以实现哪些真实的商业逻辑：

```
💰 经济系统
  ├── 自定义交易市场（自动撮合、竞价拍卖）
  ├── 联盟代币（基于 Sui 的 Fungible Token）
  └── 服务收费（星门通行费、存储租金）

🛡 安全与权限
  ├── 白名单访问控制（哪些玩家可以使用你的设施）
  └── 条件锁定（只有完成任务的角色才能提取物品）

🤖 自动化
  ├── 炮塔自定义锁定逻辑
  ├── 物品自动分发（任务奖励、空投）
  └── 跨设施联动（A 设施的行为触发 B 设施的响应）

🏗 基础设施服务
  ├── 第三方 dApp 读取链上状态
  └── 外部 API 联动（链外数据触发链上动作）
```

---

## 🔖 本章小结

| 学习点 | 核心概念 |
|--------|--------|
| EVE Frontier 的定位 | 真正开放的可编程宇宙，Builder 可改写游戏规则 |
| 智能组件类型 | Network Node / SSU / Turret / Gate |
| 三层架构 | Primitives → Assemblies → Player Extensions |
| 为什么用 Sui | 对象模型、并发、低延迟、zkLogin 无摩擦体验 |
| EVE Vault | 官方钱包 + 身份系统，基于 zkLogin |

## 📚 延伸阅读

- [Why Build on EVE Frontier?](../README.md)
- [Smart Infrastructure](../welcome/smart-infrastructure.md)
- [EVE Frontier World Explainer](../smart-contracts/eve-frontier-world-explainer.md)
- [Sui 文档：对象模型](https://docs.sui.io/concepts/object-ownership)
