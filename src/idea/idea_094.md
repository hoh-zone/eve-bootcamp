# 94. 全服倒计时争夺战

## 💡 核心概念 (Concept)
基于链上 `Clock` 做公开可验证的倒计时事件。某个资源箱、限时星门、战争窗口、迁移机会或悬赏池会在固定时间点结算，所有人都能看到同一套倒计时。玩家必须在归零前筹款、守点、交货、投票或撤离，倒计时结束瞬间按规则结算奖励与归属。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] PTB (可编程交易块)：把参与、押注和结算组织在一起
- [x] Sponsored Transactions：便于大规模活动参与
- [x] Move 核心机制 (Shared)：多人同时竞争同一倒计时事件

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `CountdownEvent`：事件本体
- `StakePool`：押注或参赛池
- `ResultBoard`：归零后的结算记录

### 关键函数
- `create_event`：创建倒计时事件
- `join_event`：参赛或下注
- `resolve_event`：到点结算
- `claim_reward`：领取奖励

## 💻 前端与客户端交互层 (Frontend & Client)
前端突出显示倒计时、参赛方、当前押注、事件地图和历史归零记录。适合做赛季活动页和世界事件页。

## 💰 经济与商业模型 (Economic Model)
- 报名费
- 押注抽成
- 活动赞助
- 战区流量入口合作

## 📅 开发里程碑 (Milestones)
- [ ] MVP：单事件倒计时
- [ ] 参赛和押注
- [ ] 自动结算
- [ ] 多事件赛季化
