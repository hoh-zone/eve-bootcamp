# 92. 旗舰试驾与限时借舰库

## 💡 核心概念 (Concept)
用 Borrow 模式做高价值舰船和设施的“限时借用”系统。新手可以试驾昂贵舰船，赛事组织可以发放赞助舰，富玩家可以把自己的旗舰短租给别人。系统通过押金、时限、活动范围和自动回收规则，让借用体验更安全。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] PTB (可编程交易块)：借出、押金、归还在一笔链路里结算
- [x] Sponsored Transactions：降低试驾门槛
- [x] Move 核心机制 (Borrow, Owned)：体现限时借用与回收

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `RentalGarage`：租赁车库
- `BorrowTicket`：借用凭证
- `DepositVault`：押金池

### 关键函数
- `list_ship`：上架可借用舰只
- `borrow_ship`：支付押金后借出
- `return_ship`：归还并结算
- `slash_deposit`：逾期或违规扣押金

## 💻 前端与客户端交互层 (Frontend & Client)
前端展示舰船库、试驾套餐、剩余借用时间和押金状态。支持赛事专属邀请码和联盟内部借舰。

## 💰 经济与商业模型 (Economic Model)
- 租金
- 押金利差
- 赛事赞助舰套餐
- 高端舰体验服务

## 📅 开发里程碑 (Milestones)
- [ ] MVP：上架与借还
- [ ] 押金和违规结算
- [ ] 赛事模式与联盟模式
- [ ] 舰队体验套餐
