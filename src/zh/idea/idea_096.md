# 96. 诅咒突变古神兵

## 💡 核心概念 (Concept)
做一套会随着击杀、重铸、修复和献祭不断突变的危险武器系统。古神兵会成长，也会反噬：可能获得强力词条，也可能带来诅咒效果、维护成本或对某类目标的极端偏执。玩家需要决定是继续养成、卖给收藏家、拿去祭坛洗练，还是趁还没失控时封印。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Dynamic Fields / Object Fields：记录突变历史、词条和诅咒状态
- [x] sui::random：结算突变方向
- [x] Sponsored Transactions：降低祭坛交互门槛
- [x] Sui Kiosk：交易危险装备
- [x] Move 核心机制 (Owned)：武器作为独立成长对象

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `AncientWeapon`：神兵本体
- `MutationRecord`：突变记录
- `CurseAltar`：祭坛或洗练台

### 关键函数
- `feed_killmail`：用 KillMail 驱动成长
- `mutate_weapon`：触发突变
- `purify_weapon`：尝试净化副作用
- `seal_weapon`：将其封存为藏品

## 💻 前端与客户端交互层 (Frontend & Client)
前端展示成长树、突变日志、风险评级和交易价格曲线。适合做收藏市场和 PvP 装备秀场。

## 💰 经济与商业模型 (Economic Model)
- 洗练费
- 祭坛通行费
- 稀有装备交易费
- 收藏和展览服务

## 📅 开发里程碑 (Milestones)
- [ ] MVP：成长记录
- [ ] 随机突变
- [ ] 净化与封印
- [ ] 交易和排行榜
