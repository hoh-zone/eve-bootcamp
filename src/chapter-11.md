# Chapter 11：赞助交易与服务端集成

> **目标：** 深入理解 EVE Frontier 的赞助交易机制，掌握如何构建后端服务来验证业务逻辑并代玩家支付 Gas，实现无摩擦的游戏体验。

---

> 状态：工程章节。正文以赞助交易、服务端校验和链上链下协同为主。

## 11.1 什么是赞助交易？

在普通的 Sui 交易中，**发起者**（Sender）和 **Gas 付款人**（Gas Owner）是同一个人。赞助交易允许这两个角色分离：

```
普通交易：  玩家签名 + 玩家付 Gas
赞助交易：  玩家签名意图 + 服务器验证 + 服务器付 Gas
```

**对 EVE Frontier 至关重要**，因为：
- 某些操作需要**游戏服务器验证**（如临近性证明、距离检查）
- 降低玩家的**入门门槛**（不需要提前充值 SUI 做 Gas）
- 实现**业务级别的风控**：服务器可以拒绝非法请求

这里真正的关键不是“谁替谁付 Gas”这么简单，而是：

> 赞助交易把一次玩家操作拆成了“用户意图 + 服务端审核 + 链上执行”三段。

这让很多原本很难做的产品体验成为可能：

- 玩家不需要先准备 SUI
- 服务端可以在上链前做业务判断
- 风险控制可以发生在签名前，而不是等资产出事后再补救

但代价也很明确：你的系统不再只是前端 + 合约，而是正式进入“链上链下协同系统”。

---

## 11.2 AdminACL：游戏服务器的权限对象

EVE Frontier 通过 `AdminACL` 共享对象来管理哪些服务器地址被授权作为赞助者：

```
GovernorCap
    └──（管理）AdminACL（共享对象）
                └── sponsors: vector<address>
                    ├── 游戏服务器1地址
                    ├── 游戏服务器2地址
                    └── ...
```

需要服务器参与的操作（如跳跃）在合约中有类似这样的检查：

```move
public fun verify_sponsor(admin_acl: &AdminACL, ctx: &TxContext) {
    // tx_context::sponsor() 返回 Gas 付款人的地址
    let sponsor = ctx.sponsor().unwrap(); // 如果没有 sponsor 则 abort
    assert!(
        vector::contains(&admin_acl.sponsors, &sponsor),
        EUnauthorizedSponsor,
    );
}
```

这意味着：即使玩家自己构造了一个合法的交易，如果没有授权服务器签名，调用 `jump_with_permit` 等函数也会 abort。

### `AdminACL` 真正表达的是什么？

它表达的不是“这个服务器技术上能签名”，而是：

> 这个服务器被世界规则正式信任，可以为某类敏感动作背书。

这和普通后端服务有本质区别。很多 Web 应用里，后端只是帮你做业务判断；在这里，后端本身还是链上权限模型的一部分。

所以一旦 `AdminACL` 管理混乱，影响的不是单个接口，而是整条可信链：

- 谁能代付
- 谁能为临近性证明背书
- 谁能发起某些受限动作

---

## 11.3 赞助交易的完整流程

```
   玩家                    你的后端服务                   Sui 网络
    │                          │                            │
    │── 1. 构建 Transaction ──►│                            │
    │   (setSender = 玩家地址)  │                            │
    │                          │                            │
    │◄── 2. 后端验证业务逻辑 ───│                            │
    │   (检查临近性、余额等)    │                            │
    │                          │                            │
    │── 3. 玩家签名 (Sender) ──►│                            │
    │                          │                            │
    │                          │── 4. 服务器签名 (Gas) ─────►│
    │                          │   (setGasOwner = 服务器)   │
    │                          │                            │
    │◄─────────────────────────┼── 5. 交易执行结果 ─────────│
```

### 这条链路里每一段分别在防什么？

- **玩家构建交易**
  防止服务端替用户随意捏造意图
- **后端验证业务逻辑**
  防止不满足条件的请求直接上链
- **玩家签名**
  证明这确实是用户授权的动作
- **服务器签名**
  证明平台愿意为这笔动作代付并背书

四段缺一不可。只要少一段，就会出现典型问题：

- 没有玩家签名：变成平台可代用户乱发
- 没有后端校验：变成谁都能白嫖赞助
- 没有服务器签名：链上受限入口直接失败

---

## 11.4 构建简单的后端赞助服务

### 项目结构

```
backend/
├── src/
│   ├── server.ts          # Express 服务器
│   ├── sponsor.ts          # 赞助交易逻辑
│   ├── validators.ts       # 业务验证
│   └── config.ts           # 配置
└── package.json
```

