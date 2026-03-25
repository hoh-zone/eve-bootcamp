# 86. 开源舰队 AI 策略仓库

## 💡 核心概念 (Concept)
打造一个“舰队 AI 与策略插件市场”。Builder 可以上传炮塔优先级策略、物流调度脚本、价格模型、风险评分器、门禁规则模板和防区配置，把版本、作者、授权方式和收益分成公开化。其他玩家或联盟可以直接购买、订阅、fork 或审计这些策略，让“规则设计能力”本身成为可交易资产。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Dynamic Fields / Object Fields：保存版本、标签、兼容组件和参数模板
- [x] Sponsored Transactions：方便试用和快速部署模板
- [x] Sui Kiosk：展示和售卖策略授权
- [x] Walrus：存放大体积文档、回测报告和样例数据
- [x] Move 核心机制 (Shared, Owned)：区分公开模板和私有部署实例

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `StrategyTemplate`：策略模板对象
- `StrategyLicense`：购买后获得的使用许可
- `DeploymentProfile`：联盟自己的参数实例

### 关键函数
- `publish_strategy`：发布策略模板
- `buy_license`：购买部署权或订阅权
- `clone_profile`：从模板派生自己的配置
- `rate_strategy`：记录评价和实战反馈

## 💻 前端与客户端交互层 (Frontend & Client)
前端展示策略市场、参数面板、兼容组件、历史版本和战绩摘要。支持一键把某个模板部署到 Turret、Gate 或 StorageUnit 扩展项目里。

## 💰 经济与商业模型 (Economic Model)
- 模板售卖
- 订阅更新
- 高级参数包
- 战绩认证与专家服务费

## 📅 开发里程碑 (Milestones)
- [ ] MVP：模板上架与购买
- [ ] 策略版本管理
- [ ] 参数 fork 与部署配置
- [ ] 实战评分和收益分成
