# 85. 星际广播电台与航线播报网

## 💡 核心概念 (Concept)
做一个面向全宇宙航线与基地节点的广播网络。联盟、商会、佣兵组织和媒体团队可以创建自己的频道，发布战争简报、航线预警、交易广告、护航招募和活动节目。链上保存频道归属、收费规则、打赏记录和节目索引，音频或录像存放在 Walrus。玩家经过某座 Gate、进入某个基地或打开 dApp 时，就能收到对应区域的实时播报。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Dynamic Fields / Object Fields：保存频道、节目单、赞助位和地区标签
- [x] zkLogin：让普通玩家低门槛订阅、打赏和收藏频道
- [x] Sponsored Transactions：降低听众订阅和互动门槛
- [x] SuiNS：为频道绑定易记名称，如 `war-room.sui`
- [x] Walrus：存储长音频、录像回放和档案节目

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `RadioStation`：电台本体，记录台长、频道名、收费模式、区域标签
- `ProgramPass`：订阅票或单期收听凭证
- `BroadcastArchive`：节目索引、Walrus 资源指针、赞助记录

### 关键函数
- `create_station`：创建电台和默认频道
- `publish_program`：发布节目索引与资源链接
- `buy_pass`：购买频道订阅或单期收听权限
- `tip_station`：给主播或频道打赏

## 💻 前端与客户端交互层 (Frontend & Client)
做一个“银河电台”页面，按星区、联盟、语言、类型筛选节目。游戏内浮层可根据当前位置推送本地基地的广播、道路警报和活动招募。

## 💰 经济与商业模型 (Economic Model)
- 订阅费
- 单期付费节目
- 广告位和赞助位
- 主播分成和频道联盟抽成

## 📅 开发里程碑 (Milestones)
- [ ] MVP：单频道发布和订阅
- [ ] 加入 Walrus 资源索引
- [ ] 游戏内区域化广播推送
- [ ] 多频道排行榜和赞助系统
