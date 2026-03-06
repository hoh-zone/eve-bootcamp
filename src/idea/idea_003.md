# 3. 去中心化太空典当行 (Space Pawnshop)

## 💡 核心概念 (Concept)
允许玩家将稀有 NFT（如涂装、蓝图）抵押给智能合约，换取流动性代币（SUI 或 EVE Credits），到期不还款则资产自动拍卖。

## 🧩 解决的痛点 (Pain Points Solved)
- **固定资产变现难**：持有极品蓝图但急需钱买弹药，卖掉舍不得，不卖没钱。
- **OTC 欺诈风险**：私下抵押容易被黑吃黑。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **资产托管 Kiosk**：使用 `Sui Kiosk` 存放抵押品，保证版税和所有权透明。
2. **抵押率计算**：根据 DeepBook 历史成交均价，自动设定 LTV（抵押率，如 50%）。
3. **清算机制**：引入时间戳。如果 `Clock::now_ms()` 超过赎回期限且债务未清，合约将资产所有权转移至 `Public Auction` 模式。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Sui Kiosk (安全资产存储)
- [x] DeepBook (价格参考 source)
- [ ] Move 核心机制

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `PawnTicket`: 代表抵押权证，包含逾期时间、本金、利息。

## 📅 开发里程碑 (Milestones)
- [ ] 集成 Kiosk 借券逻辑
- [ ] 对接价格预言机
- [ ] 实现拍卖自动切换
