# 10. 一次性急救包贩卖机 (Emergency Medical Bay)

## 💡 核心概念 (Concept)
在战场周边部署的自动贩卖机，出售可以瞬间恢复护盾值或移除 Debuff 的一次性 NFT 消耗品。

## 🧩 解决的痛点 (Pain Points Solved)
- **战斗容错低**：关键时刻缺一口奶导致爆船。
- **补给周期长**：回基地修船太远。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **即用即毁模式**：消耗性 NFT 在被调用后立即被 `burn` 掉，防止刷单。
2. **随机包设计**：使用 `sui::random`，玩家有小概率通过贩卖机抽到“超级修复包”（100% 满血恢复）。
3. **移动端支持**：通过钱包扫码快速购买，即使在激战中也能迅速完成充值。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] sui::random (随机增益抽取)
- [x] Move 核心机制 (消耗型 Object 销毁)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `MedKit`: 一次性消耗品。
- `VendingMachine`: 售货机库存。

## 📅 开发里程碑 (Milestones)
- [ ] 实现随机掉落概率
- [ ] 编写瞬间回复效果接口
- [ ] 增加物品限时失效机制
