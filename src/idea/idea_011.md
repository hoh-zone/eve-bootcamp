# 11. 炮塔限时租赁协议 (Mercenary Firepower Renting)

## 💡 核心概念 (Concept)
允许玩家将高等级炮塔的控制权（OwnerCap）临时租赁给他人，到期后控制权通过合约逻辑自动收回。

## 🧩 解决的痛点 (Pain Points Solved)
- **火力不对等**：新手在危险区域挖矿极易被海盗骚扰，但买不起护卫舰。
- **资产价值浪费**：雇佣兵的重型炮塔在非战争时期只能闲置。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **时间戳限时授权**：租户支付 SUI，获得一个包含过期时间的 `Temporary_Access_Token`。
2. **所有权锁死**：租赁期间，租户只能执行 `shoot` 指令，无法执行 `unmount` 或 `transfer`。
3. **到期自动回收**：合约在处理指令前先检查 `Clock`。若时间已过，令牌自动失效，所有权流转回原主人的 Kiosk。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Sui Kiosk (受限所有权转发)
- [x] Move 核心机制 (通过内嵌时间戳实现自动过期逻辑)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `FirepowerToken`: 包含有效期的临时权限凭证。
- `RentVault`: 托管租金的共享对象。

## 📅 开发里程碑 (Milestones)
- [ ] 编写限时逻辑模块
- [ ] 实现受限所有权转移 API
- [ ] 开发租赁市场 UI 展示
