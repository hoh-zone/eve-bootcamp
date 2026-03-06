# 6. 链上无头赏金所 (Bounty Hunter Escrow)

## 💡 核心概念 (Concept)
完全自动化的刺客平台。发布者悬赏特定玩家人头，合约在确认击杀后自动释放赏金给刺客。

## 🧩 解决的痛点 (Pain Points Solved)
- **黑吃黑**：传统暗杀经常发生“钱给了，人不杀”或“杀了人，钱没给”的情况。
- **匿名需求**：买凶者和刺客都希望在链上保持身份隐秘。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **Killmail 预言机**：合约对接 EVE 游戏服务器生成的战损日志证据。
2. **SUI 锁定**：赏金由合约托管。一旦触发 `Victim_ID == Bounty_Target` 逻辑。
3. **ZK-Login 提现**：刺客甚至不需要常用钱包接收，通过 ZK-Login 用临时社交账号（如 Twitch）生成新地址，隐秘领走赏金，彻底斩断社交关系链。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] zkLogin (暗中提款)
- [x] DeepBook (如果有复仇物资，可直接折算市价)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `BountyContract`: 共享对象，多方订阅。
- `Evidence`: 击杀凭证。

## 📅 开发里程碑 (Milestones)
- [ ] 编写证据哈希验证
- [ ] 实现自动打款奖励分配
- [ ] 测试多重签名发布悬赏
