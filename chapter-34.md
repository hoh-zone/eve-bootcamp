# 第34章：EVE Vault 技术架构与开发部署

> **学习目标**：理解 EVE Vault 的 Chrome MV3 架构（5 层脚本、消息协议、Keeper 安全容器），掌握本地构建和调试扩展的完整流程，以及 Monorepo 中各包的分工。

---

## 1. 项目结构（Monorepo）

```
evevault/
├── apps/
│   ├── extension/          # Chrome MV3 扩展（主体）
│   │   ├── entrypoints/    # WXT 入口点（每个 = 一个独立页面/脚本）
│   │   │   ├── background.ts        # Service Worker（后台常驻）
│   │   │   ├── content.ts           # 内容脚本（每个页面注入）
│   │   │   ├── injected.ts          # 页面上下文脚本（注册钱包）
│   │   │   ├── popup/               # 扩展弹窗
│   │   │   ├── sign_transaction/    # 交易审批页
│   │   │   ├── sign_sponsored_transaction/ # 赞助交易审批页
│   │   │   ├── sign_personal_message/     # 消息签名审批页
│   │   │   ├── sign_and_execute_transaction/
│   │   │   └── keeper/              # 安全密钥容器
│   │   └── src/
│   │       ├── features/   # 功能模块（auth、wallet）
│   │       ├── lib/        # 核心库（adapters、background、utils）
│   │       └── routes/     # React 路由（TanStack Router）
│   └── web/                # Web 版本（即将推出）
└── packages/
    └── shared/             # 跨 app 共享：类型、Sui 客户端、工具函数
        └── src/
            ├── types/      # 消息类型、钱包类型、认证类型
            ├── sui/        # SuiClient、GraphQL 客户端
            └── auth/       # Enoki 集成、zkLogin 工具
```

**构建工具**：Bun（包管理）+ Turborepo（构建缓存）+ WXT（扩展框架）

---

## 2. Chrome MV3 的 5 层脚本架构

Chrome MV3 扩展中各脚本的隔离边界和通信方式：

```
┌──────────────────── 浏览器 Tab（网页）───────────────────────┐
│                                                               │
│  dApp（网页 JavaScript）                                       │
│      ↕ wallet-standard API（同进程调用）                      │
│  injected.ts ← 由 content.ts 注入到页面进程                   │
│      EveVaultWallet 类注册到 @mysten/wallet-standard           │
└───────────────────────────────────────────────────────────────┘
               ↕ window.postMessage（跨进程）
┌──────────────────── Chrome Extension 进程 ────────────────────┐
│  content.ts（内容脚本）                                        │
│      转发：页面 → background                                  │
│      转发：background → 页面                                  │
└───────────────────────────────────────────────────────────────┘
               ↕ chrome.runtime.sendMessage
┌──────────────────── Service Worker ────────────────────────────┐
│  background.ts                                                  │
│      OAuth 流程、Token 交换、Storage 管理                      │
│      处理签名请求（转发给 Keeper）                             │
│      ↕ chrome.runtime Port                                    │
│  keeper.ts（隐藏 iframe，内存安全容器）                        │
│      存储临时私钥（不写 chrome.storage）                       │
└─────────────────────────────────────────────────────────────────┘
               ↕ chrome.runtime.sendMessage
┌──────────────────── Extension Pages ───────────────────────────┐
│  popup/               ← 点击扩展图标显示                       │
│  sign_transaction/    ← 交易审批弹窗                           │
│  sign_sponsored_transaction/ ← 赞助交易审批                   │
│  sign_personal_message/ ← 消息签名审批                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 消息系统（Message Protocol）

所有跨进程通信通过标准化的消息类型定义：

```typescript
// packages/shared/src/types/messages.ts

// 认证相关消息
export enum AuthMessageTypes {
    AUTH_SUCCESS = "auth_success",
    AUTH_ERROR = "auth_error",
    EXT_LOGIN = "ext_login",
    REFRESH_TOKEN = "refresh_token",
}

// Vault（加密容器）消息
export enum VaultMessageTypes {
    UNLOCK_VAULT = "UNLOCK_VAULT",
    LOCK = "LOCK",
    CREATE_KEYPAIR = "CREATE_KEYPAIR",
    GET_PUBLIC_KEY = "GET_PUBLIC_KEY",
    ZK_EPH_SIGN_BYTES = "ZK_EPH_SIGN_BYTES",  // 用临时私钥签名
    SET_ZKPROOF = "SET_ZKPROOF",
    GET_ZKPROOF = "GET_ZKPROOF",
    CLEAR_ZKPROOF = "CLEAR_ZKPROOF",
}

