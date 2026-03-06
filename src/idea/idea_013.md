# 13. 联盟战利品均分系统 (Automated Loot Distributor)

## 💡 核心概念 (Concept)
战役结束后，指挥官只需将战利品一揽子放入合约，系统自动根据参战名单和贡献比例，将资源分发至每个队员。

## 🧩 解决的痛点 (Pain Points Solved)
- **人工分账累心**：清点数千件残骸并手动分发是管理者的噩梦。
- **透明度低**：普通队员怀疑指挥官克扣高级战利品，容易导致公会分崩离析。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **贡献权重记录**：根据战斗中产生的 `Damage_Event` 或 `Healing_Event` 流，合约自动计算每个地址的权重。
2. **批量分发 PTB**：利用 Sui 单次交易处理上千命令的能力。将战利品 SUI 或零件一键拆解并 `transfer` 至对应权重的地址列表。
3. **公共账本公示**：分发记录永久存在于链上，任何人可审计分发比例是否公平。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] PTB (高并发批量分账)
- [x] DeepBook (若战利品是矿产，可一键卖出换成 SUI 再分发)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `LootPool`: 临时存放战利品的共享对象。
- `ActionRegistry`: 存储玩家近期战斗表现。

## 📅 开发里程碑 (Milestones)
- [ ] 实现权重分账算法
- [ ] 编写战利品统一估价模块
- [ ] 自动化批量分发测试
