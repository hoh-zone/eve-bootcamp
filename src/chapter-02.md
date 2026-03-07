# Chapter 2：Sui 与 EVE 环境配置

> **目标：** 只完成本书最基础、最必要的两项安装：`Sui CLI` 与 `EVE Vault`。本章不再展开 Git、Docker、Node.js、pnpm 这类通用开发工具。

---

> 状态：基础章节。正文只保留 Sui 与 EVE Frontier 直接相关的安装与配置。

##  2.1 本章只安装什么？

这一章只处理两类和本书直接相关的安装项：

| 工具 | 版本要求 | 用途 |
|------|---------|------|
| **Sui CLI** | testnet 版 | 编译、发布 Move 合约 |
| **EVE Vault** | 最新版 | 浏览器钱包 + 身份 |

---

##  2.2 为什么先只装这两样？

因为你在继续往下读之前，真正必须具备的最小能力只有两项：

- **本地能跑 `sui` 命令**
  你后面所有 Move 编译、测试、发布、对象查询都依赖它
- **浏览器里有一个可用的 EVE 钱包身份**
  你后面所有 dApp 连接、签名、领测试资产都依赖它

像 `Git`、`Docker`、`Node.js`、`pnpm` 当然后面还会用到，但它们属于：

- 通用开发工具
- 脚手架工程工具
- 前端和脚本运行工具

这些更适合在你进入 [Chapter 6](./chapter-06.md) 和 [Chapter 7](./chapter-07.md) 时，再结合工程目录一起装。

### 这一章真正要建立的，不只是两个软件

更准确地说，这一章是在建立两套工作入口：

- **命令行入口**
  给你做编译、发布、查询、测试
- **浏览器入口**
  给你做钱包连接、签名、dApp 交互

后面你几乎所有开发动作，都会在这两个入口之间来回切换：

- 写完合约，用 CLI 编译和发布
- 打开前端，用 EVE Vault 连接和签名
- 查对象时可能用 CLI，也可能用前端或 GraphQL

所以这章虽然看起来只是安装，实际上是在给后面全书铺“工作台”。

---

##  2.3 安装 Sui CLI

推荐直接使用官方的 `suiup` 安装方式。这样本章就不需要区分 Homebrew、apt、nvm 之类系统工具链。

```bash
# 安装 suiup
curl -sSfL https://raw.githubusercontent.com/MystenLabs/suiup/main/install.sh | sh

# 重新打开终端或 reload shell 后执行
suiup install sui@testnet

# 验证
sui --version
```

如果 `sui --version` 能正常输出版本号，本章第一步就算完成。

---

##  2.4 初始化 Sui 客户端

安装 Sui CLI 后，需要初始化客户端并连接网络：

```bash
# 初始化配置（首次运行会提示选择网络）
sui client

# 选择 testnet，或连接本地节点：
# localnet: http://0.0.0.0:9000

# 查看当前地址
sui client active-address

# 查看余额
sui client balance
```

### 你在这里到底完成了什么？

执行完 `sui client` 后，你本地会多出一套最基本的链上身份和网络配置：

- 当前活跃地址
- 当前默认网络
- 与该网络对应的 RPC 配置
- 本地 CLI 之后发交易和查对象时要用到的账户上下文

也就是说，`sui client` 不是单纯“看看余额”的命令，而是在给你后续所有 Move 开发动作打地基。

### `sui client` 和 EVE Vault 是什么关系？

这两个东西最容易让初学者混淆：

- `sui client` 是命令行环境里的身份与网络配置
- `EVE Vault` 是浏览器环境里的身份与签名入口

它们都能代表“你”，但服务的场景不同：

- 你在终端里发布合约、跑测试、查对象时，主要依赖 `sui client`
- 你在网页里连接 dApp、点击按钮、签名交易时，主要依赖 `EVE Vault`

### 它们必须是同一个地址吗？

不一定。

很多开发者会出现这种情况：

- CLI 用一个测试地址
- EVE Vault 里是另一个 zkLogin 地址

这不是绝对错误，但你必须非常清楚：

- 你现在在哪个地址上发包
- 你的设施归哪个地址或角色控制
- 你的前端连的是哪个钱包地址

只要这三件事没对齐，你就会频繁遇到“我明明发了，前端为什么看不到 / 不能操作”的问题。

### 从 Faucet 获取测试 SUI

如果连接的是 testnet：
```bash
# 通过 CLI 请求测试币
sui client faucet

# 或访问网页 Faucet：
# https://faucet.testnet.sui.io
```

---

##  2.5 安装并初始化 EVE Vault

**EVE Vault** 是你的浏览器身份，用于连接 dApp 和授权交易。

### 安装步骤

1. 下载最新版 Chrome 扩展：
   ```
   https://github.com/evefrontier/evevault/releases/download/v0.0.2/eve-vault-chrome.zip
   ```
2. 解压 zip 文件
3. 打开 Chrome → 扩展管理 → 开启"开发者模式"→ "加载已解压的扩展程序" → 选择解压文件夹
4. 点击扩展图标，使用 EVE Frontier SSO 账号（Google/Twitch 等）通过 **zkLogin** 创建你的 Sui 钱包

