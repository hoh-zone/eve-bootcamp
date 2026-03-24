# 17. 异星资源期货交易所 (Fuel Futures Exchange)

## 💡 核心概念 (Concept)
允许玩家将未来预计产出的资源（如：下一星期的燃料产出预期）代币化并进行提前交易和套期保值。

## 🧩 解决的痛点 (Pain Points Solved)
- **价格剧烈波动**：临近决战，燃料价格暴涨，公会需要提前锁定成本。
- **现金流压力**：矿工需要提前拿到资金升级设备。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **产能债券化**：矿工抵押自己的资源发生器 Object。合约基于其产能，发行对应的“产能通证（Futures Token）”。
2. **DeepBook 限价单撮合**：利用 DeepBook 作为底层引擎，让买卖双方进行期货对赌交易。
3. **到期实物交割**：合约设定到期时间。到期时，产能通证的持有者可以直接从矿工的产出 Object 中提取对应的实物资源。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] DeepBook (中央限价订单簿交易)
- [x] Move 核心机制 (产能通证的铸造与销毁)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `FutureToken`: 代表未来资源权属。
- `SettlementVault`: 结算金库。

## 📅 开发里程碑 (Milestones)
- [ ] 集成 DeepBook 交易对
- [ ] 编写产能评估与债券发行逻辑
- [ ] 开发交割清算系统