// Wallet Standard 相关（dApp 触发）
export enum WalletStandardMessageTypes {
    SIGN_PERSONAL_MESSAGE = "sign_personal_message",
    SIGN_TRANSACTION = "sign_transaction",
    SIGN_AND_EXECUTE_TRANSACTION = "sign_and_execute_transaction",
    EVEFRONTIER_SIGN_SPONSORED_TRANSACTION = "sign_sponsored_transaction",
}

// Keeper 安全容器消息
export enum KeeperMessageTypes {
    READY = "KEEPER_READY",
    CREATE_KEYPAIR = "KEEPER_CREATE_KEYPAIR",
    UNLOCK_VAULT = "KEEPER_UNLOCK_VAULT",
    GET_PUBLIC_KEY = "KEEPER_GET_KEY",
    EPH_SIGN = "KEEPER_EPH_SIGN",       // 临时私钥签名
    CLEAR_EPHKEY = "KEEPER_CLEAR_EPHKEY",
    SET_ZKPROOF = "KEEPER_SET_ZKPROOF",
    GET_ZKPROOF = "KEEPER_GET_ZKPROOF",
    CLEAR_ZKPROOF = "KEEPER_CLEAR_ZKPROOF",
}
```

### 消息流：dApp 签名请求的完整路径

```
dApp 调用 wallet.signTransaction(tx)
    ↓ wallet-standard（同进程）
injected.ts (EveVaultWallet.signTransaction)
    ↓ window.postMessage({ type: "sign_transaction", ... })
content.ts
    ↓ chrome.runtime.sendMessage(...)
background.ts（walletHandlers.ts）
    → 打开 sign_transaction 审批窗口
    ← 用户点击"同意"
    → 发消息给 Keeper
    ↓ chrome.runtime Port
keeper.ts
    → 用临时私钥签名
    → 返回 ZK Proof + 签名
    ↓ chrome.runtime Port
background.ts
    ↓ chrome.runtime.sendMessage
content.ts
    ↓ window.postMessage
injected.ts
    → 返回 SignedTransaction 给 dApp
```

---

## 4. Wallet Standard 实现（SuiWallet.ts）

EVE Vault 通过实现 `@mysten/wallet-standard` 的 `Wallet` 接口，让所有支持 Wallet Standard 的 dApp 自动发现它：

```typescript
// apps/extension/src/lib/adapters/SuiWallet.ts

export class EveVaultWallet implements Wallet {
    readonly #version = "1.0.0" as const;
    readonly #name = "Eve Vault" as const;

    // 支持的 Sui 网络链
    get chains(): Wallet["chains"] {
        return [SUI_TESTNET_CHAIN, SUI_DEVNET_CHAIN] as `sui:${string}`[];
    }

