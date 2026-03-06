# 第33章：EVE Vault 钱包概述——zkLogin 原理与设计

> **学习目标**：理解 EVE Vault 是什么，它为什么使用 zkLogin 而不是传统私钥，以及 zkLogin 的完整密码学工作原理。

---

> 状态：源码导读。密码学细节以 EVE Vault 当前实现和 Sui zkLogin 机制为准，正文偏重架构理解。

## 前置依赖

- 了解 OAuth、JWT、临时密钥对、Sui 地址派生
- 建议先读 [术语表](./glossary.md) 中 `zkLogin`、`Epoch`
- 需要能打开 [evevault](https://github.com/evefrontier/evevault) 仓库

## 源码位置

- [evevault/README.md](https://github.com/evefrontier/evevault/blob/main/README.md)
- [zkProof.ts](https://github.com/evefrontier/evevault/blob/main/packages/shared/src/wallet/zkProof.ts)
- [authConfig.ts](https://github.com/evefrontier/evevault/blob/main/packages/shared/src/auth/authConfig.ts)
- [useAuth.ts](https://github.com/evefrontier/evevault/blob/main/packages/shared/src/auth/hooks/useAuth.ts)
- [LoginScreen.tsx](https://github.com/evefrontier/evevault/blob/main/apps/web/src/features/auth/components/LoginScreen.tsx)
- [CallbackScreen.tsx](https://github.com/evefrontier/evevault/blob/main/apps/web/src/features/auth/components/CallbackScreen.tsx)

## 关键测试文件

- [authStore.logout.test.ts](https://github.com/evefrontier/evevault/blob/main/packages/shared/src/auth/stores/__tests__/authStore.logout.test.ts)

## 推荐阅读顺序

1. 先看 [evevault/README.md](https://github.com/evefrontier/evevault/blob/main/README.md)
2. 再读 `authConfig.ts`、`useAuth.ts`
3. 最后看 `zkProof.ts` 与登录/回调页面

## 最小调用链

`FusionAuth/OAuth 登录 -> 回调拿 code -> 交换 token -> 派生 zkLogin 地址 -> 保存登录态 -> 钱包可签名`

## 验证步骤

1. 打开 [evevault](https://github.com/evefrontier/evevault) 的 README 与 docs
2. 对照登录页面与回调页面追踪 code exchange 流程
3. 重点核对 proof、salt、maxEpoch 三个概念在实现里的位置

## 常见报错

- OAuth 回调地址与配置不一致
- proof 过期但前端仍使用旧登录态
- 把钱包地址派生逻辑和用户会话逻辑混在一起，难以定位问题

## 对应代码目录

- [evevault](https://github.com/evefrontier/evevault)

## 1. EVE Vault 是什么？

EVE Vault 是 EVE Frontier 的专属 **Chrome 浏览器扩展钱包**，基于以下技术栈构建：

| 层 | 技术 | 用途 |
|----|------|------|
| 扩展框架 | WXT + Chrome MV3 | 跨浏览器扩展构建 |
| UI 框架 | React + TanStack Router | 弹窗和审批页面 |
| 状态管理 | Zustand + Chrome Storage | 持久化用户状态 |
| 区块链 | Sui Wallet Standard | dApp 发现与交互协议 |
| 身份认证 | EVE Frontier FusionAuth (OAuth) | EVE 游戏账户登录 |
| 地址派生 | Sui zkLogin + Enoki | 从 OAuth 身份派生链上地址 |

**核心设计理念**：玩家无需管理私钥——用 EVE Frontier 的游戏账户登录，自动获得 Sui 区块链地址。

---

## 2. 为什么不用传统私钥？

普通 Sui 钱包的痛点：

```
❌ 玩家需要保管助记词（12-24个单词）
❌ 助记词泄露 = 资产全损
❌ 游戏账户与链上身份是两套独立系统
❌ 新用户的学习门槛极高
```

EVE Vault 的方案：

```
✅ 用 EVE Frontier 游戏账户（邮箱登录）直接对应链上地址
✅ 地址由零知识证明（zkLogin）确定性派生
✅ 即使 OAuth token 被盗，需要 ZK 证明才能签名
✅ 游戏账户 = 链上身份，用户体验无缝衔接
```

---

## 3. zkLogin 原理精讲

### 3.1 核心概念

zkLogin 是 Sui 原生支持的一种签名方案，它将 OAuth 身份与区块链地址绑定：

```
【传统钱包】
私钥 k → 公钥 PK → 地址 A
               签名 = ed25519_sign(k, tx)

【zkLogin 钱包】
JWT (OAuth token) + Ephemeral Key → ZK Proof → 签名
                                              ↑
                  这个证明证明了"我持有有效的 JWT 且 JWT 对应地址 A"
```

### 3.2 zkLogin 地址公式

```
zkLogin_address = hash(
    iss,          // JWT 颁发者（如 "https://auth.evefrontier.com"）
    sub,          // 用户的唯一 ID（EVE 账户 ID）
    aud,          // OAuth 客户端 ID
    user_salt,    // Enoki 保存的用户盐值（防止 sub 泄漏关联链上身份）
)
```

**关键安全性**：攻击者即使知道你的 EVE 账户 ID，没有 `user_salt` 就无法算出你的链上地址。`user_salt` 由 Enoki（Mysten Labs 的 zkLogin 服务）负责保管。

### 3.3 临时密钥对（Ephemeral Key Pair）

zkLogin 使用一个临时密钥对来执行实际签名：

```
登录流程：
1. 生成临时 ed25519 密钥对（有效期 = Sui Epoch，约 24h）
2. 将临时公钥的 nonce 嵌入 OAuth 请求
3. OAuth server 在 JWT 中返回含 nonce 的 token
4. 用临时私钥签名交易
5. 提交 ZK 证明 + 临时签名 → Sui 验证
```

临时私钥存储在 EVE Vault 的 **Keeper 安全容器**中（见第34章）。

### 3.4 ZK Proof 生成

```typescript
// packages/shared/src/wallet/zkProof.ts
interface ZkProofParams {
    jwtRandomness: string;      // 随机盐，防止 nonce 推算
    maxEpoch: string;           // 临时密钥的最大有效 Epoch
    ephemeralPublicKey: PublicKey; // 临时公钥（嵌入 JWT nonce）
    idToken: string;            // 从 FusionAuth 获取的 JWT
    enokiApiKey: string;        // Enoki 服务密钥
    network?: string;           // devnet | testnet | mainnet
}
```

ZK Proof 的生成步骤：
1. 收集上述参数
2. 调用 Sui ZK Prover 端点（Enoki 托管）
3. 返回包含 `proofPoints`、`issBase64Details`、`headerBase64` 的 ZK 证明

### 3.5 JWT Nonce 的构造

zkLogin 最关键的设计是把临时公钥"嵌入" JWT 中，这通过 `nonce` 字段实现：

```typescript
// nonce = poseidon_hash(ephemeral_public_key, max_epoch, randomness)
// 这一步在请求 OAuth 前完成
const nonce = generateNonce(ephemeralPublicKey, maxEpoch, randomness);

// OAuth URL 中传入 nonce
const authUrl = `${fusionAuthUrl}/oauth2/authorize?`
    + `client_id=${CLIENT_ID}`
    + `&response_type=code`
    + `&nonce=${nonce}`   // ← FusionAuth 会把这个 nonce 放进 JWT
    + `&scope=openid+profile+email`;
```

FusionAuth 在返回的 JWT（`id_token`）中包含：
```json
{
    "iss": "https://auth.evefrontier.com",
    "sub": "user-12345",          ← EVE 账户唯一 ID
    "aud": "your-client-id",
    "nonce": "H5SmVjkG...",       ← 含临时公钥信息
    "exp": 1712345678
}
```

Sui 的 ZK 验证器通过检查 `nonce` 中嵌入的临时公钥，确认签名确实来自该临时密钥对。

### 3.6 zkLogin 地址的 TypeScript 计算

```typescript
import { computeZkLoginAddress } from "@mysten/sui/zklogin";

// 从 Enoki API 获取 user_salt 和地址
const { address, salt } = await fetch("https://api.enoki.mystenlabs.com/v1/zklogin", {
    method: "POST",
    headers: { "Authorization": `Bearer ${ENOKI_API_KEY}` },
    body: JSON.stringify({ jwt: idToken }),
}).then(r => r.json());

// 验证：本地计算地址（与 Enoki 返回的地址相同）
const localAddress = computeZkLoginAddress({
    claimName: "sub",
    claimValue: decodedJwt.sub,    // EVE 账户 ID
    iss: decodedJwt.iss,
    aud: decodedJwt.aud,
    userSalt: BigInt(salt),
});

console.assert(address === localAddress);
```

---

## 4. EVE Vault 的认证流程

```
用户点击 "Sign in with EVE Vault"
    │
    ▼
生成临时 Ed25519 密钥对 + JWT Nonce
    │
    ▼
打开 FusionAuth OAuth 页面（chrome.identity API）
    │
    ▼
用户用 EVE Frontier 账户登录
    │
    ▼
FusionAuth 返回 JWT（包含 nonce）
    │
    ▼
调用 Enoki API → 获取 user_salt + zkLogin 地址
    │
    ▼
调用 ZK Prover → 生成 ZK Proof
    │
    ▼
Popup 显示 zkLogin 地址 + SUI 余额
    │
    ▼
dApp 调用 wallet.connect() → 获取地址 → 可以发交易
```

---

## 5. 多网络支持

EVE Vault 支持同时连接多个测试网，可随时切换：

```typescript
// packages/shared/src/types/wallet.ts
export class EveVaultWallet implements Wallet {
    #currentChain: SuiChain = SUI_TESTNET_CHAIN;

    get chains(): Wallet["chains"] {
        return [SUI_TESTNET_CHAIN, SUI_DEVNET_CHAIN] as `sui:${string}`[];
    }
    // ...
}
```

弹窗左下角的网络切换器让玩家在 Devnet（开发测试）和 Testnet（演示/Pre-launch）之间切换，切换后地址相同（因为派生公式不含网络参数），但查询的节点会切换。

---

## 6. EVE Vault vs 传统 Sui 钱包对比

| 特性 | Sui Wallet / OKX | EVE Vault |
|------|-----------------|-----------|
| 需要助记词 | ✅ 是 | ❌ 否 |
| 基于 OAuth 登录 | ❌ 否 | ✅ 是（EVE 账户） |
| 私钥存储位置 | 用户本地 | 无私钥（zkLogin） |
| 地址确定性 | 取决于私钥 | JWT + salt 确定性派生 |
| 签名方案 | ed25519 / secp256k1 | zkLogin（ZK Proof + 临时签名） |
| 赞助交易 | 部分支持 | ✅ EVE Frontier 原生支持 |
| dApp discover | Wallet Standard | Wallet Standard + EVE 扩展特性 |

---

## 7. 安全模型

### Keeper 机制

临时私钥不存储在 `chrome.storage`（可被 JS 读取），而是存在 **Keeper**（一个隔离的 hidden document）中：

```
┌─────────────────────────────────────────┐
│  Chrome Extension 沙箱                    │
│                                          │
│  Background Service Worker               │
│      ↕ chrome.runtime.sendMessage       │
│  Keeper (hidden iframe/document)         │
│      ← 临时私钥仅在此内存中              │
│      ← 不写入 chrome.storage             │
│      ← 关闭浏览器即清除                  │
└─────────────────────────────────────────┘
```

### 锁定机制

浏览器关闭或一段时间不操作后，Keeper 自动清除临时私钥（"锁定"状态）。重新解锁需要重新生成 ZK Proof（有缓存，通常几秒内完成）。

---

## 8. 对 Builder 的意义

作为 Builder，你的 dApp 用户将通过 EVE Vault 连接，以下是关键影响：

1. **无需私钥管理 UX**：用户直接用游戏账户连接，降低 onboarding 门槛
2. **赞助交易原生支持**：EVE Vault 实现了 `sign_sponsored_transaction`，Builder 可以替用户付 Gas
3. **地址稳定性**：玩家的链上地址与其 EVE 账户绑定，不会因"换设备"而改变
4. **多网络**：开发时用 Devnet，上线用 Testnet，地址不变

---

## 本章小结

| 概念 | 要点 |
|------|------|
| zkLogin | 无私钥的零知识签名方案，基于 OAuth JWT |
| `user_salt` | Enoki 保管，防止 OAuth ID 与链上地址关联 |
| 临时密钥对 | 每次 Epoch 重新生成，Keeper 安全容器存储 |
| ZK Proof | 向 Enoki 请求，证明"合法 JWT 持有者" |
| FusionAuth | EVE Frontier 的 OAuth 身份提供商 |

> 下一章：**EVE Vault 技术架构与开发部署** —— Chrome MV3 的 5 个脚本层、消息通信协议、以及如何在本地构建和加载扩展。
