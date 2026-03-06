# EVE Frontier 构建者完整课程

> 每节课约 **2 小时**，共 **53 节**：35 个基础章节 + 18 个实战案例 ≈ **106 小时**完整学习内容。

---

## 📖 基础章节（每节 2 小时）

### 第一阶段：入门基础（Chapter 1-5）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 1  | [chapter-01.md](./src/chapter-01.md) | EVE Frontier 宏观架构：三层模型、智能组件类型、Sui/Move 选型 |
| Chapter 2  | [chapter-02.md](./src/chapter-02.md) | 开发环境配置：Docker 本地链、Sui CLI、EVE Vault 钱包、builder-scaffold |
| Chapter 3  | [chapter-03.md](./src/chapter-03.md) | Move 合约基础：模块、Abilities、对象所有权、Capability/Witness/Hot Potato |
| Chapter 4  | [chapter-04.md](./src/chapter-04.md) | 智能组件开发与链上部署：角色、网络节点、炮塔/星门/存储箱改造全流程 |
| Chapter 5  | [chapter-05.md](./src/chapter-05.md) | dApp 前端开发：dapp-kit SDK、React Hooks、钱包集成、链上交易 |

### 第二阶段：核心进阶（Chapter 6-10）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 6  | [chapter-06.md](./src/chapter-06.md) | 所有权模型深度解析：OwnerCap、Keychain、Borrow-Use-Return、委托 |
| Chapter 7  | [chapter-07.md](./src/chapter-07.md) | Move 进阶：泛型、动态字段、事件系统、Table 与 VecMap |
| Chapter 8  | [chapter-08.md](./src/chapter-08.md) | 链上经济系统设计：代币发行、去中心化市场、动态定价、金库 |
| Chapter 9  | [chapter-09.md](./src/chapter-09.md) | 测试、调试与安全审计：Move 单元测试、漏洞类型、升级策略 |
| Chapter 10 | [chapter-10.md](./src/chapter-10.md) | 发布、维护与社区协作：主网部署、Package 升级、Builder 协作 |

### 第三阶段：高级专题（Chapter 11-15）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 11 | [chapter-11.md](./src/chapter-11.md) | 赞助交易与服务端集成：Sponsored Tx、AdminACL、链上链下协同 |
| Chapter 12 | [chapter-12.md](./src/chapter-12.md) | 链下索引与 GraphQL 进阶：自定义索引器、实时订阅、数据聚合 |
| Chapter 13 | [chapter-13.md](./src/chapter-13.md) | 跨合约组合性：调用其他 Builder 的合约、接口设计、协议标准 |
| Chapter 14 | [chapter-14.md](./src/chapter-14.md) | NFT 设计与元数据管理：Display 标准、动态 NFT、Collection 模式 |
| Chapter 15 | [chapter-15.md](./src/chapter-15.md) | 位置与临近性系统：哈希位置、临近证明、地理策略设计 |

### 第四阶段：架构与未来（Chapter 16-20）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 16 | [chapter-16.md](./src/chapter-16.md) | 多租户与游戏服务器集成：Tenant 模型、ObjectRegistry、服务端脚本 |
| Chapter 17 | [chapter-17.md](./src/chapter-17.md) | 性能优化与 Gas 最小化：事务批处理、读写分离、链下计算 |
| Chapter 18 | [chapter-18.md](./src/chapter-18.md) | 全栈 dApp 架构设计：状态管理、实时更新、多链支持、CI/CD |
| Chapter 19 | [chapter-19.md](./src/chapter-19.md) | Move 高级模式：升级兼容设计、动态字段扩展、数据迁移 |
| Chapter 20 | [chapter-20.md](./src/chapter-20.md) | 未来展望：零知识证明、完全去中心化游戏、EVM 互操作 |

