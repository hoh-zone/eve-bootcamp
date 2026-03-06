# Chapter 10：发布、维护与社区协作

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握从开发到上线的完整发布流程，理解 Builder 生态的边界与定位，成为可持续活跃的 EVE Frontier 构建者。

---

> 状态：发布与运营章节。正文以上线流程、维护和 Builder 协作为主。

## 前置依赖

- 建议先读 [Chapter 4](./chapter-04.md)
- 建议先读 [Chapter 9](./chapter-09.md)

## 源码位置

- [book/src/code/chapter-10](./code/chapter-10)

## 关键测试文件

- 当前目录以发布片段为主；重点是发布前验收清单。

## 推荐阅读顺序

1. 先读发布 checklist
2. 再对照 [book/src/code/chapter-10](./code/chapter-10) 中的片段
3. 最后把本章与 [Chapter 23](./chapter-23.md) 的产品化章节一起理解

## 验证步骤

1. 能列出上线前必须完成的 3-5 个验收动作
2. 能描述升级、回滚和沟通的基本策略
3. 能识别哪些事项应写进发布文档

## 常见报错

- 把“发布成功”等同于“产品完成”，忽略后续运维和社区协作

---

## 10.1 发布 checklist 全览

从本地开发到正式上线，需要经历以下阶段：

```
Phase 1 —— 本地开发（Localnet）
  ✅ Docker 本地链运行
  ✅ Move build 编译通过
  ✅ 单元测试全部通过
  ✅ 功能测试（脚本模拟完整流程）

Phase 2 —— 测试网（Testnet）
  ✅ sui client publish 到 testnet
  ✅ 扩展注册到测试组件
  ✅ dApp 部署到测试 URL
  ✅ 邀请小范围用户测试

Phase 3 —— 主网发布（Mainnet）
  ✅ 代码审计（自审 + 社区审查）
  ✅ 备份 UpgradeCap 到安全地址
  ✅ sui client switch --env mainnet
  ✅ 发布合约，记录 Package ID
  ✅ dApp 发布到正式域名
  ✅ 通知社区 / 更新公告
```

---

## 10.2 网络环境配置

Sui 和 EVE Frontier 支持三个网络：

| 网络 | 用途 | RPC 地址 |
|------|------|---------|
| **localnet** | 本地开发，Docker 启动 | `http://127.0.0.1:9000` |
| **testnet** | 公开测试，无真实价值 | `https://fullnode.testnet.sui.io:443` |
| **mainnet** | 正式生产环境 | `https://fullnode.mainnet.sui.io:443` |

```bash
# 切换到不同网络
sui client switch --env testnet
sui client switch --env mainnet

# 查看当前网络
sui client envs
sui client active-env

# 查看账户余额
sui client balance
```

### dApp 中的环境切换

```typescript
// 通过环境变量控制 dApp 连接的网络
const RPC_URL = import.meta.env.VITE_SUI_RPC_URL
  ?? 'https://fullnode.testnet.sui.io:443'

const WORLD_PACKAGE = import.meta.env.VITE_WORLD_PACKAGE
  ?? '0x...' // testnet 的 package id

const client = new SuiClient({ url: RPC_URL })
```

---

## 10.3 从 Testnet 到 Mainnet 的注意事项

- **Package ID 会变**：Mainnet 发布后得到新的 Package ID，dApp 配置需要更新
- **数据不通用**：Testnet 上创建的对象（角色、组件）在 Mainnet 上不存在，需要重新初始化
- **Gas 费真实**：Mainnet 的 SUI 有真实价值，发布和操作会消耗真实 Gas
- **不可撤销**：已共享（`share_object`）的对象无法撤回

---

## 10.4 Package 升级的最佳实践

### 安全存储 UpgradeCap

`UpgradeCap` 是最敏感的权限对象，一旦丢失则无法升级合约：

```bash
# 查看你的 UpgradeCap
sui client objects --json | grep -A5 "UpgradeCap"
```

**存储策略：**
1. **多签地址**：将 UpgradeCap 转到 2/3 多签地址，防止单点失控
2. **锁定时间**：可以加入时间锁机制，升级需要提前公告
3. **烧毁**（极端情况）：如果确认合约永远不需要升级，可以烧毁 UpgradeCap，彻底保证不可变性

```typescript
// 将 UpgradeCap 转移到多签地址
const tx = new Transaction()
tx.transferObjects(
  [tx.object(UPGRADE_CAP_ID)],
  tx.pure.address(MULTISIG_ADDRESS)
)
```

### 版本管理

建议在合约中维护版本号：

```move
const CURRENT_VERSION: u64 = 2;

public struct VersionedConfig has key {
    id: UID,
    version: u64,
    // ... 配置字段
}

// 升级时调用迁移函数
public entry fun migrate_v1_to_v2(
    config: &mut VersionedConfig,
    _cap: &UpgradeCap,
) {
    assert!(config.version == 1, EMigrationNotNeeded);
    // ... 执行数据迁移
    config.version = 2;
}
```

---

## 10.5 dApp 部署与托管

### 静态部署（推荐方案）

```bash
# 构建生产版本
npm run build

# 部署到 Vercel（自动 CI/CD）
vercel --prod

# 或部署到 GitHub Pages
gh-pages -d dist
```