    // 实现的 Wallet Standard 功能
    get features() {
        return {
            [StandardConnect]: { connect: this.#connect },
            [StandardDisconnect]: { disconnect: this.#disconnect },
            [StandardEvents]: { on: this.#on },
            [SuiSignTransaction]: { signTransaction: this.#signTransaction },
            [SuiSignAndExecuteTransaction]: { signAndExecuteTransaction: this.#signAndExecuteTransaction },
            [SuiSignPersonalMessage]: { signPersonalMessage: this.#signPersonalMessage },
            // EVE Frontier 专有扩展特性
            [EVEFRONTIER_SPONSORED_TRANSACTION]: {
                signSponsoredTransaction: this.#signSponsoredTransaction,
            },
        };
    }
}
```

### 注册到页面（injected.ts）

```typescript
// apps/extension/entrypoints/injected.ts
import { registerWallet } from "@mysten/wallet-standard";
import { EveVaultWallet } from "../src/lib/adapters/SuiWallet";

// 在页面加载时立即注册
registerWallet(new EveVaultWallet());
```

dApp 通过 `@mysten/wallet-standard` 的 `getWallets()` 自动发现 `EveVaultWallet`，无需任何特殊集成。

---

## 5. Keeper：安全密钥容器

Keeper 是 EVE Vault 最独特的安全设计——临时私钥永远不离开 Keeper 进程的内存：

```typescript
// apps/extension/entrypoints/keeper/keeper.ts

// Keeper 处理的消息类型
switch (message.type) {
    case KeeperMessageTypes.CREATE_KEYPAIR:
        // 生成新的 Ed25519 临时密钥对
        // 私钥只在内存中，不写 chrome.storage
        break;

    case KeeperMessageTypes.EPH_SIGN:
        // 用临时私钥对字节签名
        // 只暴露签名结果，不暴露私钥
        break;

    case KeeperMessageTypes.CLEAR_EPHKEY:
        // 清除内存中的临时私钥（锁定操作）
        break;
}
```

**安全保证**：
- 临时私钥 = 内存变量，不序列化到 chrome.storage
- 浏览器关闭或 Keeper 崩溃 → 私钥自动销毁
- 重新解锁 → 重新生成新的临时密钥对
- Background/Popup 无法直接读取私钥，只能通过 Port 消息请求签名

---

## 6. 本地开发配置

### 安装依赖

```bash
# 推荐使用 Bun
bun install
```

### 配置 .env

```bash
# apps/extension/.env
VITE_FUSION_SERVER_URL="https://auth.evefrontier.com"
VITE_FUSIONAUTH_CLIENT_ID=your-fusionauth-client-id
VITE_FUSION_CLIENT_SECRET=your-fusionauth-client-secret
VITE_ENOKI_API_KEY=your-enoki-api-key
EXTENSION_ID="your-extension-public-key"
```

### 启动开发模式

```bash
# 只运行扩展（推荐）
bun run dev:extension

# 运行所有 apps（扩展 + web）
bun run dev
```

开发模式下，WXT 会在 `apps/extension/.output/chrome-mv3/` 生成扩展文件，并监听文件变化自动重建。

### 在 Chrome 中加载扩展

1. 打开 `chrome://extensions`
2. 开启右上角「开发者模式」
3. 点击「加载已解压的扩展程序」
4. 选择 `apps/extension/.output/chrome-mv3/`

每次文件变化后，Chrome 会自动检测并提示更新（无需手动重新加载）。

---

## 7. 构建生产版本

```bash
# 构建 Chrome 扩展
bun run build:extension
# 输出：apps/extension/.output/chrome-mv3.zip

# 构建所有 apps
bun run build

# 清除所有缓存（构建时间变慢时使用）
bun run clean
```

---

## 8. FusionAuth OAuth 配置

在 FusionAuth 控制台需要添加以下重定向 URI（格式固定）：

```
https://<extension-id>.chromiumapp.org/
```

Extension ID 是 Chrome 分配的扩展唯一标识符（可在 `chrome://extensions` 页面找到）。

**必要的 OAuth 范围（Scopes）**：
- `openid`（获取 JWT 格式的 token）
- `profile`（获取用户信息）
- `email`（用户邮箱）

---

## 9. Turborepo 构建缓存

项目使用 Turborepo 加速构建：

```bash
# turbo.json 定义了任务并行关系
# build:extension 依赖 shared 包的构建
bun run build:extension
# → 先 build packages/shared
# → 然后 build apps/extension（使用缓存）

# 强制重新构建（忽略缓存）
bun run build --force
```

---

## 10. E2E 测试

```bash
# tests/e2e/ 目录包含余额查询等端到端测试
bun run test:e2e

# 测试前需要钱包已登录并配置了测试账户
# tests/e2e/helpers/state.ts 提供状态管理工具
```

---

## 本章小结

| 组件 | 层级 | 功能 |
|------|-----|------|
| `injected.ts` | 页面进程 | 注册 EveVaultWallet 到 Wallet Standard |
| `content.ts` | 内容脚本 | 消息桥接：页面 ↔ Background |
| `background.ts` | Service Worker | OAuth、存储、请求协调 |
| `keeper.ts` | 隐藏容器 | 临时私钥的安全存储与使用 |
| `popup/` | Extension Page | 用户界面：登录、地址、余额 |
| `sign_*/` | Extension Pages | 交易/消息审批 UI |
| `SuiWallet.ts` | Adapter | Wallet Standard 完整实现 |

> 下一章：**EVE Vault 与 dApp 集成实战** —— 如何在 Builder 的 dApp 中接入 EVE Vault，支持账户发现、赞助交易和中断处理。
