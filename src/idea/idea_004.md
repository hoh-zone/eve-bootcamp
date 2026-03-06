# 4. 军团 CTA 出勤打卡器 (Guild Attendance Tracker)

## 💡 核心概念 (Concept)
一个部署在星门或集结点的智能网关。自动记录参与“集结行动”（CTA）的成员，并实时发放不可转让的荣誉凭证。

## 🧩 解决的痛点 (Pain Points Solved)
- **统计成本高**：传统军团需要专人截屏排查出勤，费时费力。
- **贡献不透明**：难以建立公平的军功奖励系统。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **地理围栏验证**：只有当玩家签名位置在特定星门范围内时，才能与合约交互。
2. **SBT (灵魂绑定代币)**：发放带有 `Combat_Log` 元数据的不可转移 NFT，作为积分凭证。
3. **智能分账**：战役结束后，指挥官将战利品 SUI 打入国库。国库合约根据本周内 SBT 的持有情况，PTB 批量发放分红。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Move 核心机制 (通过禁用 `transfer` 实现 SBT)
- [x] PTB (批量发放奖励，单笔交易支持上百人)
- [ ] SuiNS (显示人类可读的玩家名称)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `AttendanceBook`: 存储在特定 Epoch 签到的地址列表。
- `MeritPoint`: SBT。

## 📅 开发里程碑 (Milestones)
- [ ] 实现不可转移代币逻辑
- [ ] 编写指挥官管理面板
- [ ] 测试批量空投性能
