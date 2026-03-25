# 7. 全自动化兵工厂 (Automated Ammo Factory)

## 💡 核心概念 (Concept)
一个链上自动生产线组件。输入矿石，合约根据时间流逝自动转换输出为弹药或装甲板。

## 🧩 解决的痛点 (Pain Points Solved)
- **制造业繁琐**：手动点击合成太低效。
- **库存管理难**：后勤人员需要手动搬运材料。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **时间锁 (Time-Lock) 生产**：矿石存入合约后，`Clock` 对象开始计时。
2. **Recipe (配方) 验证**：Move 合约内预设 `Ore_A + Ore_B = Ammo_C` 逻辑。
3. **异步领取**：24小时后，凭证对象状态变更，变为“可领取”状态，自动分发弹药到玩家指定的 Kiosk。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Move 核心机制 (通过 Epoch/Clock 驱动)
- [x] Sui Kiosk (弹药分发渠道)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `ProductionQueue`: 动态字段列表。
- `Blueprint`: 定义转化率。

## 📅 开发里程碑 (Milestones)
- [ ] 编写配方匹配逻辑
- [ ] 实现生产冷却 CD 系统
- [ ] 批量处理生产任务
