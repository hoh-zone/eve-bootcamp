# 14. 死人开关：遗产继承器 (Dead-Man's Switch Inheritor)

## 💡 核心概念 (Concept)
如果玩家在设定时间内（如 30 天）没有任何链上交互，其名下的房产、飞船、资源控制权自动移交给指定的继承人。

## 🧩 解决的痛点 (Pain Points Solved)
- **资产沉没**：大佬突然退游（卖号/忘记私钥），名下数亿资产成为无法被利用的死物。
- **传承中断**：小型公会会长退坑时无法平滑将公会权限卡交给副会长。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **心跳包监听**：合约记录玩家每次签名的 `Timestamp`。
2. **激活判定**：当外界（继承人）发起继承请求时，合约核对 `Current_Time - Last_Active_Time > Threshold`。
3. **所有权级联转移**：利用 Move 的 `transfer` 功能，将原本绑定在受赠人名下的 `Kiosk` 或控制权对象的所有权进行强制重置。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Move 核心机制 (通过时间戳进行所有权强制流转)
- [x] Sui Kiosk (批量移交资产包)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `WillBook`: 指定继承关系和激活条件的映射表。
- `InheritanceCapsule`: 包含遗产资产的容器。

## 📅 开发里程碑 (Milestones)
- [ ] 编写交互时间记录模块
- [ ] 实现继承权激活验证
- [ ] 资产批量转移逻辑压力测试
