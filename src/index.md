# EVE Frontier 构建者完整课程

> 每节课约 **2 小时**，共 **54 节**：36 个基础章节 + 18 个实战案例 ≈ **108 小时**完整学习内容。

---

## 📖 章节主线（按建议学习顺序排列，每节约 2 小时）

### 前置章节

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Prelude | [chapter-00.md](./chapter-00.md) | 先读懂 EVE Frontier 这款游戏：玩家在争夺什么、设施为什么重要、位置/战损/物流/经济如何串成完整玩法 |

### 第一阶段：入门基础（Chapter 1-5）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 1  | [chapter-01.md](./chapter-01.md) | EVE Frontier 宏观架构：三层模型、智能组件类型、Sui/Move 选型 |
| Chapter 2  | [chapter-02.md](./chapter-02.md) | 开发环境配置：Docker 本地链、Sui CLI、EVE Vault 钱包、builder-scaffold |
| Chapter 3  | [chapter-03.md](./chapter-03.md) | Move 合约基础：模块、Abilities、对象所有权、Capability/Witness/Hot Potato |
| Chapter 4  | [chapter-04.md](./chapter-04.md) | 智能组件开发与链上部署：角色、网络节点、炮塔/星门/存储箱改造全流程 |
| Chapter 5  | [chapter-05.md](./chapter-05.md) | dApp 前端开发：dapp-kit SDK、React Hooks、钱包集成、链上交易 |

配套实战：[Example 1](./example-01.md) 炮塔白名单、[Example 2](./example-02.md) 星门收费站

### 第二阶段：Builder 工程闭环（Chapter 31-32, 11-12, 35）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 31 | [chapter-31.md](./chapter-31.md) | Builder Scaffold 入口：项目结构、smart_gate 架构、编译与发布 |
| Chapter 32 | [chapter-32.md](./chapter-32.md) | TS 脚本与前端：helper.ts、脚本链路、React dApp 模板 |
| Chapter 11 | [chapter-11.md](./chapter-11.md) | 服务端协同：Sponsored Tx、AdminACL、链上链下配合 |
| Chapter 12 | [chapter-12.md](./chapter-12.md) | 数据读取：GraphQL、事件订阅、索引器思路 |
| Chapter 35 | [chapter-35.md](./chapter-35.md) | dApp 钱包接入：useConnection、赞助交易、Epoch 处理 |

配套实战：[Example 4](./example-04.md) 任务解锁系统、[Example 11](./example-11.md) 物品租赁系统

### 第三阶段：合约设计进阶（Chapter 6-8, 13-15）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 6  | [chapter-06.md](./chapter-06.md) | 所有权模型深度解析：OwnerCap、Keychain、Borrow-Use-Return、委托 |
| Chapter 7  | [chapter-07.md](./chapter-07.md) | Move 进阶：泛型、动态字段、事件系统、Table 与 VecMap |
| Chapter 14 | [chapter-14.md](./chapter-14.md) | NFT 设计与元数据管理：Display 标准、动态 NFT、Collection 模式 |
| Chapter 8  | [chapter-08.md](./chapter-08.md) | 链上经济系统设计：代币发行、去中心化市场、动态定价、金库 |
| Chapter 13 | [chapter-13.md](./chapter-13.md) | 跨合约组合性：调用其他 Builder 的合约、接口设计、协议标准 |
| Chapter 15 | [chapter-15.md](./chapter-15.md) | 位置与临近性系统：哈希位置、临近证明、地理策略设计 |

配套实战：[Example 3](./example-03.md) 链上拍卖行、[Example 6](./example-06.md) 动态 NFT、[Example 7](./example-07.md) 星门物流网络、[Example 9](./example-09.md) 跨 Builder 协议、[Example 13](./example-13.md) 订阅制通行证、[Example 14](./example-14.md) NFT 质押借贷、[Example 16](./example-16.md) NFT 合成拆解、[Example 18](./example-18.md) 跨联盟外交条约

