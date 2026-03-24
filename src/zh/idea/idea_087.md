# 87. KillMail 取证回放台

## 💡 核心概念 (Concept)
围绕 KillMail 做一个战损取证和战术回放平台。链上保存击杀事实、索引、提交者和资源哈希；链下保存录像、战斗日志、语音片段和战场截图。保险方、联盟指挥、雇佣兵和媒体团队可以通过同一套回放台判断赔付真伪、复盘战术、公开战报并生成教学内容。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Dynamic Fields / Object Fields：挂接多份取证材料和标签
- [x] Sponsored Transactions：方便受害者和第三方快速提交材料
- [x] Walrus：存放视频、日志和大体积回放文件
- [x] Move 核心机制 (Shared, Immutable)：公开索引和不可篡改证据摘要

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `EvidenceBoard`：某条 KillMail 的证据板
- `ReplayTicket`：付费或授权访问凭证
- `VerifierNote`：保险方或仲裁方批注

### 关键函数
- `attach_evidence`：追加录像、日志索引
- `verify_case`：写入审核结果
- `buy_replay_access`：购买回放权限
- `publish_report`：生成公开战报摘要

## 💻 前端与客户端交互层 (Frontend & Client)
做成 KillMail 详情页、时间线、地图热区和回放播放器。支持按联盟、星区、舰型和战损金额过滤。

## 💰 经济与商业模型 (Economic Model)
- 回放访问费
- 保险验证服务费
- 联盟战术课程
- 媒体栏目赞助

## 📅 开发里程碑 (Milestones)
- [ ] MVP：KillMail 与证据链接
- [ ] 回放查看页
- [ ] 仲裁与赔付批注
- [ ] 战术报告和订阅服务