### 第五阶段：实战与运营（Chapter 21-23）

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 21 | [chapter-21.md](./src/chapter-21.md) | 游戏内 dApp 集成：浮层 UI、游戏事件监听、postMessage 桥接 |
| Chapter 22 | [chapter-22.md](./src/chapter-22.md) | 故障排查手册：常见 Move/Sui/dApp 错误类型与系统化调试方法 |
| Chapter 23 | [chapter-23.md](./src/chapter-23.md) | 从 Builder 到产品：商业模式、用户增长、社区运营、渐进去中心化 |

### 🔬 第六阶段：World 合约源码精读（Chapter 24-30）

> 基于 [world-contracts](../world-contracts/) 真实源代码，深度解析 EVE Frontier 核心系统机制。

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 24 | [chapter-24.md](./src/chapter-24.md) | **KillMail 系统**：PvP 击杀记录、TenantItemId、derived_object 防重放 |
| Chapter 25 | [chapter-25.md](./src/chapter-25.md) | **链下签名 × 链上验证**：Ed25519、PersonalMessage intent、sig_verify 精读 |
| Chapter 26 | [chapter-26.md](./src/chapter-26.md) | **位置证明协议**：LocationProof、BCS 反序列化、临近性验证实战 |
| Chapter 27 | [chapter-27.md](./src/chapter-27.md) | **能量与燃料系统**：EnergySource、Fuel 消耗率计算、已知 Bug 分析 |
| Chapter 28 | [chapter-28.md](./src/chapter-28.md) | **Extension 模式实战**：官方 tribe_permit + corpse_gate_bounty 精读 |
| Chapter 29 | [chapter-29.md](./src/chapter-29.md) | **炮塔 AI 扩展**：TargetCandidate、优先级队列、自定义 AI 开发 |
| Chapter 30 | [chapter-30.md](./src/chapter-30.md) | **访问控制完整解析**：GovernorCap / AdminACL / OwnerCap / Receiving 模式 |

### 🚀 第七阶段：Builder Scaffold 实战（Chapter 31-32）

> 基于 [builder-scaffold](../builder-scaffold/) 进行端到端开发——从本地链搭建到 dApp 上线。

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 31 | [chapter-31.md](./src/chapter-31.md) | **项目结构与合约开发**：Docker 环境、smart_gate 三文件架构、编译与发布 |
| Chapter 32 | [chapter-32.md](./src/chapter-32.md) | **TS 脚本与 dApp 开发**：6 个交互脚本、helper.ts 工具链、React Hooks、赞助交易 |

### 🔐 第八阶段：EVE Vault 钱包（Chapter 33-35）

> 基于 [evevault](../evevault/) 源码，深入理解 EVE Frontier 专属钱包——zkLogin、Chrome MV3 架构和 dApp 集成。

| 章节 | 文件 | 主题摘要 |
|------|------|--------|
| Chapter 33 | [chapter-33.md](./src/chapter-33.md) | **zkLogin 原理与设计**：零知识证明、FusionAuth OAuth、Enoki 盐值、临时密钥对 |
| Chapter 34 | [chapter-34.md](./src/chapter-34.md) | **技术架构与开发部署**：Chrome MV3 五层结构、Keeper 安全容器、消息协议、本地构建 |
| Chapter 35 | [chapter-35.md](./src/chapter-35.md) | **dApp 集成实战**：useConnection、赞助交易、Epoch 刷新、hasEveVault 检测 |

---

## 🛠 实战案例（每节 2 小时）

### 初级案例（Example 1-3）——基础组件应用

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 1  | [example-01.md](./src/example-01.md) | 炮塔白名单：MiningPass NFT + AdminCap + 管理 dApp |
| Example 2  | [example-02.md](./src/example-02.md) | 星门收费站：金库合约 + JumpPermit + 玩家购票 dApp |
| Example 3  | [example-03.md](./src/example-03.md) | 链上拍卖行：荷兰式定价 + 自动结算 + 实时倒计时 dApp |

