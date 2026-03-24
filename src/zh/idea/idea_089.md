# 89. 共享矿带抢采协议

## 💡 核心概念 (Concept)
把整条矿带设计成共享对象，而不是每个玩家各自挖自己的资源副本。多个玩家、团队和联盟可以同时对同一资源池发起开采、增益、抢夺和封锁操作。系统根据时间窗、工具等级、位置条件和协作人数动态结算产出，真实表现“大家都在抢同一片矿”的世界感。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] PTB (可编程交易块)：一笔交易里完成开采、结算、奖励
- [x] Dynamic Fields / Object Fields：记录矿层、增益、采集位和剩余量
- [x] Sponsored Transactions：降低大规模活动参与门槛
- [x] Move 核心机制 (Shared)：多方并发争夺同一资源池

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `SharedAsteroidBelt`：共享矿带
- `MiningSlot`：占位与工具加成
- `YieldPool`：本轮可分配产出

### 关键函数
- `enter_belt`：进入矿带争夺
- `mine_tick`：按条件结算当次产出
- `boost_team`：给队伍叠加协作加成
- `drain_belt`：矿带耗尽并重置周期

## 💻 前端与客户端交互层 (Frontend & Client)
前端展示矿带热度、剩余量、参与队伍、实时收益和争夺日志。适合做星区资源战面板。

## 💰 经济与商业模型 (Economic Model)
- 资源税
- 工具租赁
- 护航服务费
- 矿带占领方抽成

## 📅 开发里程碑 (Milestones)
- [ ] MVP：共享矿带与基础开采
- [ ] 多人并发结算
- [ ] 联盟加成和封锁机制
- [ ] 热区地图与税收结算
