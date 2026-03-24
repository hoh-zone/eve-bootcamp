# 19. 智能勒索炮塔 (Automated Ransomware Turret)

## 💡 核心概念 (Concept)
炮塔在锁定威胁后，不立即射击，而是向对方弹出支付界面。如果对方在 30 秒内支付设定金额的 SUI，其地址自动进入该炮塔的临时 10 分钟免疫白名单。

## 🧩 解决的痛点 (Pain Points Solved)
- **战斗损耗双输**：有些仗没必要打到死，双方都不想爆船赔钱。
- **收买门槛高**：战斗过程中无法快速谈拢保护费价格。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **锁定警报联动机**：炮塔组件感应到准星覆盖特定玩家。合约向该玩家发送一个 `Incoming_Threat` 事件通知。
2. **PTB 即时买命**：受害者点击 UI 调起支付交易。一旦付款成功，动态字段（Dynamic Field）写入 `{Address: Expire_Time}`。
3. **免伤协议**：在炮塔的 `fire` 逻辑头部，检查上述表项。若存在且有效，指令强制返回，从而实现“拿钱放人”。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] Dynamic Fields (高速存储临时的白名单权限)
- [x] PTB (买命钱与白名单写入的原子原子性)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `RansomRegistry`: 单个炮塔的保护费缴纳记录。
- `DefensePolicy`: 管理价格区间与免疫时长。

## 📅 开发里程碑 (Milestones)
- [ ] 编写锁定-支付交互流
- [ ] 实现自动检测白名单的火力开关
- [ ] 开发 UI 弹窗警告插件