### 第四阶段：架构、集成与产品（Chapter 16-19, 21-23, 10）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 16 | [chapter-16.md](./chapter-16.md) | 多租户与游戏服务器集成：Tenant 模型、ObjectRegistry、服务端脚本 |
| Chapter 18 | [chapter-18.md](./chapter-18.md) | 全栈 dApp 架构设计：状态管理、实时更新、多链支持、CI/CD |
| Chapter 21 | [chapter-21.md](./chapter-21.md) | 游戏内接入：浮层 UI、postMessage、游戏事件桥接 |
| Chapter 17 | [chapter-17.md](./chapter-17.md) | 性能优化与 Gas 最小化：事务批处理、读写分离、链下计算 |
| Chapter 19 | [chapter-19.md](./chapter-19.md) | Move 高级模式：升级兼容设计、动态字段扩展、数据迁移 |
| Chapter 10 | [chapter-10.md](./chapter-10.md) | 发布、维护与社区协作：主网部署、Package 升级、Builder 协作 |
| Chapter 22 | [chapter-22.md](./chapter-22.md) | 故障排查手册：常见 Move/Sui/dApp 错误类型与系统化调试方法 |
| Chapter 23 | [chapter-23.md](./chapter-23.md) | 从 Builder 到产品：商业模式、用户增长、社区运营、渐进去中心化 |

配套实战：[Example 5](./example-05.md) 联盟 DAO、[Example 12](./example-12.md) 联盟招募、[Example 15](./example-15.md) PvP 物品保险、[Example 17](./example-17.md) 游戏内浮层实战

### 🔬 第五阶段：World 合约源码精读（Chapter 30, 25-29, 24）

