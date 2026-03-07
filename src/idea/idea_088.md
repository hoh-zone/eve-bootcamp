# 88. 热土豆通缉信标

## 💡 核心概念 (Concept)
把 Hot Potato 模式做成一个高风险 PvP 活动信标。持有信标的玩家必须在限定时间内完成特定动作，比如击杀、抵达某地点、交货或把信标传递给下一人；否则押金会被罚没，或者其位置和身份会被广播到追猎网络。它适合做逃亡赛、猎杀秀、赌命快递和联盟内部选拔。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] PTB (可编程交易块)：把传递、结算、罚没放进同一交易链路
- [x] Sponsored Transactions：降低参赛和围观门槛
- [x] sui::random：生成赛季效果或突发规则
- [x] Move 核心机制 (Hot Potato, Shared)：实现不可久持的信标

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `BountyBeacon`：热土豆信标
- `EscapePool`：押金池与奖金池
- `RoundRule`：本轮赛事规则

### 关键函数
- `start_round`：开启一轮追猎
- `pass_beacon`：把信标传给下一玩家
- `claim_survival_reward`：完成目标后领取奖励
- `slash_holder`：超时未完成则罚没

## 💻 前端与客户端交互层 (Frontend & Client)
前端显示倒计时、追猎地图、传递历史、奖金池和幸存榜。可接入游戏内浮层，实时提醒信标状态。

## 💰 经济与商业模型 (Economic Model)
- 赛事报名费
- 赞助奖金池
- 观赛门票
- 高阶猎人排行榜奖励

## 📅 开发里程碑 (Milestones)
- [ ] MVP：单局热土豆传递
- [ ] 押金和罚没逻辑
- [ ] 实时排行榜
- [ ] 多赛季规则与赞助系统
