# 第7章：Builder Scaffold 完整使用指南（二）——TS 脚本与 dApp 开发

> **学习目标**：掌握 `ts-scripts/` 中 6 个交互脚本的用法与原理，理解 `helper.ts` 工具链，并学会在 `dapps/` React 模板的基础上构建属于自己的 EVE Frontier dApp。

---

> 状态：已映射脚本与 dApp 目录。正文以本仓库内 `builder-scaffold` 的脚本布局为准。

## 最小调用链

`读取 .env -> helper.ts 初始化客户端/对象 ID -> TS 脚本发起 PTB -> 链上对象变化 -> dApp 查询并展示新状态`

## 目录职责边界

把 `builder-scaffold` 用顺，关键不是记住每个脚本名，而是先分清三层职责：

| 目录/文件 | 责任 | 不应该承担的事 |
|------|------|------|
| `ts-scripts/smart_gate/*` | 组织单个业务动作，拼装 PTB | 塞大量共享工具函数 |
| `ts-scripts/utils/helper.ts` | 初始化客户端、读取环境、封装公共查询 | 写具体业务规则 |
| `dapps/src/*` | 展示状态、发起交互、承接钱包连接 | 直接硬编码环境和对象 ID |

## 一条完整脚本链路应该长什么样

```text
.env
  -> helper.ts 读取网络 / package id / key
  -> 业务脚本拼装 PTB
  -> 提交链上交易
  -> dApp 或查询脚本刷新对象状态
```

如果一个脚本同时负责“读配置 + 查对象 + 拼复杂业务规则 + 打印 UI 文案”，基本就该拆了。

脚本体系真正要解决的，不是“把命令行自动化”这么简单，而是把工程动作拆成清晰职责：

- 配置来自哪里
- 公共查询由谁负责
- 单个业务动作由谁组织
- 前端和脚本怎样共享同一套对象理解

## 两个常见反模式

- `helper.ts` 越写越大，最后变成难以维护的“上帝文件”
- 前端直接复制脚本里的对象 ID 和网络配置，导致脚本与页面长期漂移

## 对应代码目录

