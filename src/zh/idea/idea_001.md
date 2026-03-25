# 1. 太空闪电贷 (Space Flash Loan)

## 💡 核心概念 (Concept)
利用 Sui 的 PTB (Programmable Transaction Blocks) 实现“原子级”的资产借贷。玩家在单次交易内借入高价值飞船，完成采矿或贸易，最后归还飞船并支付利息。

## 🧩 解决的痛点 (Pain Points Solved)
- **准入门槛高**：新手玩家买不起昂贵的旗舰，导致无法体验高级内容。
- **资产闲置**：老玩家的大量飞船在机库吃灰，缺乏安全的租赁机制，担心租出去收不回来。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **Hot Potato 强制约束**：利用 Move 语言的 `Hot Potato` 模式。当玩家调用 `borrow_ship` 时，系统返回一个没有 `drop` 能力的凭证（Receipt）。
2. **原子化操作环**：在同一个 PTB 中，第二步必须是使用该船进行某种获利行为（如触发采矿合约），第三步必须调用 `return_ship` 销毁凭证并交还资产所有权。
3. **零风险租赁**：如果交易中途飞船被炸毁或余额不足支付利息，整个 PTB 会直接回滚，飞船依然安全地留在出借人的合约中，甚至时空“倒流”回出发前。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] PTB (原子化借-用-还闭环)
- [x] Move 核心机制 (Hot Potato 锁定交易完整性)
- [ ] zkLogin
- [ ] sui::random

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `LoanPool`: 共享对象，存放可借出的飞船 Kiosk 权限。
- `BorrowReceipt`: Hot Potato，确保借出后必须在同笔交易归还。

## 📅 开发里程碑 (Milestones)
- [ ] 设计借贷协议接口
- [ ] 实现 Hot Potato 逻辑测试
- [ ] 集成 EVE World 物品所有权校验
