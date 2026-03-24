# 90. 永久战争纪念碑

## 💡 核心概念 (Concept)
用 immutable object 的思路做“不可篡改纪念碑”，而不是不合理的无敌建筑。联盟在完成史诗远征、守住重要星系或经历惨烈战役后，可以把战役摘要、牺牲者名单、胜利宣言和纪念影像铸成永久纪念碑。纪念碑本体不可改写，但周边可以衍生纪念活动、军校导览、纪念 NFT 和打赏墙。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Sponsored Transactions：方便联盟集体参与铸碑
- [x] Sui Kiosk：售卖纪念周边或纪念票
- [x] Walrus：保存高清纪念影像与文档
- [x] Move 核心机制 (Immutable)：纪念碑正文不可篡改

## 📐 智能合约架构规划 (Smart Contract Architecture)

### 核心 Object
- `WarMemorial`：纪念碑本体
- `MemorialPass`：纪念活动票或纪念 NFT
- `TributeVault`：打赏和纪念基金

### 关键函数
- `mint_memorial`：铸造纪念碑
- `append_tribute`：追加打赏或悼词索引
- `buy_memorial_pass`：购买纪念物
- `fund_veterans`：从纪念基金拨款

## 💻 前端与客户端交互层 (Frontend & Client)
做成战争纪念馆页面、时间轴、地图与英雄名录。游戏内可以为纪念碑周边做导览和献花交互。

## 💰 经济与商业模型 (Economic Model)
- 纪念周边售卖
- 联盟纪念基金
- 教学战史订阅
- 品牌合作和活动赞助

## 📅 开发里程碑 (Milestones)
- [ ] MVP：铸造纪念碑和展示页
- [ ] 影像与名录归档
- [ ] 纪念周边发行
- [ ] 联盟基金和导览活动