### `sponsor.ts`：核心赞助逻辑

```typescript
// src/sponsor.ts
import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import { fromBase64 } from "@mysten/sui/utils";

const client = new SuiClient({
  url: process.env.SUI_RPC_URL ?? "https://fullnode.testnet.sui.io:443",
});

// 服务器签名密钥（安全存储在环境变量中）
const serverKeypair = Ed25519Keypair.fromSecretKey(
  fromBase64(process.env.SERVER_PRIVATE_KEY!)
);

export interface SponsoredTxRequest {
  txBytes: string;         // 玩家构建的交易（base64）
  playerSignature: string; // 玩家对 txBytes 的签名（base64）
  playerAddress: string;
}

export async function sponsorAndExecute(req: SponsoredTxRequest) {
  // 1. 反序列化玩家的交易
  const txBytes = fromBase64(req.txBytes);

  // 2. 服务器设置 Gas 付款人
  //    这会修改交易，使服务器地址成为 Gas 付款人
  const tx = Transaction.from(txBytes);
  tx.setGasOwner(serverKeypair.getPublicKey().toSuiAddress());

  // 3. 服务器签名（作为 Gas 付款人）
  const sponsoredBytes = await tx.build({ client });
  const serverSig = await serverKeypair.signTransaction(sponsoredBytes);

  // 4. 执行：同时提交玩家签名和服务器签名
  const result = await client.executeTransactionBlock({
    transactionBlock: sponsoredBytes,
    signature: [
      req.playerSignature,  // 玩家作为 Sender 的签名
      serverSig.signature,  // 服务器作为 Gas Owner 的签名
    ],
    options: { showEvents: true, showEffects: true },
  });

  return result;
}
```

### 服务端在这里最需要防的，不是“请求失败”，而是“请求被滥用”

一个真正可用的赞助服务，至少要考虑这些风控点：

- 同一玩家短时间内重复请求
- 同一交易被重复提交
- 某类高成本操作被批量刷
- 玩家把本不该赞助的交易偷偷塞给服务端

所以在真实项目里，赞助服务通常还会增加：

- 请求频率限制
- 交易白名单或入口白名单
- 每个动作的预算限制
- 请求日志和审计记录

### `validators.ts`：业务验证逻辑

```typescript
// src/validators.ts
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: process.env.SUI_RPC_URL! });

// 验证临近性（简化版：检查两个组件的游戏坐标是否足够近）
export async function validateProximity(
  playerAddress: string,
  assemblyId: string,
): Promise<boolean> {
  // 在真实场景中，这里会查询游戏服务器或链上的位置哈希
  // 此处仅做示例性实现
  try {
    const assembly = await client.getObject({
      id: assemblyId,
      options: { showContent: true },
    });

    // 检查玩家是否在组件附近（游戏物理规则验证）
    // 真实实现需要与游戏服务器通信
    return true; // 简化
  } catch {
    return false;
  }
}

// 验证玩家是否满足条件（如持有特定 NFT）
export async function validatePlayerCondition(
  playerAddress: string,
  requiredNftType: string,
): Promise<boolean> {
  const objects = await client.getOwnedObjects({
    owner: playerAddress,
    filter: { StructType: requiredNftType },
  });

  return objects.data.length > 0;
}
```

### 校验逻辑为什么不要和执行逻辑混在一起？

因为这两件事变化速度不同：

- 校验规则会频繁迭代
- 执行链路需要尽量稳定

把它们拆开后，你会得到几个直接好处：

- 风控规则更容易单独更新
- 更容易给不同 action 组合不同验证器
- 更容易做灰度和回放分析

### `server.ts`：REST API 服务器

