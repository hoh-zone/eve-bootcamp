# 7. 全自动化兵工厂 (Automated Ammo Factory)

## 💡 Core Concept (Concept)
An on-chain automated production line component.输入矿石，合约根据时间流逝自动转换输出为弹药或装甲板。

## 🧩Pain Points Solved
- **制造业繁琐**：手动点击合成太低效。
- **库存管理难**：后勤人员需要手动搬运材料。

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **时间锁 (Time-Lock) 生产**：矿石存入合约后，`Clock` 对象开始计时。
2. **Recipe (配方) 验证**：Move 合约内预设 `Ore_A + Ore_B = Ammo_C` 逻辑。
3. **异步领取**：24小时后，凭证对象状态变更，变为“可领取”状态，自动分发弹药到玩家指定的 Kiosk。

## 🛠️ Sui core feature application (Sui Features)
- [x] Move 核心机制 (通过 Epoch/Clock 驱动)
- [x] Sui Kiosk (ammunition distribution channel)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `ProductionQueue`: Dynamic field list.
- `Blueprint`: Define conversion rate.

## 📅 Development Milestones (Milestones)
- [ ] Write recipe matching logic
- [ ] Implementation of production cooling CD system
- [ ] Batch processing of production tasks