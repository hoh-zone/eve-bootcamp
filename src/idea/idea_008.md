# 8. 共享充电桩网络 (Shared Battery Network)

## 💡 核心概念 (Concept)
部署在星区节点的共享能源 Object。任何飞船都可以靠近它并支付 SUI 实时补充船体电能/燃料。

## 🧩 解决的痛点 (Pain Points Solved)
- **断粮危机**：长途跃迁时电能耗尽，被迫飘在太空中等死。
- **能源垄断**：小公会难以自建燃料补给线。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **按需计费微支付**：利用 PTB，玩家每次请求补充 10% 燃料，自动扣除对应 $SUI。
2. **投资收益化**：个人玩家可以向充电桩“注能”或注资 $SUI 购买股份，根据充电热度获取被动收入分红。
3. **服务竞争**：不同节点的价格可以随市场需求波动，形成太空中的中石化/中石油竞争网络。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Shared Objects (并发充电)
- [x] Sponsored Transactions (允许没电的船由系统代付一笔开机费)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `BatteryNode`: 包含库存和汇率的共享对象。
- `DividendShare`: 投资者权证。

## 📅 开发里程碑 (Milestones)
- [ ] 实现燃料-SUI 兑换逻辑
- [ ] 编写多股东分红合约
- [ ] 前端地图标记充电点