> 基于 [world-contracts](https://github.com/evefrontier/world-contracts) 真实源代码，深度解析 EVE Frontier 核心系统机制。

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 30 | [chapter-30.md](./chapter-30.md) | **访问控制完整解析**：GovernorCap / AdminACL / OwnerCap / Receiving 模式 |
| Chapter 25 | [chapter-25.md](./chapter-25.md) | **链下签名 × 链上验证**：Ed25519、PersonalMessage intent、sig_verify 精读 |
| Chapter 26 | [chapter-26.md](./chapter-26.md) | **位置证明协议**：LocationProof、BCS 反序列化、临近性验证实战 |
| Chapter 27 | [chapter-27.md](./chapter-27.md) | **能量与燃料系统**：EnergySource、Fuel 消耗率计算、已知 Bug 分析 |
| Chapter 28 | [chapter-28.md](./chapter-28.md) | **Extension 模式实战**：官方 tribe_permit + corpse_gate_bounty 精读 |
| Chapter 29 | [chapter-29.md](./chapter-29.md) | **炮塔 AI 扩展**：TargetCandidate、优先级队列、自定义 AI 开发 |
| Chapter 24 | [chapter-24.md](./chapter-24.md) | **KillMail 系统**：PvP 击杀记录、TenantItemId、derived_object 防重放 |

配套实战：[Example 8](./example-08.md) Builder 竞赛系统、[Example 10](./example-10.md) 综合实战

### 🔐 第六阶段：钱包内部与未来（Chapter 33-34, 20）

> 在已经会接入钱包和 dApp 之后，再回头深入钱包内部实现与未来方向，学习曲线更顺。

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 33 | [chapter-33.md](./chapter-33.md) | **zkLogin 原理与设计**：零知识证明、FusionAuth OAuth、Enoki 盐值、临时密钥对 |
| Chapter 34 | [chapter-34.md](./chapter-34.md) | **技术架构与开发部署**：Chrome MV3 五层结构、Keeper 安全容器、消息协议、本地构建 |
| Chapter 20 | [chapter-20.md](./chapter-20.md) | **未来展望**：零知识证明、完全去中心化游戏、EVM 互操作 |

配套建议：完成本阶段后，回看 [Example 17](./example-17.md) 的钱包连接、签名与游戏内接入链路。

---

## 🛠 案例索引（按复杂度查看，每节 2 小时）

> 主线分配见上；下面保留按复杂度查看的索引，方便选题和回查。

### 初级案例（Example 1-3）——基础组件应用

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 1  | [example-01.md](./example-01.md) | 炮塔白名单：MiningPass NFT + AdminCap + 管理 dApp |
| Example 2  | [example-02.md](./example-02.md) | 星门收费站：金库合约 + JumpPermit + 玩家购票 dApp |
| Example 3  | [example-03.md](./example-03.md) | 链上拍卖行：荷兰式定价 + 自动结算 + 实时倒计时 dApp |

### 中级案例（Example 4-7）——经济与治理

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 4  | [example-04.md](./example-04.md) | 任务解锁系统：链上位标志任务 + 链下监控 + 条件星门 |
| Example 5  | [example-05.md](./example-05.md) | 联盟 DAO：自定义 Coin + 快照分红 + 加权治理投票 |
| Example 6  | [example-06.md](./example-06.md) | 动态 NFT：随游戏状态实时更新元数据的可进化装备 |
| Example 7  | [example-07.md](./example-07.md) | 星门物流网络：多跳路由 + Dijkstra 路径规划 + dApp |

### 高级案例（Example 8-10）——系统集成

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 8  | [example-08.md](./example-08.md) | Builder 竞赛系统：链上排行榜 + 积分 + 奖杯 NFT 自动分发 |
| Example 9  | [example-09.md](./example-09.md) | 跨 Builder 协议：适配器模式 + 多合约聚合市场 |
| Example 10 | [example-10.md](./example-10.md) | 综合实战：太空资源争夺战（整合角色/炮塔/星门/代币） |

### 扩展案例（Example 11-15）——金融与产品化

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 11 | [example-11.md](./example-11.md) | 物品租赁系统：时间锁 NFT + 押金管理 + 提前归还退款 |
| Example 12 | [example-12.md](./example-12.md) | 联盟招募：申请押金 + 成员投票 + 一票否决 + 自动发 NFT |
| Example 13 | [example-13.md](./example-13.md) | 订阅制通行证：月/季套餐 + 可转让 Pass NFT + 续费 |
| Example 14 | [example-14.md](./example-14.md) | NFT 质押借贷：LTV 60% + 月息 3% + 逾期清算拍卖 |
| Example 15 | [example-15.md](./example-15.md) | PvP 物品保险：购买保单 + 服务器签名理赔 + 赔付池 |

### 高级扩展（Example 16-18）——创新玩法

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 16 | [example-16.md](./example-16.md) | NFT 合成拆解：三级物品体系 + 链上随机数 + 安慰奖机制 |
| Example 17 | [example-17.md](./example-17.md) | 游戏内浮层实战：收费站游戏内版 + postMessage + 无缝签名 |
| Example 18 | [example-18.md](./example-18.md) | 跨联盟外交条约：双签生效 + 押金约束 + 违约举证与罚款 |

---

## 📖 阅读建议

| 阶段 | 内容 | 建议 | 时长 |
|------|------|------|------|
| 入门基础 | Prelude → Chapter 1-5 → Example 1, 2 | 先建立玩法直觉，再进入架构、组件和最小闭环 | ~16h |
| 工程闭环 | Chapter 31-32 → 11-12 → 35 → Example 4, 11 | 先把 Builder 的端到端链路跑通 | ~14h |
| 合约进阶 | Chapter 6-8, 13-15 → Example 3, 6, 7, 9, 13, 14, 16, 18 | 回头补强合约设计能力 | ~28h |
| 架构与产品 | Chapter 16, 18, 21, 17, 19, 10, 22-23 → Example 5, 12, 15, 17 | 面向长期维护、游戏接入和产品化 | ~24h |
| 源码精读 | Chapter 30, 25-29, 24 → Example 8, 10 | 从 World 核心模块反推设计理念，再做复杂系统案例 | ~18h |
| 钱包内部与未来 | Chapter 33-34, 20 | 深入理解 EVE Vault 内核和后续方向 | ~6h |

### 推荐学习路径

**快速上手 Builder（最短路径，约 26h）**：
Prelude → Chapter 1-4 → Example 1-2 → Chapter 31-32 → Chapter 11-12 → Chapter 35 → Example 4

**完整 Builder 路径（约 96h）**：
Prelude → Chapter 1-5 → Example 1-2 → Chapter 31-32 → Chapter 11-12 → Chapter 35 → Example 4, 11 → Chapter 6-8 → Chapter 13-15 → Example 3, 6, 7, 9, 13, 14 → Chapter 16 → Chapter 18 → Chapter 21 → Chapter 17, 19 → Chapter 10, 22-23 → Example 5, 12, 15, 17 → Chapter 30 → Chapter 25-29 → Chapter 24 → Example 8, 10 → Chapter 33-34 → Chapter 20

**源码研究者路径（约 32h）**：
Prelude → Chapter 3 → Chapter 6 → Chapter 13 → Chapter 30 → Chapter 25-29 → Chapter 24 → Example 8, 10 → Chapter 31-32

---

## 📚 参考资源

- [官方 builder-documentation](https://github.com/evefrontier/builder-documentation)
- [builder-scaffold（脚手架）](https://github.com/evefrontier/builder-scaffold)
- [World Contracts 源码](https://github.com/evefrontier/world-contracts)
- [Sui 文档](https://docs.sui.io)
- [Move Book](https://move-book.com)
- [EVE Frontier dapp-kit API](http://sui-docs.evefrontier.com/)
- [Sui GraphQL IDE（Testnet）](https://graphql.testnet.sui.io/graphql)
- [EVE Frontier Discord](https://discord.com/invite/evefrontier)
- [术语表](./glossary.md)