**推荐平台：**
| 平台 | 特点 |
|------|------|
| **Vercel** | 自动 CI/CD，简单配置，免费额度充足 |
| **Cloudflare Pages** | 全球 CDN，支持 KV 存储扩展 |
| **IPFS/Arweave** | 真正的去中心化部署，永久存储 |

### 环境变量配置

```bash
# .env.production
VITE_SUI_RPC_URL=https://fullnode.mainnet.sui.io:443
VITE_WORLD_PACKAGE=0x_MAINNET_WORLD_PACKAGE_
VITE_MY_PACKAGE=0x_MAINNET_MY_PACKAGE_
VITE_TREASURY_ID=0x_MAINNET_TREASURY_ID_
```

---

## 10.6 Builder 在 EVE Frontier 的定位与约束

理解 Builder 的边界，对于长期成功至关重要：

### 你可以做的（Layer 3）

- ✅ 编写自定义扩展逻辑（Witness 模式）
- ✅ 构建新的经济机制（市场、拍卖、代币）
- ✅ 创建前端 dApp 界面
- ✅ 在已有设施类型上添加自定义规则
- ✅ 与其他 Builder 的合约组合使用

### 你不能改变的（Layer 1 & 2）

- ❌ 修改核心游戏物理规则（位置、能量系统）
- ❌ 创建全新类型的设施（只有 CCP 能做）
- ❌ 访问未公开的 Admin 操作
- ❌ 绕过 AdminACL 的服务器验证要求

### 设计技巧：在约束中找空间

```
官方限制：星门只能通过 JumpPermit 控制通行
你的扩展空间：
  ├── 许可证有效期（时效控制）
  ├── 许可证获取条件（付费/持有 NFT/任务完成）
  ├── 许可证的二级市场（转卖通行证）
  └── 许可证的批量购买折扣
```

---

## 10.7 社区协作与贡献

### 可组合性：你的合约可以被别人使用

当你发布了一个市场合约，其他 Builder 可以：
- 将你的价格预言机集成进他们的定价系统
- 在你的市场基础上增加推荐返佣
- 用你的代币作为他们服务的支付手段

**设计建议**：公开必要的读取接口，让你的合约对生态友好：

```move
// 公开查询接口，供其他合约调用
public fun get_current_price(market: &Market, item_type_id: u64): u64 {
    // 返回当前价格，其他合约可以用于定价参考
}

public fun is_item_available(market: &Market, item_type_id: u64): bool {
    table::contains(&market.listings, item_type_id)
}
```

### 参与官方文档贡献

EVE Frontier 文档是开源的：

```bash
# 克隆文档仓库
git clone https://github.com/evefrontier/builder-documentation.git

# 创建分支，添加你的教程或修正
git checkout -b feat/add-auction-tutorial

# 提交 PR
```

贡献内容包括：
- 发现并修正文档错误
- 补充缺失的示例代码
- 翻译文档到其他语言
- 分享你的最佳实践案例

### 行为准则

所有 Builder 必须遵守：
- ❌ 禁止通过编程基础设施骚扰或恶意攻击其他玩家
- ❌ 禁止欺骗性的经济行为（如蜜罐合约）
- ✅ 鼓励公平竞争和透明机制
- ✅ 鼓励集体分享知识和工具

---

## 10.8 可持续的 Builder 策略

### 经济可持续性

```
收入来源设计：
  ├── 手续费（市场交易的 1-3%）
  ├── 订阅服务（月度 LUX 订阅）
  ├── 高级功能（付费解锁）
  └── 联盟服务合同（B2B）

成本控制：
  ├── 使用读取 API（GraphQL/gRPC）替代高频链上写入
  ├── 聚合多个操作到单笔交易
  └── 利用赞助交易降低用户摩擦
```

### 技术可持续性

- **模块化设计**：将功能拆分成独立模块，方便独立升级
- **向后兼容**：新版本优先兼容旧版本数据
- **文档驱动**：记录你自己的合约 API，方便他人集成
- **监控告警**：订阅关键事件，当异常发生时获得通知

---

## 10.9 EVE Frontier 生态的未来

根据官方文档，以下功能在未来可能开放给 Builder：
- **更多组件类型**：冶炼厂、制造厂等工业设施的编程接口
- **零知识证明**：用 ZK proof 替代服务器签名做临近验证，实现完全去中心化
- **更丰富的经济接口**：更多官方 LUX/EVE Token 的交互接口

**设计原则**：为可扩展而设计。今天的合约应该能在明天的新功能上线后，通过升级无缝接入。

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 发布流程 | localnet → testnet → mainnet 三阶段 |
| 网络切换 | `sui client switch --env mainnet` |
| UpgradeCap 安全 | 多签存储，考虑时间锁 |
| dApp 部署 | Vercel/Cloudflare Pages + 环境变量 |
| Builder 约束 | Layer 3 自由扩展，Layer 1/2 不可改变 |
| 社区协作 | 开放 API、贡献文档、遵守行为准则 |
| 可持续策略 | 多元收入 + 模块化 + 监控 |

## 📚 延伸阅读

- [Builder 约束文档](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
- [Contributing Guide](https://github.com/evefrontier/builder-documentation/blob/main/CONTRIBUTING.md)
- [Sui Package 升级](https://docs.sui.io/guides/developer/packages/upgrade)
- [EVE Frontier 开发路线图（community channels）]
