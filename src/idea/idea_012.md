# 12. 太空海关扣款机 (Customs & Tax Stargate)

## 💡 核心概念 (Concept)
部署在关键交通咽喉的强制扣款系统，对通过的非白名单玩家强制征收资产比例税。

## 🧩 解决的痛点 (Pain Points Solved)
- **逃税行为**：手动收费容易被玩家通过“赖账”或“硬闯”规避。
- **公共基建补偿**：控制星区的公会需要持续支出维护费用，需稳定的税收覆盖。

## 🎮 详细玩法与机制 (Gameplay Mechanics)
1. **余额强扣机制**：利用 Sui 的 $SUI 余额检查。如果玩家想通过星门，PTB 会在第一步尝试从其钱包 `split` 出一定比例（如 1%）的 $SUI。
2. **拦截判定**：若余额不足或余额被“藏匿”到不透明容器中，星门合约将无法生成“通行准证（Jump Ticket）”。
3. **白名单免税**：友方公会地址在 `Stargate_config` 中有永久豁免权。

## 🛠️ Sui 核心特性应用 (Sui Features)
- [x] PTB (确保扣款与通行是原子绑定的)
- [x] Dynamic Fields (存储海量的白名单及税收配额)

## 📐 智能合约架构规划 (Smart Contract Architecture)
### 核心 Object
- `CustomsConfig`: 控制税收比例的共享配置对象。
- `TaxRegistry`: 记录各大组织历史税费贡献。

## 📅 开发里程碑 (Milestones)
- [ ] 编写动态比例扣款合约
- [ ] 实现跨合约通行调用
- [ ] 设计税收数据仪表盘
