# 第35章：EVE Vault 与 dApp 集成实战

> **学习目标**：掌握在 Builder dApp 中接入 EVE Vault 的完整流程——账户发现、连接、签名交易、赞助交易，以及处理 zkLogin 特有的 Epoch 刷新和断连情况。

---

> 状态：教学示例。正文 API 说明以当前依赖版本与本仓库示例 dApp 为准，实际接入时需以本地包版本核对。

## 最小调用链

`dApp Provider 初始化 -> useConnection 发现钱包 -> 构建 PTB -> EVE Vault 审批/签名 -> 链上执行 -> dApp 刷新对象状态`

## 钱包能力矩阵

| 能力 | 普通 Wallet Standard 钱包 | EVE Vault |
|------|------|------|
| 发现与连接 | 支持 | 支持 |
| 普通交易签名 | 支持 | 支持 |
| Sponsored Tx | 通常不支持 | 支持 |
| zkLogin / Epoch 处理 | 依赖钱包实现 | 内建处理 |
| 游戏内浮层联动 | 通常没有 | 可与 EVE Frontier 场景配合 |

这张表的作用不是做宣传，而是提醒你：接入层必须先探测钱包能力，再决定是否展示赞助交易入口。

这章真正该建立的意识是：

> 钱包接入不是“连上就行”，而是要按钱包能力差异设计完整交互降级路径。

也就是说，你的 dApp 不能假设所有钱包都等价。

## 异常处理顺序

当用户反馈“钱包能连上，但交易发不出去”时，建议按这个顺序排查：

1. 先确认当前钱包是否支持 Sponsored Tx
2. 再确认网络、package id、对象 ID 是否一致
3. 然后确认 zkLogin 证明是否过期、`maxEpoch` 是否需要刷新
4. 最后再看前端是否正确处理了断连和重连后的状态恢复

## 对应代码目录

