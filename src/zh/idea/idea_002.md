# 2. 极危求救信标 (Automated SOS Beacon)

## 💡 核心概念 (Concept)
一个集成在飞船上的智能组件。当飞船装甲值低于临界点时，自动向全网广播求救信号，并锁定一笔赏金给第一个击退敌人的救援者。

## 🧩 解决的痛点 (Pain Points Solved)
- **响应慢**：打字向公会求救往往来不及，劫匪在几秒内就能完成击毁。
- **信任缺失**：路人看到求救不敢救，担心救了之后受害者不给钱，甚至担心是诱饵。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **自动资金托管**：玩家出航前在信标中存入 10 SUI 作为“定金”。
2. **事件驱动广播**：当飞船 `Health` 组件触发 `Critical_Alert` 事件时，合约立刻释放 `SOS_Signal` Event。
3. **PTB 实时结算**：救援者对劫匪造成伤害后产生 `Killmail` 凭证。救援者提交凭证至合约，合约验证击杀时间与受救时间吻合后，瞬间从托管池分发赏金，无需受害者手动点击。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Sponsored Transactions (允许受害者在资源枯竭时发信号)
- [x] PTB (验证击杀与支付的原子性)
- [ ] Dynamic Fields / Object Fields

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `SOSBeacon`: 包含 `Balance` 和 `Threshold` 的飞船挂载件。
- `RescueReward`: 待领取的资产包。

## 📅 开发里程碑 (Milestones)
- [ ] 编写伤害监听逻辑
- [ ] 接入 Killmail 验证逻辑
- [ ] 实现自动打款合约