```typescript
// src/server.ts
import express from "express";
import { sponsorAndExecute, SponsoredTxRequest } from "./sponsor";
import { validateProximity, validatePlayerCondition } from "./validators";

const app = express();
app.use(express.json());

// 赞助跳跃请求
app.post("/api/sponsor/jump", async (req, res) => {
  const { txBytes, playerSignature, playerAddress, gateId } = req.body;

  try {
    // 1. 验证临近性（玩家必须在星门附近）
    const isNear = await validateProximity(playerAddress, gateId);
    if (!isNear) {
      return res.status(400).json({ error: "玩家不在星门附近" });
    }

    // 2. 执行赞助交易
    const result = await sponsorAndExecute({
      txBytes,
      playerSignature,
      playerAddress,
    });

    res.json({ success: true, digest: result.digest });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// 赞助通用操作（带自定义验证）
app.post("/api/sponsor/action", async (req, res) => {
  const { txBytes, playerSignature, playerAddress, actionType, metadata } = req.body;

  try {
    // 根据 actionType 做不同验证
    switch (actionType) {
      case "deposit_ore": {
        // 验证是否在存储箱附近
        const ok = await validateProximity(playerAddress, metadata.ssuId);
        if (!ok) return res.status(400).json({ error: "不在附近" });
        break;
      }
      case "special_gate": {
        // 验证是否持有 VIP NFT
        const hasNft = await validatePlayerCondition(
          playerAddress,
          `${process.env.MY_PACKAGE}::vip_pass::VipPass`
        );
        if (!hasNft) return res.status(403).json({ error: "需要 VIP 通行证" });
        break;
      }
    }

    const result = await sponsorAndExecute({ txBytes, playerSignature, playerAddress });
    res.json({ success: true, digest: result.digest });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3001, () => console.log("赞助服务运行在 :3001"));
```

### 幂等性是赞助服务最容易被忽略的问题

玩家网络抖动、前端重试、用户狂点按钮，都会导致同一个请求被发多次。

如果你的后端没有幂等设计，就会出现：

- 同一业务请求被重复赞助
- 用户以为点了一次，链上却发了两次
- 预算和统计全部失真

实际项目里，至少应该给每次业务动作一个稳定请求 ID，并在服务端记录“这个请求是否已经处理过”。

---

## 11.5 前端配合赞助交易

```tsx
// src/hooks/useSponsoredAction.ts
import { useWallet } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";
import { toBase64 } from "@mysten/sui/utils";

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL ?? "http://localhost:3001";

export function useSponsoredAction() {
  const wallet = useWallet();

  const executeSponsoredJump = async (
    tx: Transaction,
    gateId: string,
  ) => {
    if (!wallet.currentAccount) throw new Error("请先连接钱包");

    const playerAddress = wallet.currentAccount.address;

    // 1. 玩家只签名，不提交
    const txBytes = await tx.build({ client: suiClient });
    const { signature: playerSig } = await wallet.signTransaction({
      transaction: tx,
    });

    // 2. 发送到后端，让服务器验证并代付 Gas
    const response = await fetch(`${BACKEND_URL}/api/sponsor/jump`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        txBytes: toBase64(txBytes),
        playerSignature: playerSig,
        playerAddress,
        gateId,
      }),
    });

    if (!response.ok) {
      const { error } = await response.json();
      throw new Error(error);
    }

    return response.json();
  };

  return { executeSponsoredJump };
}
```

---

## 11.6 赞助交易的安全考量

| 风险 | 防御措施 |
|------|--------|
| 服务器私钥泄露 | 使用 HSM 或 KMS 存储私钥；定期轮换 |
| 恶意玩家重放交易 | Sui 的 TransactionDigest 是唯一的，无法重放 |
| DDoS 攻击后端 | Rate limiting + IP 封锁 + 要求玩家 auth |
| 绕过验证直接提交 | 链上合约的 `verify_sponsor` 强制要求授权地址 |
| Gas 费耗尽 | 监控服务器账户余额，设置告警阈值 |

---

## 11.7 `@evefrontier/dapp-kit` 内置赞助支持

官方 SDK 已内置对赞助交易的支持：

```typescript
import { signAndExecuteSponsoredTransaction } from "@evefrontier/dapp-kit";

// SDK 会自动与 EVE Frontier 后端通信完成赞助
const result = await signAndExecuteSponsoredTransaction({
  transaction: tx,
  // 无需手动处理签名和后端通信
});
```

**适用场景**：官方游戏操作（如组件上/下线、仓库转移）通常可以用官方赞助服务。

**需要自建后端**：当你的扩展合约需要自定义业务验证时（如检查 NFT 持有、游戏内条件），需要部署自己的赞助服务。

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 赞助交易本质 | Sender（玩家）与 Gas Owner（服务器）分离 |
| AdminACL | 游戏合约验证 `ctx.sponsor()` 必须在授权列表 |
| 后端服务职责 | 业务验证 + 服务器签名 + 合并签名提交 |
| 安全要点 | 私钥保护 + Rate Limiting + 合约层兜底 |
| SDK 支持 | `signAndExecuteSponsoredTransaction()` 处理官方场景 |

## 📚 延伸阅读

- [Interfacing with the World](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [Sui 赞助交易文档](https://docs.sui.io/guides/developer/advanced/sponsored-transactions)
- [ownership-model.md](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/ownership-model.md)
