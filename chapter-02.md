# Chapter 2：开发环境配置与工具链

> ⏱ 预计学习时间：2 小时
>
> **目标：** 从零搭建 EVE Frontier 本地开发环境，配置好 Sui CLI、EVE Vault 钱包，并跑通脚手架项目。

---

## 2.1 工具清单

在开始之前，确认你需要安装的工具：

| 工具 | 版本要求 | 用途 |
|------|---------|------|
| **Git** | 任意 | 代码管理 |
| **Docker** | 最新版 | 推荐搭建本地 Sui 测试链 |
| **Sui CLI** | testnet 版 | 编译、发布 Move 合约 |
| **Node.js** | v24 LTS | 前端 dApp 开发 / TypeScript 脚本 |
| **pnpm** | 最新版 | 包管理器 |
| **EVE Vault** | 最新版 | 浏览器钱包 + 身份 |

---

## 2.2 方法一（推荐）：Docker + builder-scaffold

Docker 方法适用于所有操作系统，无需手动处理系统级依赖，是最快的上手方式。

### 步骤一：克隆脚手架仓库

```bash
git clone https://github.com/evefrontier/builder-scaffold.git
cd builder-scaffold
```

`builder-scaffold` 是 EVE Frontier 官方提供的开发模板，包含：
- 预配置的 Sui 本地测试网（localnet）Docker 环境
- 示例 Move 合约（Smart Gate、Storage Unit 扩展）
- TypeScript 交互脚本

### 步骤二：启动 Docker 本地链

```bash
cd docker
# 按照 docker/readme.md 中的指引启动
docker compose up -d
```

启动后你会获得：
- 一个运行中的 Sui localnet 节点
- 预部署好的 EVE Frontier World Contracts（游戏世界合约）
- 测试用账号和 SUI 代币

> ✅ **验证**：打开浏览器访问 `http://localhost:9001` 确认本地节点在线

---

## 2.3 方法二：手动安装（按操作系统）

如果你不想使用 Docker，按照你的系统逐步安装。

### macOS

```bash
# 1. 安装 Homebrew（如果没有）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
export PATH="/opt/homebrew/bin:$PATH"

# 2. 安装 Git
brew install git

# 3. 安装 Sui CLI（推荐 suiup 方式）
curl -sSfL https://raw.githubusercontent.com/MystenLabs/suiup/main/install.sh | sh
# 重新打开终端后执行：
suiup install sui@testnet

# 验证安装
sui --version

# 4. 安装 Node.js 和 pnpm
brew install node@24
npm install -g pnpm
```

### Linux (Ubuntu 22.04+)

```bash
# 1. 安装基础工具
sudo apt-get install git curl

# 2. 安装 Sui CLI
curl -sSfL https://raw.githubusercontent.com/MystenLabs/suiup/main/install.sh | sh
# 重启 shell 后：
suiup install sui@testnet

# 3. 安装 Node.js 和 pnpm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash && . ~/.bashrc && nvm install 24
npm install -g pnpm
```

### Windows

推荐使用 **Git Bash** 来运行脚本命令：

```bash
# 1. 安装 Git for Windows：https://git-scm.com/download/win
# 使用 Git Bash 运行以下命令：

# 2. 安装 suiup
curl -sSfL https://raw.githubusercontent.com/MystenLabs/suiup/main/install.sh | sh

# 在 PowerShell 中安装 Sui
suiup install sui@testnet

# 验证
sui --version
```

---

## 2.4 配置 Sui 客户端

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

### 从 Faucet 获取测试 SUI

如果连接的是 testnet：
```bash
# 通过 CLI 请求测试币
sui client faucet

# 或访问网页 Faucet：
# https://faucet.testnet.sui.io
```

如果使用本地 Docker 网络，脚手架中已经包含了 Faucet 设置，无需手动请求。

---

## 2.5 安装配置 EVE Vault 浏览器钱包

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

---

## 2.6 理解 builder-scaffold 项目结构

打开 `builder-scaffold`，了解目录结构：

```
builder-scaffold/
├── docker/                   # Docker 本地链配置
│   ├── readme.md             # 启动说明
│   └── docker-compose.yml   # 服务定义
│
├── move-contracts/           # 示例 Move 合约
│   ├── smart_gate/           # 智能星门扩展示例
│   │   └── sources/
│   │       └── smart_gate.move
│   └── storage_unit/         # 智能存储箱扩展示例（如有）
│
├── ts-scripts/               # TypeScript 交互脚本
│   ├── setup/                # 初始化脚本（创建角色、建设施等）
│   └── ...
│
└── README.md
```

### 关键文件：`Move.toml`

每个 Move 项目都有一个配置文件：

```toml
[package]
name = "smart_gate"
version = "0.0.1"

[dependencies]
# 指向游戏世界合约依赖
WorldContracts = { git = "https://github.com/evefrontier/world-contracts.git", subdir = "contracts/world", rev = "main" }
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "testnet" }

[addresses]
smart_gate = "0x0"
```

---

## 2.7 验证环境：编译示例合约

```bash
cd builder-scaffold/move-contracts/smart_gate

# 编译合约（检查语法和类型）
sui move build

# 预期输出：
# UPDATING GIT DEPENDENCY ...
# INCLUDING DEPENDENCY ...
# BUILDING smart_gate
```

> ✅ **如果编译成功**，说明你的 Sui CLI、Move 依赖配置都正确。

---

## 2.8 EVE Vault Faucet：获取 LUX 测试代币

在开发和测试阶段，你需要 LUX 来模拟游戏内经济操作：

1. 安装 EVE Vault 后，在扩展界面找到 **GAS Faucet**
2. 输入你的 Sui 地址请求测试代币
3. LUX 会出现在你的 EVE Vault 余额中

详细说明见：[GAS Faucet 文档](../eve-vault/gas-faucet.md)

---

## 🔖 本章小结

| 步骤 | 操作 |
|------|------|
| 克隆脚手架 | `git clone https://github.com/evefrontier/builder-scaffold.git` |
| 启动本地链 | `cd docker && docker compose up -d` (推荐) 或手动装 Sui CLI |
| 配置 Sui 客户端 | `sui client` 选择网络并创建地址 |
| 安装 EVE Vault | Chrome 扩展 + zkLogin 创建链上身份 |
| 验证环境 | `sui move build` 编译示例合约通过 |

## 📚 延伸阅读

- [Environment Setup 文档](../tools/environment-setup.md)
- [builder-scaffold GitHub](https://github.com/evefrontier/builder-scaffold)
- [Sui CLI 完整文档](https://docs.sui.io/references/cli)
- [Sui 客户端配置指南](https://docs.sui.io/guides/developer/getting-started/configure-sui-client)