### 中级案例（Example 4-7）——经济与治理

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 4  | [example-04.md](./src/example-04.md) | 任务解锁系统：链上位标志任务 + 链下监控 + 条件星门 |
| Example 5  | [example-05.md](./src/example-05.md) | 联盟 DAO：自定义 Coin + 快照分红 + 加权治理投票 |
| Example 6  | [example-06.md](./src/example-06.md) | 动态 NFT：随游戏状态实时更新元数据的可进化装备 |
| Example 7  | [example-07.md](./src/example-07.md) | 星门物流网络：多跳路由 + Dijkstra 路径规划 + dApp |

### 高级案例（Example 8-10）——系统集成

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 8  | [example-08.md](./src/example-08.md) | Builder 竞赛系统：链上排行榜 + 积分 + 奖杯 NFT 自动分发 |
| Example 9  | [example-09.md](./src/example-09.md) | 跨 Builder 协议：适配器模式 + 多合约聚合市场 |
| Example 10 | [example-10.md](./src/example-10.md) | 综合实战：太空资源争夺战（整合角色/炮塔/星门/代币） |

### 扩展案例（Example 11-15）——金融与产品化

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 11 | [example-11.md](./src/example-11.md) | 物品租赁系统：时间锁 NFT + 押金管理 + 提前归还退款 |
| Example 12 | [example-12.md](./src/example-12.md) | 联盟招募：申请押金 + 成员投票 + 一票否决 + 自动发 NFT |
| Example 13 | [example-13.md](./src/example-13.md) | 订阅制通行证：月/季套餐 + 可转让 Pass NFT + 续费 |
| Example 14 | [example-14.md](./src/example-14.md) | NFT 质押借贷：LTV 60% + 月息 3% + 逾期清算拍卖 |
| Example 15 | [example-15.md](./src/example-15.md) | PvP 物品保险：购买保单 + 服务器签名理赔 + 赔付池 |

### 高级扩展（Example 16-18）——创新玩法

| 案例 | 文件 | 技术亮点 |
|------|------|--------|
| Example 16 | [example-16.md](./src/example-16.md) | NFT 合成拆解：三级物品体系 + 链上随机数 + 安慰奖机制 |
| Example 17 | [example-17.md](./src/example-17.md) | 游戏内浮层实战：收费站游戏内版 + postMessage + 无缝签名 |
| Example 18 | [example-18.md](./src/example-18.md) | 跨联盟外交条约：双签生效 + 押金约束 + 违约举证与罚款 |

---

## 📖 阅读建议

| 阶段 | 内容 | 建议 | 时长 |
|------|------|------|------|
| 入门 | Chapter 1-5 | 按顺序学习，建立基础 | ~10h |
| 进阶 | Chapter 6-10 | 完成入门后，深入 Move 模式 | ~10h |
| 高级专题 | Chapter 11-15 | 按需阅读，重点关注你的业务方向 | ~10h |
| 架构 | Chapter 16-20 | 适合有经验的 Builder | ~10h |
| 运营 | Chapter 21-23 | 产品上线前必读 | ~6h |
| 源码精读 | Chapter 24-30 | 深入理解 World 合约底层机制 | ~14h |
| 工程实战 | Chapter 31-32 | Builder Scaffold 端到端开发 | ~4h |
| 钱包集成 | Chapter 33-35 | EVE Vault zkLogin 与 dApp 对接 | ~6h |
| 基础实战 | Example 1-7 | 按顺序完成，实践核心技能 | ~14h |
| 高级实战 | Example 8-18 | 综合运用，挑战复杂场景 | ~22h |

### 推荐学习路径

**快速上手 Builder（最短路径，约 20h）**：
Chapter 1-4 → Chapter 31-32（Builder Scaffold）→ Example 1-3

**完整 Builder 路径（约 60h）**：
Chapter 1-23 → Example 1-10 → Chapter 31-32 → Chapter 33-35

**源码研究者路径（约 30h）**：
Chapter 3 → Chapter 24-30（World 合约精读）→ Chapter 31-32

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