> **优势**：zkLogin 不需要助记词，你的 Sui 地址完全由你的 OAuth 身份唯一推导出，安全且便捷。

这里最值得理解的不是“安装方法”，而是它为什么会极大降低新用户门槛：

- 不需要先教育用户保存助记词
- 不需要先装一套传统钱包心智
- 用户可以直接用熟悉的账号体系进入链上交互

对 Builder 来说，这意味着你的 dApp 不必默认把用户当成“已经是资深加密用户的人”。这会直接影响你的产品设计方式：

- 登录和连接流程可以更短
- Gas 体验可以进一步配合赞助交易优化
- 你可以把重点放在设施体验，而不是钱包教育

---

##  2.6 EVE Vault 在本书里具体负责什么？

安装完 EVE Vault 后，它在后续章节里会承担三类职责：

- **钱包**
  持有 LUX、SUI、NFT、权限凭证
- **身份**
  用 EVE Frontier 账号进入链上交互体系
- **授权入口**
  给 dApp 提供连接、签名、赞助交易能力

你可以先把它理解成：

> `sui client` 是命令行里的链上身份，`EVE Vault` 是浏览器和 dApp 里的链上身份。

两者不一定是同一个地址，但它们都必须工作正常。

### 什么时候该先检查 CLI，什么时候该先检查钱包？

这能帮你更快定位问题：

- **合约编译失败**
  先看 CLI
- **发布交易失败**
  先看 CLI 当前网络和地址
- **前端连不上钱包**
  先看 EVE Vault
- **前端能连钱包但按钮报权限错误**
  先核对钱包地址、角色归属和对象权限

不要把所有链上问题都归咎于“钱包坏了”或者“CLI 配错了”。大多数时候，是你没有先分清问题发生在哪一层。

---

##  2.7 EVE Vault Faucet：获取测试资产

在开发和测试阶段，你至少会碰到两种测试资产：

- **测试 SUI**
  用于链上交易 Gas
- **测试 LUX**
  用于模拟 EVE Frontier 游戏内经济交互

获取 LUX 的方式：

1. 安装 EVE Vault 后，在扩展界面找到 **GAS Faucet**
2. 输入你的 Sui 地址请求测试代币
3. LUX 会出现在你的 EVE Vault 余额中

详细说明见：[GAS Faucet 文档](https://github.com/evefrontier/builder-documentation/blob/main/eve-vault/gas-faucet.md)

### 为什么测试阶段同时需要 SUI 和 LUX？

因为它们扮演的角色不同：

- **SUI**
  是链上交易的 Gas 资源，没有它很多交易连发都发不出去
- **LUX**
  更像 EVE Frontier 业务环境里的经济资产，很多教程和案例会用它模拟游戏内收费、结算、许可购买

如果你只有 SUI，没有 LUX：

- 你能发交易
- 但很多业务流程没法按书里的方式演练

如果你只有 LUX，没有 SUI：

- 你甚至很难完成最基础的链上交互

---

##  2.8 最小验收清单

到这里为止，你不需要马上跑脚手架，也不需要先装前端依赖。先确认下面四件事：

1. `sui --version` 能输出版本
2. `sui client active-address` 能返回当前地址
3. `EVE Vault` 已完成 zkLogin 初始化
4. 钱包里至少能看到测试资产或可请求 Faucet

如果这四件事都成立，说明你已经具备继续学习本书前半段的最小环境。

### 最常见的三种环境错位

#### 1. CLI 在 testnet，钱包却切在别的网络

表现：

- 终端里能查到对象
- 前端里看不到对应资产或组件

#### 2. CLI 地址和钱包地址不是同一个，但自己没意识到

表现：

- 合约是一个地址发的
- dApp 连的是另一个地址
- 前端操作时提示没有权限

#### 3. 水龙头领到了币，但领到了“另一套身份”上

表现：

- 你明明领过测试币
- 但当前正在用的钱包或 CLI 地址余额仍然是 0

一旦遇到“我明明做了，但系统说没有”这种问题，先不要急着怀疑教程。先把这三件事重新核对一遍。

### 什么时候再装其他工具？

- 到 [Chapter 6](./chapter-06.md)：再装和使用 `builder-scaffold`
- 到 [Chapter 7](./chapter-07.md)：再处理脚本与 dApp 依赖
- 到具体案例章节：再按案例需要补充前端运行环境

## 🔖 本章小结

| 步骤 | 操作 |
|------|------|
| 安装 Sui CLI | `suiup install sui@testnet` |
| 配置 Sui 客户端 | `sui client` 选择网络并创建地址 |
| 安装 EVE Vault | Chrome 扩展 + zkLogin 创建链上身份 |
| 获取测试资产 | SUI Faucet + EVE Vault GAS Faucet |
| 验证环境 | CLI 地址、钱包地址、网络、余额都可见 |

## 📚 延伸阅读

- [Sui CLI 完整文档](https://docs.sui.io/references/cli)
- [Sui 客户端配置指南](https://docs.sui.io/guides/developer/getting-started/configure-sui-client)
- [EVE Vault](https://github.com/evefrontier/evevault)
- [EVE Vault GAS Faucet 文档](https://github.com/evefrontier/builder-documentation/blob/main/eve-vault/gas-faucet.md)