- [builder-scaffold/ts-scripts](https://github.com/evefrontier/builder-scaffold/tree/main/ts-scripts)
- [builder-scaffold/dapps](https://github.com/evefrontier/builder-scaffold/tree/main/dapps)

## 1. TypeScript 脚本的使用前提

在运行任何脚本之前，需要完成以下准备：

```
前置条件：
1. ✅ world-contracts 已发布（本地或测试网）
2. ✅ smart_gate 合约已发布（执行 sui client publish）
3. ✅ .env 文件已填写所有必要的环境变量
4. ✅ test-resources.json + extracted-object-ids.json 存在于项目根目录
```

### 配置 .env 文件

```bash
cp .env.example .env
```

关键环境变量：

```dotenv
# 网络选择
NETWORK=localnet        # localnet | testnet | mainnet

# 管理员私钥（导出的 Sui 密钥，0x 开头的 Bech32 格式）
ADMIN_EXPORTED_KEY=suiprivkey1...

# 合约地址
WORLD_PACKAGE_ID=0xabc...    # world-contracts 发布后的 Package ID
BUILDER_PACKAGE_ID=0xdef...  # smart_gate 发布后的 Package ID

# 租户名称（游戏世界的命名空间）
TENANT=evefrontier
```

### `.env` 的本质不是配置表，而是工程边界

只要某个值会因为环境不同而变化，它就不该被散落在脚本正文里。

最常见会漂移的值包括：

- 网络
- 包 ID
- 管理员密钥
- 租户名
- 关键对象 ID

一旦这些东西被脚本、前端、测试各写一份，后面排查会非常痛苦。

---

## 2. 6 个脚本的执行顺序与功能

### 完整执行流程

```
① pnpm configure-rules       → 设置 Gate 的扩展规则（tribe ID、悬赏物品 type_id）
② pnpm authorise-gate        → 将扩展注册到 Gate 对象
③ pnpm authorise-storage-unit → 将扩展注册到 StorageUnit
④ pnpm issue-tribe-jump-permit → 为符合部族条件的角色颁发通行证
⑤ pnpm jump-with-permit      → 持有通行证跳跃
⑥ pnpm collect-corpse-bounty → 提交尸体物品 → 获得通行证（悬赏流程）
```

---

## 3. 精读：configure-rules.ts

这是最常修改的脚本，负责初始化两种规则：

```typescript
// ts-scripts/smart_gate/configure-rules.ts
import { Transaction } from "@mysten/sui/transactions";
import { getEnvConfig, initializeContext, hydrateWorldConfig } from "../utils/helper";
import { resolveSmartGateExtensionIds } from "./extension-ids";

async function main() {
    // 1. 读取 .env 配置
    const env = getEnvConfig();

    // 2. 初始化 Sui 客户端 + 密钥对
    const ctx = initializeContext(env.network, env.adminExportedKey);
    const { client, keypair, address } = ctx;

    // 3. 从链上读取 world-contracts 的配置
    await hydrateWorldConfig(ctx);

    // 4. 从链上查询 AdminCap、ExtensionConfig 的对象 ID
    const { builderPackageId, adminCapId, extensionConfigId } =
        await resolveSmartGateExtensionIds(client, address);

    const tx = new Transaction();

    // 5. 设置部族规则（tribe=100, 有效期=1小时）
    tx.moveCall({
        target: `${builderPackageId}::tribe_permit::set_tribe_config`,
        arguments: [
            tx.object(extensionConfigId),
            tx.object(adminCapId),
            tx.pure.u32(100),           // 允许的部族 ID
            tx.pure.u64(3600000),       // 有效期：1 小时（毫秒）
        ],
    });

    // 6. 设置悬赏规则（物品 type_id=ITEM_A_TYPE_ID, 有效期=1小时）
    tx.moveCall({
        target: `${builderPackageId}::corpse_gate_bounty::set_bounty_config`,
        arguments: [
            tx.object(extensionConfigId),
            tx.object(adminCapId),
            tx.pure.u64(ITEM_A_TYPE_ID),  // 尸体物品的 type_id
            tx.pure.u64(3600000),
        ],
    });

    // 7. 提交交易
    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEffects: true, showObjectChanges: true },
    });

    console.log("Transaction digest:", result.digest);
}
```

### 这类脚本最值得保留的结构是什么？

就是这条清晰链路：

1. 读环境
2. 初始化上下文
3. 解析链上关键对象
4. 组装 PTB
5. 提交并记录 digest

只要你以后新增脚本也保持这个骨架，工程会稳定很多。

### 修改规则参数

常见修改点：

```typescript
// 改为允许部族 ID = 3（对应你游戏世界的部族配置）
tx.pure.u32(3),

// 改为 24 小时有效期
tx.pure.u64(24 * 60 * 60 * 1000),

// ITEM_A_TYPE_ID 在 utils/constants.ts 中定义，根据实际物品调整
```

---

## 4. 工具函数解析：`utils/helper.ts`

这是所有脚本的共享基础组件：

```typescript
import { getEnvConfig, initializeContext, hydrateWorldConfig } from "../utils/helper";

// getEnvConfig()：读取 .env 并验证必要字段
const env = getEnvConfig();
// → { network, rpcUrl, packageId, adminExportedKey, tenant }

// initializeContext()：创建 Sui RPC 客户端和 Ed25519 密钥对
const ctx = initializeContext(env.network, env.adminExportedKey);
// → { client, keypair, address, config, network }

// hydrateWorldConfig()：从链上读取 world 配置（ObjectRegistry、AdminACL 等对象 ID）
await hydrateWorldConfig(ctx);
// 之后可通过 ctx.config 访问所有 world 对象 ID
```

### 关键工具

```
utils/
├── helper.ts           # 环境配置、上下文初始化、world 配置读取
├── config.ts           # Network 类型、WorldConfig 接口、RPC URL 映射
├── constants.ts        # TENANT、ITEM_A_TYPE_ID 等常量
├── derive-object-id.ts # 从 game item_id 推导 Sui 对象 ID（deterministic）
└── proof.ts            # 生成 LocationProof（用于位置验证测试）
```

### `helper.ts` 为什么既重要又危险？

因为它天然会变成所有脚本都依赖的中心文件。

重要在于：

- 它统一了网络、客户端、配置读取
- 它降低了重复代码

危险在于：

- 它很容易无限膨胀
- 最后把一堆业务判断也吸进去

所以更稳的原则是：`helper.ts` 只做“公共基础设施”，不要做“具体业务策略”。

---

## 5. resolve-extension-ids.ts：自动查询对象 ID

```typescript
// 不需要手动查询对象 ID！脚本会自动从链上查找 AdminCap 和 ExtensionConfig
export async function resolveSmartGateExtensionIds(client, ownerAddress) {
    // 查找属于 ownerAddress 的 AdminCap 对象
    const adminCapId = await findObjectByType(
        client,
        ownerAddress,
        `${builderPackageId}::config::AdminCap`,
    );

    // 查找共享的 ExtensionConfig 对象
    const extensionConfigId = await findSharedObjectByType(
        client,
        `${builderPackageId}::config::ExtensionConfig`,
    );

    return { builderPackageId, adminCapId, extensionConfigId };
}
```

---

## 6. 为自定义合约添加脚本

以第6章的 `toll_gate` 为例，添加一个 `configure-toll.ts`：

```typescript
// ts-scripts/smart_gate/configure-toll.ts
import "dotenv/config";
import { Transaction } from "@mysten/sui/transactions";
import { getEnvConfig, initializeContext, hydrateWorldConfig } from "../utils/helper";
import { resolveSmartGateExtensionIds } from "./extension-ids";

async function main() {
    const env = getEnvConfig();
    const ctx = initializeContext(env.network, env.adminExportedKey);
    await hydrateWorldConfig(ctx);
    const { client, keypair } = ctx;

    const { builderPackageId, adminCapId, extensionConfigId } =
        await resolveSmartGateExtensionIds(client, ctx.address);

    const tx = new Transaction();

    tx.moveCall({
        target: `${builderPackageId}::toll_gate::set_toll_config`,
        arguments: [
            tx.object(extensionConfigId),
            tx.object(adminCapId),
            tx.pure.u64(1_000_000_000),   // 通行费：1 SUI = 10^9 MIST
            tx.pure.u64(3600000),          // 有效期 1 小时
        ],
    });

    const result = await client.signAndExecuteTransaction({
        transaction: tx,
        signer: keypair,
        options: { showEffects: true },
    });

    console.log("Toll config set! Digest:", result.digest);
}

main();
```

然后在 `package.json` 中添加：

```json
"scripts": {
    "configure-toll": "tsx ts-scripts/smart_gate/configure-toll.ts"
}
```

---

## 7. dApp 模板：快速上手

```bash
cd dapps
pnpm install
cp .envsample .env       # 填写 VITE_ITEM_ID 等变量
pnpm dev                 # 启动开发服务器：http://localhost:5173
```

### 技术栈

| 库 | 版本 | 用途 |
|----|------|------|
| React + TypeScript | 18 | UI 框架 |
| Vite | 5 | 构建工具 |
| Radix UI | 1 | UI 组件库 |
| `@evefrontier/dapp-kit` | latest | EVE Frontier 专用 SDK |
| `@mysten/dapp-kit-react` | latest | Sui 钱包连接 |

### Provider 架构（main.tsx）

```tsx
// src/main.tsx
ReactDOM.createRoot(document.getElementById("root")!).render(
    <EveFrontierProvider queryClient={queryClient}>
        {/* 一个 Provider 组合了所有必要的 Context */}
        {/* QueryClientProvider → DAppKitProvider → VaultProvider → SmartObjectProvider → NotificationProvider */}
        <App />
    </EveFrontierProvider>,
);
```

---

## 8. 核心 Hooks 速查

### 钱包连接（App.tsx）

```tsx
import { abbreviateAddress, useConnection } from "@evefrontier/dapp-kit";
import { useCurrentAccount } from "@mysten/dapp-kit-react";

// 连接/断开钱包
const { handleConnect, handleDisconnect, isConnected, walletAddress } = useConnection();

// 读取当前账户
const account = useCurrentAccount();

// 显示缩短的地址（如 0x1234...5678）
<span>{abbreviateAddress(account?.address ?? "")}</span>
```

### 读取 Smart Object（Assembly Data）

```tsx
import { useSmartObject } from "@evefrontier/dapp-kit";

// 传入游戏内的 item_id（从 URL 参数或 env 读取）
const { assembly, character, loading, error, refetch } = useSmartObject({
    itemId: VITE_ITEM_ID,
});

// assembly 包含：name, typeId, state, id, owner character
// character 包含：持有者角色信息
```

### 执行交易（WalletStatus.tsx）

```tsx
import { useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

const { signAndExecuteTransaction } = useDAppKit();

async function callMyContract() {
    const tx = new Transaction();
    tx.moveCall({
        target: `${PACKAGE_ID}::tribe_permit::issue_jump_permit`,
        arguments: [/* ... */],
    });

    const result = await signAndExecuteTransaction({ transaction: tx });
    await refetch();  // 刷新 assembly 状态
}
```

---

## 9. 实战：在 dApp 中颁发部族通行证

```tsx
// src/components/IssuePermit.tsx
import { useSmartObject, useConnection } from "@evefrontier/dapp-kit";
import { useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

export function IssuePermit({ gateItemId }: { gateItemId: string }) {
    const { assembly } = useSmartObject({ itemId: gateItemId });
    const { isConnected } = useConnection();
    const { signAndExecuteTransaction } = useDAppKit();

    const handleIssuePermit = async () => {
        const tx = new Transaction();
        tx.moveCall({
            target: `${import.meta.env.VITE_BUILDER_PACKAGE_ID}::tribe_permit::issue_jump_permit`,
            arguments: [
                tx.object(import.meta.env.VITE_EXTENSION_CONFIG_ID),
                tx.object(SOURCE_GATE_ID),
                tx.object(DEST_GATE_ID),
                tx.object(CHARACTER_ID),
                tx.object("0x6"),  // Clock 对象（Sui 系统对象固定 ID）
            ],
        });

        const result = await signAndExecuteTransaction({ transaction: tx });
        console.log("JumpPermit 已颁发！", result.digest);
    };

    return (
        <button
            onClick={handleIssuePermit}
            disabled={!isConnected || !assembly}
        >
            {assembly ? `申请通过 ${assembly.name}` : "加载中..."}
        </button>
    );
}
```

---

## 10. 赞助交易（Sponsored TX）

对于想要隐藏 gas 费用的 Builder，dapp-kit 支持赞助交易：

```tsx
import { useSponsoredTransaction } from "@evefrontier/dapp-kit";

const { sponsoredSignAndExecute } = useSponsoredTransaction();

// 玩家不需要支付 gas——Builder 的服务器替他们支付
await sponsoredSignAndExecute({ transaction: tx });

// 注意：只有 EVE Vault 钱包支持此功能
// 如果用户使用其他钱包，需要 catch WalletSponsoredTransactionNotSupportedError
```

---

## 11. GraphQL 数据查询（高级）

当 `useSmartObject` 不够用时，可以直接用 GraphQL：

```tsx
import { executeGraphQLQuery, getAssemblyWithOwner } from "@evefrontier/dapp-kit";

// 查询 Gate 的完整数据（含所有者角色）
const gateData = await getAssemblyWithOwner({ itemId: gateItemId });

// 执行自定义 GraphQL 查询
const result = await executeGraphQLQuery(`
    query GetMyGates($owner: SuiAddress!) {
        objects(filter: { type: "${PACKAGE_ID}::smart_gate::Gate", owner: $owner }) {
            nodes {
                address
                contents { json }
            }
        }
    }
`, { owner: address });
```

---

## 12. 项目完整搭建流程总结

```
1. 克隆 builder-scaffold
2. 克隆 world-contracts（docker 用户：在宿主机，容器内自动可见）
3. 选择流程：Docker 或 Host
4. 启动本地链（docker compose run 或 sui start）
5. 发布 world-contracts（参考 docs/builder-flow-docker.md）
6. 编译 smart_gate：sui move build -e testnet
7. 发布 smart_gate：sui client test-publish --pubfile-path ...
8. 填写 .env 文件（BUILDER_PACKAGE_ID + WORLD_PACKAGE_ID + ADMIN_KEY）
9. 运行 pnpm configure-rules → pnpm authorise-gate → pnpm issue-tribe-jump-permit
10. 启动 dApp：cd dapps && pnpm dev
```

---

## 本章小结

| 组件 | 用途 |
|------|------|
| `configure-rules` | 设置 tribe + bounty 配置规则 |
| `authorise-gate` | 将 XAuth 注册到目标 Gate |
| `issue-tribe-jump-permit` | 为符合条件的玩家颁发 JumpPermit |
| `utils/helper.ts` | 环境变量、Sui 客户端、world 配置初始化 |
| `EveFrontierProvider` | 统一包装所有 React Context |
| `useSmartObject` | 读取链上 Assembly 数据的核心 Hook |
| `useSponsoredTransaction` | 为玩家代付 Gas 的赞助交易 |

> 这两章涵盖了 Builder Scaffold 从本地搭建到合约部署、脚本交互、前端开发的完整链路。结合之前的 World 合约章节，你现在具备了独立构建端到端 EVE Frontier Builder 应用的全部知识。
