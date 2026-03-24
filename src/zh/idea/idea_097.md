# 97. 红名自动截杀网

## 💡 核心概念 (Concept)
围绕信誉、红名和 KillMail 数据做一张自动协防网络。联盟或赏金组织把高风险目标同步到多个 Gate 和 Turret 节点，一旦目标接近某条航线或边境区域，就触发预警、加价、拒绝通行甚至自动攻击。它把原本分散的单点防御升级成一张区域化安全网。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Dynamic Fields / Object Fields：保存红名名单、危险级别和区域策略
- [x] Sponsored Transactions：快速同步协防策略
- [x] Move 核心机制 (Shared, Owned)：共享规则网络与私有控制权结合

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `RedlistRegistry`：红名注册表
- `DefenseNodeProfile`：某个 Gate 或 Turret 的协防配置
- `BountyExecutionLog`：执行记录

### 关键函数
- `mark_target`：标记高风险目标
- `sync_profile`：同步到某个防御节点
- `trigger_penalty`：执行拒绝、加价或攻击策略
- `clear_target`：移除目标

## 💻 前端与客户端交互层 (Frontend & Client)
前端提供区域热图、拦截日志、红名榜和防线状态页。适合联盟安全后台和赏金追猎面板。

## 💰 经济与商业模型 (Economic Model)
- 安全网络订阅
- 赏金执行分成
- 防区托管服务
- 区域治安评分 API

## 📅 开发里程碑 (Milestones)
- [ ] MVP：红名注册和单节点同步
- [ ] 多节点协防
- [ ] 赏金执行结算
- [ ] 区域安全评分