- [builder-scaffold/dapps](https://github.com/evefrontier/builder-scaffold/tree/main/dapps)
- [book/src/code/example-17/dapp](./code/example-17/dapp)
- [evevault](https://github.com/evefrontier/evevault)

## 1. dApp 集成概述

因为 EVE Vault 实现了完整的 **Sui Wallet Standard**，任何使用 `@mysten/dapp-kit` 或 `@evefrontier/dapp-kit` 的 dApp 可以零配置地发现并连接 EVE Vault。

同时，EVE Vault 还实现了 EVE Frontier 专有的 **赞助交易扩展**，让 Builder 可以替玩家支付 Gas。

所以接入层通常至少要回答三件事：

- 当前有没有钱包
- 当前是不是 EVE Vault
- 当前操作需不需要 Sponsored Tx 能力

---

## 2. 安装依赖

```bash
# EVE Frontier 专用 SDK（推荐，包含 EVE Vault 赞助交易支持）
npm install @evefrontier/dapp-kit

# 或 Mysten 官方 SDK（基础 Wallet Standard，不含赞助交易）
npm install @mysten/dapp-kit
```

---

## 3. Provider 配置

```tsx
// src/main.tsx
import { EveFrontierProvider } from "@evefrontier/dapp-kit";
import { QueryClient } from "@tanstack/react-query";
import ReactDOM from "react-dom/client";

const queryClient = new QueryClient();

ReactDOM.createRoot(document.getElementById("root")!).render(
    <EveFrontierProvider queryClient={queryClient}>
        <App />
    </EveFrontierProvider>,
);
```

`EveFrontierProvider` 自动初始化：
- **QueryClientProvider**（React Query）
- **DAppKitProvider**（Sui 客户端 + Wallet）
- **VaultProvider**（EVE Vault 连接状态）
- **SmartObjectProvider**（游戏对象 GraphQL 查询）
- **NotificationProvider**（链上操作通知）

Provider 这里最关键的不是“包了多少层”，而是能力顺序。

你后面的连接、签名、对象查询和通知体验，都依赖这层初始化顺序正确。

---

## 4. 连接钱包

```tsx
import { useConnection, abbreviateAddress } from "@evefrontier/dapp-kit";
import { useCurrentAccount } from "@mysten/dapp-kit-react";

function ConnectButton() {
    const { handleConnect, handleDisconnect, isConnected, walletAddress, hasEveVault } = useConnection();
    const account = useCurrentAccount();

    if (!isConnected) {
        return (
            <div>
                <button onClick={handleConnect}>连接 EVE Vault</button>
                {!hasEveVault && (
                    <p style={{ color: "orange" }}>
                        请先安装 <a href="https://github.com/evefrontier/evevault/releases/latest/download/eve-vault-chrome.zip">EVE Vault 扩展</a>
                    </p>
                )}
            </div>
        );
    }

    return (
        <div>
            <span>已连接：{abbreviateAddress(account?.address ?? "")}</span>
            <button onClick={handleDisconnect}>断开</button>
        </div>
    );
}
```

### hasEveVault 的意义

`hasEveVault` 为 `true` 时表示 EVE Vault 扩展已安装且在钱包列表中被发现。这让你可以给未安装的用户提供下载链接引导。

连接流程里最容易忽视的问题，不是“按钮能不能点亮”，而是连上之后页面有没有立刻切到正确状态：

- 当前地址是否刷新
- 需要的对象查询是否重新拉取
- 依赖钱包能力的按钮是否切换显示

---

## 5. 发送交易（普通签名）

```tsx
import { useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";
import { useConnection } from "@evefrontier/dapp-kit";

function SendTxButton() {
    const { signAndExecuteTransaction } = useDAppKit();
    const { isConnected } = useConnection();

    const handleSend = async () => {
        const tx = new Transaction();

        // 调用 Builder 合约
        tx.moveCall({
            target: `${PACKAGE_ID}::tribe_permit::issue_jump_permit`,
            arguments: [
                tx.object(EXTENSION_CONFIG_ID),
                tx.object(SOURCE_GATE_ID),
                tx.object(DEST_GATE_ID),
                tx.object(CHARACTER_ID),
                tx.object("0x6"),  // Sui Clock（固定对象 ID）
            ],
        });

        try {
            const result = await signAndExecuteTransaction({ transaction: tx });
            console.log("交易成功，Digest:", result.digest);
        } catch (err) {
            // EVE Vault 审批弹窗被用户关闭
            if (err.message?.includes("User rejected")) {
                alert("交易被用户取消");
            }
        }
    };

    return <button onClick={handleSend} disabled={!isConnected}>颁发通行证</button>;
}
```

普通签名流程的关键不是代码能调用，而是用户能理解自己正在签什么。

所以交易按钮前最好就把：

- 目标对象
- 关键成本
- 预期结果

尽量讲清楚，而不是把一切都留给钱包审批页。

---

## 6. 赞助交易（Sponsored TX）——最重要的特性

EVE Vault 是唯一实现了 `sign_sponsored_transaction` 的 Sui 钱包。这意味着 Builder 的服务器可以替玩家支付 Gas，玩家不需要持有 SUI 才能使用 dApp。

```tsx
import { useSponsoredTransaction, WalletSponsoredTransactionNotSupportedError } from "@evefrontier/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";

function SponsoredTxButton() {
    const { sponsoredSignAndExecute } = useSponsoredTransaction();

    const handleSponsoredTx = async () => {
        const tx = new Transaction();
        tx.moveCall({
            target: `${PACKAGE_ID}::my_extension::some_action`,
            arguments: [/* ... */],
        });

        try {
            // 玩家签名，Gas 由 Builder 服务器赞助
            const result = await sponsoredSignAndExecute({ transaction: tx });
            console.log("赞助交易成功！", result.digest);
        } catch (err) {
            if (err instanceof WalletSponsoredTransactionNotSupportedError) {
                // 用户使用的不是 EVE Vault，降级到普通交易
                console.warn("当前钱包不支持赞助交易，请使用 EVE Vault");
                // 可以 fallback 到 signAndExecuteTransaction
            }
        }
    };

    return <button onClick={handleSponsoredTx}>免 Gas 操作（EVE Vault 赞助）</button>;
}
```

### Builder 服务器端的赞助配置

赞助交易需要 Builder 在服务器端配置一个 Gas 赞助者账户：

```typescript
// Builder 后端（Node.js）
import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";

const sponsorKeypair = Ed25519Keypair.fromSecretKey(SPONSOR_PRIVATE_KEY);

// 接收玩家的 PTB，添加 Gas 并签名返回
app.post("/sponsor-tx", async (req, res) => {
    const { serializedTx } = req.body;

    const tx = Transaction.from(serializedTx);

    // 设置 Gas 赞助者
    tx.setSender(playerAddress);
    tx.setGasOwner(sponsorKeypair.getPublicKey().toSuiAddress());

    const sponsorSignature = await tx.sign({ signer: sponsorKeypair, client });

    res.json({ sponsorSignature, serializedTx: tx.serialize() });
});
```

Sponsored Tx 的接入重点不是“省 Gas”，而是“前后端协同”。

它要求至少三层都配合正确：

- 前端能识别钱包能力
- 后端能正确补 Gas 和签名
- 钱包能完成对应审批流程

只要其中一层口径不一致，用户看到的就会是“能连上，但怎么都发不出去”。

---

## 7. 读取游戏对象（Smart Object）

```tsx
import { useSmartObject } from "@evefrontier/dapp-kit";

function GateStatus({ gateItemId }: { gateItemId: string }) {
    const { assembly, character, loading, error, refetch } = useSmartObject({
        itemId: gateItemId,
    });

    if (loading) return <div>加载中...</div>;
    if (error) return <div>错误: {error.message}</div>;
    if (!assembly) return <div>未找到 Gate</div>;

    return (
        <div>
            <h2>{assembly.name}</h2>
            <p>类型 ID: {assembly.typeId}</p>
            <p>状态: {assembly.state}</p>
            <p>所有者: {character?.name ?? "未知"}</p>
            <button onClick={refetch}>刷新</button>
        </div>
    );
}
```

---

## 8. zkLogin Epoch 刷新处理

zkLogin 的临时密钥对绑定到 Sui Epoch（约 24 小时）。当 Epoch 过期时，需要重新生成密钥和 ZK Proof：

```tsx
import { useConnection } from "@evefrontier/dapp-kit";
import { useDAppKit } from "@mysten/dapp-kit-react";

function TransactionButton() {
    const { isConnected, walletAddress } = useConnection();
    const { signAndExecuteTransaction } = useDAppKit();

    const handleTransaction = async () => {
        const tx = new Transaction();
        // ...构建交易...

        try {
            await signAndExecuteTransaction({ transaction: tx });
        } catch (err) {
            const errMsg = err?.message ?? "";

            if (errMsg.includes("ZK proof") || errMsg.includes("maxEpoch")) {
                // Epoch 已过期，ZK Proof 无效
                // EVE Vault 会自动弹出重新验证的引导
                alert("您的登录已过期，请在 EVE Vault 中刷新登录状态");
            } else if (errMsg.includes("User rejected")) {
                // 用户在审批页面取消了交易
                console.log("用户取消了操作");
            } else {
                console.error("交易失败:", errMsg);
            }
        }
    };

    return <button onClick={handleTransaction} disabled={!isConnected}>执行操作</button>;
}
```

---

## 9. 监听网络切换

EVE Vault 支持用户在 Devnet/Testnet 之间切换。dApp 需要响应这个变化：

```tsx
import { useCurrentAccount } from "@mysten/dapp-kit-react";
import { useEffect } from "react";

function NetworkAwareComponent() {
    const account = useCurrentAccount();

    useEffect(() => {
        if (!account) return;

        // account.chains 包含当前钱包支持的链
        const currentChain = account.chains[0]; // "sui:testnet" 或 "sui:devnet"
        console.log("当前网络:", currentChain);

        // 根据网络切换 API 端点或合约地址
    }, [account]);

    // ...
}
```

---

## 10. 消息签名（Personal Message）

```tsx
import { useDAppKit } from "@mysten/dapp-kit-react";
import { toBase64 } from "@mysten/sui/utils";

function SignMessageButton() {
    const { signPersonalMessage } = useDAppKit();

    const handleSign = async () => {
        const message = new TextEncoder().encode("EVE Frontier Builder Auth: " + Date.now());

        const { bytes, signature } = await signPersonalMessage({
            message,
        });

        console.log("消息签名:", signature);
        // 可将 signature 发给服务器验证用户身份（link game account to builder system）
    };

    return <button onClick={handleSign}>用 EVE Vault 签名验证身份</button>;
}
```

---

## 11. 完整示例：Gate Extension dApp

以下是一个将所有功能整合的最小完整示例：

```tsx
// src/App.tsx
import { useConnection, useSmartObject, abbreviateAddress } from "@evefrontier/dapp-kit";
import { useDAppKit } from "@mysten/dapp-kit-react";
import { useSponsoredTransaction } from "@evefrontier/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";

const GATE_ITEM_ID = import.meta.env.VITE_GATE_ITEM_ID;
const PACKAGE_ID = import.meta.env.VITE_BUILDER_PACKAGE_ID;
const EXTENSION_CONFIG_ID = import.meta.env.VITE_EXTENSION_CONFIG_ID;

export function App() {
    const { handleConnect, handleDisconnect, isConnected, hasEveVault } = useConnection();
    const { assembly, loading } = useSmartObject({ itemId: GATE_ITEM_ID });
    const { signAndExecuteTransaction } = useDAppKit();
    const { sponsoredSignAndExecute } = useSponsoredTransaction();

    const requestJumpPermit = async () => {
        const tx = new Transaction();
        tx.moveCall({
            target: `${PACKAGE_ID}::tribe_permit::issue_jump_permit`,
            arguments: [tx.object(EXTENSION_CONFIG_ID), /* ... */],
        });
        await signAndExecuteTransaction({ transaction: tx });
    };

    const requestFreeJump = async () => {
        // 赞助交易版本（Builder 付 Gas）
        const tx = new Transaction();
        tx.moveCall({ /* 同上 */ });
        await sponsoredSignAndExecute({ transaction: tx });
    };

    return (
        <div>
            {/* 顶栏 */}
            <header>
                <h1>Star Gate Manager</h1>
                <button onClick={isConnected ? handleDisconnect : handleConnect}>
                    {isConnected ? "断开钱包" : "连接 EVE Vault"}
                </button>
            </header>

            {/* Gate 状态卡片 */}
            {!loading && assembly && (
                <div>
                    <h2>{assembly.name}</h2>
                    <p>当前状态: {assembly.state}</p>
                </div>
            )}

            {/* 操作按钮 */}
            {isConnected && (
                <div>
                    <button onClick={requestJumpPermit}>申请通行证（自付 Gas）</button>
                    <button onClick={requestFreeJump}>免费申请（赞助交易）</button>
                </div>
            )}

            {/* EVE Vault 未安装提示 */}
            {!hasEveVault && (
                <div style={{ background: "#fff3cd", padding: 12, borderRadius: 8 }}>
                    ⚠️ 请安装{" "}
                    <a href="https://github.com/evefrontier/evevault/releases/latest/download/eve-vault-chrome.zip">
                        EVE Vault 扩展
                    </a>{" "}
                    以连接您的 EVE Frontier 账户
                </div>
            )}
        </div>
    );
}
```

---

## 12. 常见集成问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| `WalletSponsoredTransactionNotSupportedError` | 用户使用非 EVE Vault 钱包 | Catch 错误，降级为普通交易 |
| 审批弹窗不出现 | Chrome 拦截了弹窗 | 告知用户检查右上角的拦截提示 |
| `maxEpoch exceeded` | ZK Proof 过期 | 提示用户在 EVE Vault 弹窗中刷新 |
| `hasEveVault = false` | 扩展未安装或未激活 | 展示下载链接和安装指引 |
| 网络不匹配 | dApp 期望 testnet，钱包连 devnet | 监听 account.chains，提示用户切换网络 |

---

## 本章小结

| 功能 | API |
|------|-----|
| 检测钱包安装 | `useConnection().hasEveVault` |
| 连接/断开 | `handleConnect / handleDisconnect` |
| 普通交易 | `useDAppKit().signAndExecuteTransaction` |
| 赞助交易 | `useSponsoredTransaction().sponsoredSignAndExecute` |
| 消息签名 | `useDAppKit().signPersonalMessage` |
| 读取游戏对象 | `useSmartObject({ itemId })` |
| 监听网络切换 | `useCurrentAccount().chains` |

---

## 延伸阅读

- [EVE Vault GitHub](https://github.com/evefrontier/evevault)
- [Sui zkLogin 官方文档](https://docs.sui.io/concepts/cryptography/zklogin)
- [Enoki 文档](https://docs.enoki.mystenlabs.com/)
- [Sui Wallet Standard](https://docs.sui.io/standards/wallet-standard)
- [@evefrontier/dapp-kit SDK 文档](https://sui-docs.evefrontier.com/)

> 你现在掌握了 EVE Frontier Builder 课程的完整知识体系：从 Move 2024 基础到 World 合约深度解析，从 Builder Scaffold 工程实践到 EVE Vault 钱包集成。是时候在星际中留下你的印记了。
