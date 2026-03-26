# EVE Frontier Builder Course

> **Choose your language / 选择语言:**
> [🇬🇧 English](./README.md#english) | [🇨🇳 中文](./README.md#中文)

---

## English

### Complete EVE Frontier Builder Course

> Approximately **2 hours per lesson**, **54 total lessons**: 36 core chapters + 18 practical case studies, covering gameplay understanding, Builder engineering workflow, World contract source code analysis, and wallet integration.

**Build Status:**
```bash
# Build both languages + language picker (recommended)
./build.sh

# Or build one language (mdbook 0.4.x has no --config-file; use env overrides)
mdbook build                                          # English → book/en/
MDBOOK_BOOK__SRC=src/zh MDBOOK_BOOK__LANGUAGE=zh-CN MDBOOK_BUILD__BUILD_DIR=book/zh mdbook build
```

### Chapter Overview

#### Prelude

| Chapter | File | Summary |
|---------|------|---------|
| Prelude | [chapter-00.md](./src/en/chapter-00.md) | Understanding EVE Frontier: what players compete for, why facilities matter, how location, combat, logistics and economy form complete gameplay |

#### Stage 1: Fundamentals (Chapters 1-5)

| Chapter | File | Summary |
|---------|------|---------|
| Chapter 1 | [chapter-01.md](./src/en/chapter-01.md) | EVE Frontier macro architecture: three-tier model, smart component types, Sui/Move rationale |
| Chapter 2 | [chapter-02.md](./src/en/chapter-02.md) | Development environment setup: Sui CLI, EVE Vault, test asset acquisition and minimal acceptance |
| Chapter 3 | [chapter-03.md](./src/en/chapter-03.md) | Move contract basics: modules, Abilities, object ownership, Capability/Witness/Hot Potato |
| Chapter 4 | [chapter-04.md](./src/en/chapter-04.md) | Smart component development and on-chain deployment: characters, network nodes, turrets, stargates, storage box transformation |
| Chapter 5 | [chapter-05.md](./src/en/chapter-05.md) | dApp frontend development: dapp-kit SDK, React Hooks, wallet integration, on-chain transactions |

**Paired Examples:** [Example 1](./src/en/example-01.md) Turret Whitelist, [Example 2](./src/en/example-02.md) Stargate Toll Station

#### Stage 2: Builder Engineering Workflow (Chapters 6-10)

| Chapter | File | Summary |
|---------|------|---------|
| Chapter 6 | [chapter-06.md](./src/en/chapter-06.md) | Builder Scaffold entry: project structure, smart_gate architecture, compilation and publication |
| Chapter 7 | [chapter-07.md](./src/en/chapter-07.md) | TypeScript scripts and frontend: helper.ts, script pipeline, React dApp template |
| Chapter 8 | [chapter-08.md](./src/en/chapter-08.md) | Server-side collaboration: Sponsored Tx, AdminACL, on-chain/off-chain coordination |
| Chapter 9 | [chapter-09.md](./src/en/chapter-09.md) | Data reading: GraphQL, event subscription, indexer approaches |
| Chapter 10 | [chapter-10.md](./src/en/chapter-10.md) | dApp wallet integration: useConnection, sponsored transactions, Epoch handling |

**Paired Examples:** [Example 4](./src/en/example-04.md) Quest Unlock System, [Example 11](./src/en/example-11.md) Item Rental System

#### Stage 3: Advanced Contract Design (Chapters 11-17)

| Chapter | File | Summary |
|---------|------|---------|
| Chapter 11 | [chapter-11.md](./src/en/chapter-11.md) | Ownership model deep dive: OwnerCap, Keychain, Borrow-Use-Return, delegation |
| Chapter 12 | [chapter-12.md](./src/en/chapter-12.md) | Advanced Move: generics, dynamic fields, event system, Table and VecMap |
| Chapter 13 | [chapter-13.md](./src/en/chapter-13.md) | NFT design and metadata management: Display standard, dynamic NFT, Collection patterns |
| Chapter 14 | [chapter-14.md](./src/en/chapter-14.md) | On-chain economic system design: token issuance, decentralized marketplace, dynamic pricing, treasury |
| Chapter 15 | [chapter-15.md](./src/en/chapter-15.md) | Cross-contract composability: calling other Builders' contracts, interface design, protocol standards |
| Chapter 16 | [chapter-16.md](./src/en/chapter-16.md) | Location and proximity systems: hash location, proximity proof, geographic strategy design |
| Chapter 17 | [chapter-17.md](./src/en/chapter-17.md) | Testing, debugging and security audit: Move unit tests, vulnerability types, upgrade strategies |

**Paired Examples:** [Example 3](./src/en/example-03.md) On-chain Auction, [Example 6](./src/en/example-06.md) Dynamic NFT, [Example 7](./src/en/example-07.md) Stargate Logistics Network, [Example 9](./src/en/example-09.md) Cross-Builder Protocol, [Example 13](./src/en/example-13.md) Subscription Pass, [Example 14](./src/en/example-14.md) NFT Staking Lending, [Example 16](./src/en/example-16.md) NFT Crafting/Decomposition, [Example 18](./src/en/example-18.md) Inter-Alliance Diplomatic Treaty

#### Stage 4: Architecture, Integration and Product (Chapters 18-25)

| Chapter | File | Summary |
|---------|------|---------|
| Chapter 18 | [chapter-18.md](./src/en/chapter-18.md) | Multi-tenancy and game server integration: Tenant model, ObjectRegistry, server-side scripts |
| Chapter 19 | [chapter-19.md](./src/en/chapter-19.md) | Full-stack dApp architecture design: state management, real-time updates, multi-chain support, CI/CD |
| Chapter 20 | [chapter-20.md](./src/en/chapter-20.md) | In-game integration: overlay UI, postMessage, game event bridging |
| Chapter 21 | [chapter-21.md](./src/en/chapter-21.md) | Performance optimization and Gas minimization: transaction batching, read-write separation, off-chain computation |
| Chapter 22 | [chapter-22.md](./src/en/chapter-22.md) | Advanced Move patterns: upgrade compatibility design, dynamic field extension, data migration |
| Chapter 23 | [chapter-23.md](./src/en/chapter-23.md) | Publishing, maintenance and community collaboration: mainnet deployment, Package upgrade, Builder collaboration |
| Chapter 24 | [chapter-24.md](./src/en/chapter-24.md) | Troubleshooting handbook: common Move, Sui, dApp error types and systematic debugging methods |
| Chapter 25 | [chapter-25.md](./src/en/chapter-25.md) | From Builder to product: business models, user growth, community operations, progressive decentralization |

**Paired Examples:** [Example 5](./src/en/example-05.md) Alliance DAO, [Example 12](./src/en/example-12.md) Alliance Recruitment, [Example 15](./src/en/example-15.md) PvP Item Insurance, [Example 17](./src/en/example-17.md) In-Game Overlay Practice

#### Stage 5: World Contract Source Code Analysis (Chapters 26-32)

> Based on real source code from [world-contracts](https://github.com/evefrontier/world-contracts), deep dive into EVE Frontier core system mechanisms.

| Chapter | File | Summary |
|---------|------|---------|
| Chapter 26 | [chapter-26.md](./src/en/chapter-26.md) | Complete access control analysis: GovernorCap, AdminACL, OwnerCap, Receiving pattern |
| Chapter 27 | [chapter-27.md](./src/en/chapter-27.md) | Off-chain signature × on-chain verification: Ed25519, PersonalMessage intent, sig_verify analysis |
| Chapter 28 | [chapter-28.md](./src/en/chapter-28.md) | Location proof protocol: LocationProof, BCS deserialization, proximity verification practice |
| Chapter 29 | [chapter-29.md](./src/en/chapter-29.md) | Energy and fuel system: EnergySource, fuel consumption rate calculation, known bug analysis |
| Chapter 30 | [chapter-30.md](./src/en/chapter-30.md) | Extension pattern practice: official tribe_permit + corpse_gate_bounty analysis |
| Chapter 31 | [chapter-31.md](./src/en/chapter-31.md) | Turret AI extension: TargetCandidate, priority queue, custom AI development |
| Chapter 32 | [chapter-32.md](./src/en/chapter-32.md) | KillMail system: PvP kill records, TenantItemId, derived_object replay prevention |

**Paired Examples:** [Example 8](./src/en/example-08.md) Builder Competition System, [Example 10](./src/en/example-10.md) Comprehensive Practice

#### Stage 6: Wallet Internals and Future (Chapters 33-35)

> After learning wallet integration and dApp development, dive deep into wallet internals and future directions for a smoother learning curve.

| Chapter | File | Summary |
|---------|------|---------|
| Chapter 33 | [chapter-33.md](./src/en/chapter-33.md) | zkLogin principles and design: zero-knowledge proofs, FusionAuth OAuth, Enoki salt, ephemeral key pairs |
| Chapter 34 | [chapter-34.md](./src/en/chapter-34.md) | Technical architecture and deployment: Chrome MV3 five-layer structure, Keeper security container, messaging protocol, local build |
| Chapter 35 | [chapter-35.md](./src/en/chapter-35.md) | Future outlook: zero-knowledge proofs, fully decentralized games, EVM interoperability |

**Paired Suggestion:** After completing this stage, review [Example 17](./src/en/example-17.md) for wallet connection, signing, and in-game integration pipeline.

---

### Case Study Index

#### Beginner Cases (Examples 1-3)

| Example | File | Technical Highlights |
|---------|------|---------------------|
| Example 1 | [example-01.md](./src/en/example-01.md) | Turret whitelist: MiningPass NFT + AdminCap + management dApp |
| Example 2 | [example-02.md](./src/en/example-02.md) | Stargate toll station: vault contract + JumpPermit + player ticket dApp |
| Example 3 | [example-03.md](./src/en/example-03.md) | On-chain auction: Dutch pricing + auto settlement + real-time countdown dApp |

#### Intermediate Cases (Examples 4-7)

| Example | File | Technical Highlights |
|---------|------|---------------------|
| Example 4 | [example-04.md](./src/en/example-04.md) | Quest unlock system: on-chain flag quests + off-chain monitoring + conditional stargate |
| Example 5 | [example-05.md](./src/en/example-05.md) | Alliance DAO: custom Coin + snapshot dividends + weighted governance voting |
| Example 6 | [example-06.md](./src/en/example-06.md) | Dynamic NFT: evolvable equipment with metadata updating based on game state |
| Example 7 | [example-07.md](./src/en/example-07.md) | Stargate logistics network: multi-hop routing + Dijkstra pathfinding + dApp |

#### Advanced Cases (Examples 8-10)

| Example | File | Technical Highlights |
|---------|------|---------------------|
| Example 8 | [example-08.md](./src/en/example-08.md) | Builder competition system: on-chain leaderboard + points + trophy NFT auto-distribution |
| Example 9 | [example-09.md](./src/en/example-09.md) | Cross-Builder protocol: adapter pattern + multi-contract aggregated marketplace |
| Example 10 | [example-10.md](./src/en/example-10.md) | Comprehensive practice: space resource battle (integrating characters, turrets, stargates, tokens) |

#### Extension Cases (Examples 11-15)

| Example | File | Technical Highlights |
|---------|------|---------------------|
| Example 11 | [example-11.md](./src/en/example-11.md) | Item rental system: time-locked NFT + deposit management + early return refund |
| Example 12 | [example-12.md](./src/en/example-12.md) | Alliance recruitment: application deposit + member voting + veto power + auto NFT issuance |
| Example 13 | [example-13.md](./src/en/example-13.md) | Subscription pass: monthly/quarterly packages + transferable Pass NFT + renewal |
| Example 14 | [example-14.md](./src/en/example-14.md) | NFT staking lending: 60% LTV + 3% monthly interest + overdue liquidation auction |
| Example 15 | [example-15.md](./src/en/example-15.md) | PvP item insurance: purchase policy + server signature claims + payout pool |

#### Advanced Extension (Examples 16-18)

| Example | File | Technical Highlights |
|---------|------|---------------------|
| Example 16 | [example-16.md](./src/en/example-16.md) | NFT crafting/decomposition: three-tier item system + on-chain randomness + consolation mechanism |
| Example 17 | [example-17.md](./src/en/example-17.md) | In-game overlay practice: in-game toll station + postMessage + seamless signing |
| Example 18 | [example-18.md](./src/en/example-18.md) | Inter-alliance diplomatic treaty: dual signature activation + deposit constraint + breach evidence and penalties |

---

### Idea Library

- [100 Sui Core Feature Ideas](./src/en/idea/README.md)
- [100 General Comprehensive Ideas](./src/en/idea_general/README.md)

---

### Getting Started

- [Course Homepage](./src/en/index.md)
- [Table of Contents](./src/en/SUMMARY.md)
- [Glossary](./src/en/glossary.md)
- [Code Examples Guide](./src/code/README.md)

---

### Reference Resources

- [Official builder-documentation](https://github.com/evefrontier/builder-documentation)
- [builder-scaffold](https://github.com/evefrontier/builder-scaffold)
- [World Contracts Source](https://github.com/evefrontier/world-contracts)
- [EVE Vault](https://github.com/evefrontier/evevault)
- [Sui Documentation](https://docs.sui.io)
- [Move Book](https://move-book.com)
- [EVE Frontier dapp-kit API](http://sui-docs.evefrontier.com/)
- [Sui GraphQL IDE (Testnet)](https://graphql.testnet.sui.io/graphql)
- [EVE Frontier Discord](https://discord.com/invite/evefrontier)

---
---

## 中文

### EVE Frontier 构建者完整课程

> 每节课约 **2 小时**,共 **54 节**:36 个基础章节 + 18 个实战案例,覆盖从玩法理解、Builder 工程闭环,到 World 合约源码精读与钱包接入。

**构建方式:**
```bash
# 同时构建双语与入口页（推荐）
./build.sh

# 或单独构建一种语言（mdbook 0.4.x 无 --config-file，用环境变量覆盖）
mdbook build                                          # 英文 → book/en/
MDBOOK_BOOK__SRC=src/zh MDBOOK_BOOK__LANGUAGE=zh-CN MDBOOK_BUILD__BUILD_DIR=book/zh mdbook build
```

### 章节主线

#### 前置章节

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Prelude | [chapter-00.md](./src/zh/chapter-00.md) | 先读懂 EVE Frontier 这款游戏:玩家在争夺什么、设施为什么重要、位置、战损、物流和经济如何串成完整玩法 |

#### 第一阶段:入门基础(Chapter 1-5)

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 1 | [chapter-01.md](./src/zh/chapter-01.md) | EVE Frontier 宏观架构:三层模型、智能组件类型、Sui/Move 选型 |
| Chapter 2 | [chapter-02.md](./src/zh/chapter-02.md) | 开发环境配置:Sui CLI、EVE Vault、测试资产获取与最小验收 |
| Chapter 3 | [chapter-03.md](./src/zh/chapter-03.md) | Move 合约基础:模块、Abilities、对象所有权、Capability/Witness/Hot Potato |
| Chapter 4 | [chapter-04.md](./src/zh/chapter-04.md) | 智能组件开发与链上部署:角色、网络节点、炮塔、星门、存储箱改造全流程 |
| Chapter 5 | [chapter-05.md](./src/zh/chapter-05.md) | dApp 前端开发:dapp-kit SDK、React Hooks、钱包集成、链上交易 |

配套实战:[Example 1](./src/zh/example-01.md) 炮塔白名单、[Example 2](./src/zh/example-02.md) 星门收费站

#### 第二阶段:Builder 工程闭环(Chapter 6-10)

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 6 | [chapter-06.md](./src/zh/chapter-06.md) | Builder Scaffold 入口:项目结构、smart_gate 架构、编译与发布 |
| Chapter 7 | [chapter-07.md](./src/zh/chapter-07.md) | TS 脚本与前端:helper.ts、脚本链路、React dApp 模板 |
| Chapter 8 | [chapter-08.md](./src/zh/chapter-08.md) | 服务端协同:Sponsored Tx、AdminACL、链上链下配合 |
| Chapter 9 | [chapter-09.md](./src/zh/chapter-09.md) | 数据读取:GraphQL、事件订阅、索引器思路 |
| Chapter 10 | [chapter-10.md](./src/zh/chapter-10.md) | dApp 钱包接入:useConnection、赞助交易、Epoch 处理 |

配套实战:[Example 4](./src/zh/example-04.md) 任务解锁系统、[Example 11](./src/zh/example-11.md) 物品租赁系统

#### 第三阶段:合约设计进阶(Chapter 11-17)

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 11 | [chapter-11.md](./src/zh/chapter-11.md) | 所有权模型深度解析:OwnerCap、Keychain、Borrow-Use-Return、委托 |
| Chapter 12 | [chapter-12.md](./src/zh/chapter-12.md) | Move 进阶:泛型、动态字段、事件系统、Table 与 VecMap |
| Chapter 13 | [chapter-13.md](./src/zh/chapter-13.md) | NFT 设计与元数据管理:Display 标准、动态 NFT、Collection 模式 |
| Chapter 14 | [chapter-14.md](./src/zh/chapter-14.md) | 链上经济系统设计:代币发行、去中心化市场、动态定价、金库 |
| Chapter 15 | [chapter-15.md](./src/zh/chapter-15.md) | 跨合约组合性:调用其他 Builder 的合约、接口设计、协议标准 |
| Chapter 16 | [chapter-16.md](./src/zh/chapter-16.md) | 位置与临近性系统:哈希位置、临近证明、地理策略设计 |
| Chapter 17 | [chapter-17.md](./src/zh/chapter-17.md) | 测试、调试与安全审计:Move 单元测试、漏洞类型、升级策略 |

配套实战:[Example 3](./src/zh/example-03.md) 链上拍卖行、[Example 6](./src/zh/example-06.md) 动态 NFT、[Example 7](./src/zh/example-07.md) 星门物流网络、[Example 9](./src/zh/example-09.md) 跨 Builder 协议、[Example 13](./src/zh/example-13.md) 订阅制通行证、[Example 14](./src/zh/example-14.md) NFT 质押借贷、[Example 16](./src/zh/example-16.md) NFT 合成拆解、[Example 18](./src/zh/example-18.md) 跨联盟外交条约

#### 第四阶段:架构、集成与产品(Chapter 18-25)

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 18 | [chapter-18.md](./src/zh/chapter-18.md) | 多租户与游戏服务器集成:Tenant 模型、ObjectRegistry、服务端脚本 |
| Chapter 19 | [chapter-19.md](./src/zh/chapter-19.md) | 全栈 dApp 架构设计:状态管理、实时更新、多链支持、CI/CD |
| Chapter 20 | [chapter-20.md](./src/zh/chapter-20.md) | 游戏内接入:浮层 UI、postMessage、游戏事件桥接 |
| Chapter 21 | [chapter-21.md](./src/zh/chapter-21.md) | 性能优化与 Gas 最小化:事务批处理、读写分离、链下计算 |
| Chapter 22 | [chapter-22.md](./src/zh/chapter-22.md) | Move 高级模式:升级兼容设计、动态字段扩展、数据迁移 |
| Chapter 23 | [chapter-23.md](./src/zh/chapter-23.md) | 发布、维护与社区协作:主网部署、Package 升级、Builder 协作 |
| Chapter 24 | [chapter-24.md](./src/zh/chapter-24.md) | 故障排查手册:常见 Move、Sui、dApp 错误类型与系统化调试方法 |
| Chapter 25 | [chapter-25.md](./src/zh/chapter-25.md) | 从 Builder 到产品:商业模式、用户增长、社区运营、渐进去中心化 |

配套实战:[Example 5](./src/zh/example-05.md) 联盟 DAO、[Example 12](./src/zh/example-12.md) 联盟招募、[Example 15](./src/zh/example-15.md) PvP 物品保险、[Example 17](./src/zh/example-17.md) 游戏内浮层实战

#### 第五阶段:World 合约源码精读(Chapter 26-32)

> 基于 [world-contracts](https://github.com/evefrontier/world-contracts) 真实源代码,深度解析 EVE Frontier 核心系统机制。

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 26 | [chapter-26.md](./src/zh/chapter-26.md) | 访问控制完整解析:GovernorCap、AdminACL、OwnerCap、Receiving 模式 |
| Chapter 27 | [chapter-27.md](./src/zh/chapter-27.md) | 链下签名 × 链上验证:Ed25519、PersonalMessage intent、sig_verify 精读 |
| Chapter 28 | [chapter-28.md](./src/zh/chapter-28.md) | 位置证明协议:LocationProof、BCS 反序列化、临近性验证实战 |
| Chapter 29 | [chapter-29.md](./src/zh/chapter-29.md) | 能量与燃料系统:EnergySource、Fuel 消耗率计算、已知 Bug 分析 |
| Chapter 30 | [chapter-30.md](./src/zh/chapter-30.md) | Extension 模式实战:官方 tribe_permit + corpse_gate_bounty 精读 |
| Chapter 31 | [chapter-31.md](./src/zh/chapter-31.md) | 炮塔 AI 扩展:TargetCandidate、优先级队列、自定义 AI 开发 |
| Chapter 32 | [chapter-32.md](./src/zh/chapter-32.md) | KillMail 系统:PvP 击杀记录、TenantItemId、derived_object 防重放 |

配套实战:[Example 8](./src/zh/example-08.md) Builder 竞赛系统、[Example 10](./src/zh/example-10.md) 综合实战

#### 第六阶段:钱包内部与未来(Chapter 33-35)

> 在已经会接入钱包和 dApp 之后,再回头深入钱包内部实现与未来方向,学习曲线更顺。

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 33 | [chapter-33.md](./src/zh/chapter-33.md) | zkLogin 原理与设计:零知识证明、FusionAuth OAuth、Enoki 盐值、临时密钥对 |
| Chapter 34 | [chapter-34.md](./src/zh/chapter-34.md) | 技术架构与开发部署:Chrome MV3 五层结构、Keeper 安全容器、消息协议、本地构建 |
| Chapter 35 | [chapter-35.md](./src/zh/chapter-35.md) | 未来展望:零知识证明、完全去中心化游戏、EVM 互操作 |

配套建议:完成本阶段后,回看 [Example 17](./src/zh/example-17.md) 的钱包连接、签名与游戏内接入链路。

---

### 案例索引

#### 初级案例(Example 1-3)

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 1 | [example-01.md](./src/zh/example-01.md) | 炮塔白名单:MiningPass NFT + AdminCap + 管理 dApp |
| Example 2 | [example-02.md](./src/zh/example-02.md) | 星门收费站:金库合约 + JumpPermit + 玩家购票 dApp |
| Example 3 | [example-03.md](./src/zh/example-03.md) | 链上拍卖行:荷兰式定价 + 自动结算 + 实时倒计时 dApp |

#### 中级案例(Example 4-7)

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 4 | [example-04.md](./src/zh/example-04.md) | 任务解锁系统:链上位标志任务 + 链下监控 + 条件星门 |
| Example 5 | [example-05.md](./src/zh/example-05.md) | 联盟 DAO:自定义 Coin + 快照分红 + 加权治理投票 |
| Example 6 | [example-06.md](./src/zh/example-06.md) | 动态 NFT:随游戏状态实时更新元数据的可进化装备 |
| Example 7 | [example-07.md](./src/zh/example-07.md) | 星门物流网络:多跳路由 + Dijkstra 路径规划 + dApp |

#### 高级案例(Example 8-10)

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 8 | [example-08.md](./src/zh/example-08.md) | Builder 竞赛系统:链上排行榜 + 积分 + 奖杯 NFT 自动分发 |
| Example 9 | [example-09.md](./src/zh/example-09.md) | 跨 Builder 协议:适配器模式 + 多合约聚合市场 |
| Example 10 | [example-10.md](./src/zh/example-10.md) | 综合实战:太空资源争夺战(整合角色、炮塔、星门、代币) |

#### 扩展案例(Example 11-15)

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 11 | [example-11.md](./src/zh/example-11.md) | 物品租赁系统:时间锁 NFT + 押金管理 + 提前归还退款 |
| Example 12 | [example-12.md](./src/zh/example-12.md) | 联盟招募:申请押金 + 成员投票 + 一票否决 + 自动发 NFT |
| Example 13 | [example-13.md](./src/zh/example-13.md) | 订阅制通行证:月、季套餐 + 可转让 Pass NFT + 续费 |
| Example 14 | [example-14.md](./src/zh/example-14.md) | NFT 质押借贷:LTV 60% + 月息 3% + 逾期清算拍卖 |
| Example 15 | [example-15.md](./src/zh/example-15.md) | PvP 物品保险:购买保单 + 服务器签名理赔 + 赔付池 |

#### 高级扩展(Example 16-18)

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 16 | [example-16.md](./src/zh/example-16.md) | NFT 合成拆解:三级物品体系 + 链上随机数 + 安慰奖机制 |
| Example 17 | [example-17.md](./src/zh/example-17.md) | 游戏内浮层实战:收费站游戏内版 + postMessage + 无缝签名 |
| Example 18 | [example-18.md](./src/zh/example-18.md) | 跨联盟外交条约:双签生效 + 押金约束 + 违约举证与罚款 |

---

### 创意库

- [Sui 核心特性创意 100 例](./src/zh/idea/README.md)
- [常规综合创意 100 例](./src/zh/idea_general/README.md)

---

### 阅读入口

- [课程首页](./src/zh/index.md)
- [目录](./src/zh/SUMMARY.md)
- [术语表](./src/zh/glossary.md)
- [案例运行指南](./src/code/README.md)

---

### 参考资源

- [官方 builder-documentation](https://github.com/evefrontier/builder-documentation)
- [builder-scaffold(脚手架)](https://github.com/evefrontier/builder-scaffold)
- [World Contracts 源码](https://github.com/evefrontier/world-contracts)
- [EVE Vault](https://github.com/evefrontier/evevault)
- [Sui 文档](https://docs.sui.io)
- [Move Book](https://move-book.com)
- [EVE Frontier dapp-kit API](http://sui-docs.evefrontier.com/)
- [Sui GraphQL IDE(Testnet)](https://graphql.testnet.sui.io/graphql)
- [EVE Frontier Discord](https://discord.com/invite/evefrontier)
