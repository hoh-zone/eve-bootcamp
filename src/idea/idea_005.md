# 5. 动态拥堵收费星门 (Dynamic Toll Stargate)

## 💡 核心概念 (Concept)
利用算法自动调节交通费用的星门收费组件。流量越大，过路费越贵，收益归星门拥有者联盟。

## 🧩 解决的痛点 (Pain Points Solved)
- **战略切割难**：无法有效阻止敌对舰队大规模借道。
- **商业化效率低**：固定收费无法应对战争期间的爆发性需求。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **AMM 类定价算法**：模拟 Uniswap 的 `x*y=k` 或线性增长。每分钟内通过的船只越多，下一艘船的费用按 `Base_Fee * (1 + 0.1^N)` 增长。
2. **白名单减免**：本公会成员通过 Dynamic Field 验证，享受固定 0 费用。
3. **战略护城河**：在决战时刻，通过极高的过路费让敌后勤物资保障（弹药/燃料）面临巨大的经济压力。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Dynamic Fields (存储每个地址的临时折扣/凭证)
- [x] Sponsored Transactions (为友好盟友代付路费)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `GateTreasury`: 存储收益。
- `FlowController`: 动态参数调整。

## 📅 开发里程碑 (Milestones)
- [ ] 编写定价曲线合约
- [ ] 实现白名单列表管理
- [ ] 前端展示实时地价图
