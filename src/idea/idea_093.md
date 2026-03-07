# 93. 联盟多签金库与军费保险箱

## 💡 核心概念 (Concept)
为联盟和大型组织设计一个真正可审计的军费系统。税收、战利品收入、补给预算和战争赔款全部进入多签金库，由不同角色分别掌握审批、付款、冻结和审计权。它解决的不是“做个钱包”，而是联盟组织最真实的治理问题：预算纪律、防卷款跑路和战时财务透明。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] PTB (可编程交易块)：一笔交易里完成审批和拨款
- [x] Dynamic Fields / Object Fields：保存预算项、角色权限和付款记录
- [x] Sponsored Transactions：方便普通官员提交审批动作
- [x] Move 核心机制 (Shared, Owned)：共享金库和私有签署权结合

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `AllianceTreasury`：联盟金库
- `BudgetRequest`：预算申请单
- `SignerRole`：角色权限配置

### 关键函数
- `submit_budget`：提交军费申请
- `approve_budget`：多签审批
- `execute_payout`：付款执行
- `freeze_treasury`：紧急冻结

## 💻 前端与客户端交互层 (Frontend & Client)
前端展示预算面板、签署状态、账单流水、审计报告和权限树。适合联盟管理后台和 Discord 机器人提醒。

## 💰 经济与商业模型 (Economic Model)
- 联盟 SaaS 服务费
- 审计和风控增值服务
- 战时预算模板订阅
- 数据导出和报表服务

## 📅 开发里程碑 (Milestones)
- [ ] MVP：多签金库和付款
- [ ] 预算流程
- [ ] 冻结与审计
- [ ] 联盟后台集成
