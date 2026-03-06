# 实战案例 1：白名单矿区守卫（智能炮塔访问控制）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 编写一个智能炮塔扩展，让炮塔只放行持有"矿区通行证 NFT"的玩家；同时构建一个管理界面，让 Owner 能在线颁发通行证。

---

> 状态：已映射到本地代码目录。正文覆盖通行证 NFT 与炮塔白名单逻辑，适合作为第一个完整 Builder 闭环。

## 前置依赖

- 建议先读 [Chapter 6](./chapter-06.md)、[Chapter 14](./chapter-14.md)
- 需要本地 `sui` CLI 与 `pnpm`

## 对应代码目录

- [example-01](./code/example-01)
- [example-01/dapp](./code/example-01/dapp)

## 源码位置

- [Move.toml](./code/example-01/Move.toml)
- [mining_pass.move](./code/example-01/sources/mining_pass.move)
- [guard_extension.move](./code/example-01/sources/guard_extension.move)
- [dapp/readme.md](./code/example-01/dapp/readme.md)

## 关键测试文件

- [tests/README.md](./code/example-01/tests/README.md)

## 推荐阅读顺序

1. 先看 `mining_pass.move` 理解凭证 NFT
2. 再读 `guard_extension.move` 看炮塔校验逻辑
3. 最后打开 dApp 对照颁证与撤销流程

## 最小调用链

`Owner 颁发通行证 -> 玩家持有 MiningPass -> 炮塔扩展读取凭证 -> 放行或开火`

## 验证步骤

1. 在 [example-01](./code/example-01) 运行 `sui move build`
2. 在 [example-01/dapp](./code/example-01/dapp) 运行 `pnpm install && pnpm dev`
3. 按测试矩阵验证颁证、放行、撤销三条路径

## 常见报错

- 白名单逻辑只查地址，不绑定具体 `MiningPass` 对象
- 撤销后前端缓存未刷新，导致仍显示可通行

---

## 需求分析

**场景：** 你的联盟在深空开采到了一片稀有矿区，部署了一个智能炮塔保护基地。但你希望区别对待不同角色：
- ✅ **联盟成员**：持有 `MiningPass` NFT，炮塔放行
- ❌ **非成员**：没有 `MiningPass`，炮塔自动开火

**额外要求：**
- Owner（你）可以通过 dApp 给信任角色颁发 `MiningPass`
- `MiningPass` 可以被 Owner 撤销
- dApp 显示当前受保护状态和通行证持有者列表

---

## 第一部分：Move 合约开发

### 目录结构

```
mining-guard/
├── Move.toml
└── sources/
    ├── mining_pass.move      # NFT 定义
    └── guard_extension.move  # 炮塔扩展
```

### 第一步：定义 MiningPass NFT

```move
// sources/mining_pass.move
module mining_guard::mining_pass;

use sui::object::{Self, UID};
use sui::tx_context::TxContext;
use sui::transfer;
use sui::event;

/// 矿区通行证 NFT
public struct MiningPass has key, store {
    id: UID,
    holder_name: vector<u8>,    // 持有者名称（方便辨识）
    issued_at_ms: u64,          // 颁发时间戳
    zone_id: u64,               // 对应哪个矿区（支持多矿区）
}

/// 管理员能力（只有合约部署者持有）
public struct AdminCap has key, store {
    id: UID,
}

/// 事件：新通行证颁发
public struct PassIssued has copy, drop {
    pass_id: ID,
    recipient: address,
    zone_id: u64,
}

/// 合约初始化：部署者获得 AdminCap
fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    // 将 AdminCap 转给部署者地址
    transfer::transfer(admin_cap, ctx.sender());
}

/// 颁发矿区通行证（只有持有 AdminCap 才能调用）
public entry fun issue_pass(
    _admin_cap: &AdminCap,             // 验证调用者是管理员
    recipient: address,                 // 接收者地址
    holder_name: vector<u8>,
    zone_id: u64,
    ctx: &mut TxContext,
) {
    let pass = MiningPass {
        id: object::new(ctx),
        holder_name,
        issued_at_ms: ctx.epoch_timestamp_ms(),
        zone_id,
    };

    // 发射事件
    event::emit(PassIssued {
        pass_id: object::id(&pass),
        recipient,
        zone_id,
    });

    // 将通行证转给接收者
    transfer::transfer(pass, recipient);
}

/// 撤销通行证
/// Owner 可以通过 admin_cap 销毁指定角色的通行证
/// （实际上，你可以设计成"收回+销毁"，这里简化为让持有者自行烧毁）
public entry fun revoke_pass(
    _admin_cap: &AdminCap,
    pass: MiningPass,
) {
    let MiningPass { id, .. } = pass;
    id.delete();
}

/// 检查通行证是否属于特定矿区
public fun is_valid_for_zone(pass: &MiningPass, zone_id: u64): bool {
    pass.zone_id == zone_id
}
```

### 第二步：编写炮塔扩展

```move
// sources/guard_extension.move
module mining_guard::guard_extension;

use mining_guard::mining_pass::{Self, MiningPass};
use world::turret::{Self, Turret};
use world::character::Character;
use sui::tx_context::TxContext;

/// 炮塔扩展的 Witness 类型
public struct GuardAuth has drop {}

/// 受保护的矿区 ID（这个版本保护 zone 1）
const PROTECTED_ZONE_ID: u64 = 1;

/// 请求安全通行（玩家持有通行证则被炮塔放过）
/// 
/// 注意：实际炮塔的"不开火"逻辑由游戏服务器执行，
/// 这里的合约用于验证和记录许可意图
public entry fun request_safe_passage(
    turret: &mut Turret,
    character: &Character,
    pass: &MiningPass,           // 必须持有通行证
    ctx: &mut TxContext,
) {
    // 验证通行证属于正确的矿区
    assert!(
        mining_pass::is_valid_for_zone(pass, PROTECTED_ZONE_ID),
        0  // 错误码：无效的矿区通行证
    );

    // 调用炮塔的安全通行函数，传入 GuardAuth{} 作为扩展凭证
    // （实际 API 以世界合约为准）
    turret::grant_safe_passage(
        turret,
        character,
        GuardAuth {},
        ctx,
    );
}
```

### 第三步：编译和发布

```bash
cd mining-guard

# 编译检查
sui move build

# 发布到测试网
sui client publish 

# 记录输出：
# Package ID: 0x_YOUR_PACKAGE_ID_
# AdminCap Object ID: 0x_YOUR_ADMIN_CAP_
```

### 第四步：注册扩展到炮塔

```typescript
// scripts/register-extension.ts
import { Transaction } from "@mysten/sui/transactions";
import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

const WORLD_PACKAGE = "0x...";
const MY_PACKAGE = "0x_YOUR_PACKAGE_ID_";
const TURRET_ID = "0x...";
const CHARACTER_ID = "0x...";
const OWNER_CAP_ID = "0x...";

async function registerExtension() {
  const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });
  const keypair = Ed25519Keypair.fromSecretKey(/* your key */);

  const tx = new Transaction();

  // 1. 从角色借用炮塔的 OwnerCap
  const [ownerCap] = tx.moveCall({
    target: `${WORLD_PACKAGE}::character::borrow_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::turret::Turret`],
    arguments: [tx.object(CHARACTER_ID), tx.object(OWNER_CAP_ID)],
  });

  // 2. 注册我们的扩展
  tx.moveCall({
    target: `${WORLD_PACKAGE}::turret::authorize_extension`,
    typeArguments: [`${MY_PACKAGE}::guard_extension::GuardAuth`],
    arguments: [tx.object(TURRET_ID), ownerCap],
  });

  // 3. 归还 OwnerCap
  tx.moveCall({
    target: `${WORLD_PACKAGE}::character::return_owner_cap`,
    typeArguments: [`${WORLD_PACKAGE}::turret::Turret`],
    arguments: [tx.object(CHARACTER_ID), ownerCap],
  });

  const result = await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
  });
  console.log("扩展注册成功！Tx:", result.digest);
}

registerExtension();
```

---

## 第二部分：管理员 dApp

### 功能：颁发通行证界面

```tsx
// src/AdminPanel.tsx
import { useState } from 'react'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { useConnection } from '@evefrontier/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'

const MY_PACKAGE = "0x_YOUR_PACKAGE_ID_"
const ADMIN_CAP_ID = "0x_YOUR_ADMIN_CAP_"

export function AdminPanel() {
  const { isConnected, handleConnect } = useConnection()
  const dAppKit = useDAppKit()
  const [recipient, setRecipient] = useState('')
  const [holderName, setHolderName] = useState('')
  const [status, setStatus] = useState('')

  const issuePass = async () => {
    if (!recipient || !holderName) {
      setStatus('❌ 请填写接收者地址和名称')
      return
    }

    const tx = new Transaction()
    tx.moveCall({
      target: `${MY_PACKAGE}::mining_pass::issue_pass`,
      arguments: [
        tx.object(ADMIN_CAP_ID),
        tx.pure.address(recipient),
        tx.pure.vector('u8', Array.from(new TextEncoder().encode(holderName))),
        tx.pure.u64(1), // 矿区 Zone ID
      ],
    })

    try {
      setStatus('⏳ 交易提交中...')
      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`✅ 通行证已颁发！Tx: ${result.digest.slice(0, 12)}...`)
    } catch (e: any) {
      setStatus(`❌ 失败：${e.message}`)
    }
  }

  if (!isConnected) {
    return (
      <div className="admin-panel">
        <button onClick={handleConnect}>🔗 连接管理员钱包</button>
      </div>
    )
  }

  return (
    <div className="admin-panel">
      <h2>🛡 矿区通行证管理</h2>

      <div className="form-group">
        <label>接收者 Sui 地址</label>
        <input
          value={recipient}
          onChange={e => setRecipient(e.target.value)}
          placeholder="0x..."
        />
      </div>

      <div className="form-group">
        <label>持有者名称</label>
        <input
          value={holderName}
          onChange={e => setHolderName(e.target.value)}
          placeholder="Mining Corp Alpha"
        />
      </div>

      <button className="issue-btn" onClick={issuePass}>
        📜 颁发矿区通行证
      </button>

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 第三部分：玩家端 dApp

```tsx
// src/PlayerPanel.tsx
import { useConnection, useSmartObject } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

const MY_PACKAGE = "0x_YOUR_PACKAGE_ID_"
const TURRET_ID = "0x..."
const CHARACTER_ID = "0x..."

export function PlayerPanel() {
  const { isConnected, handleConnect } = useConnection()
  const { assembly, loading } = useSmartObject()
  const dAppKit = useDAppKit()
  const [passId, setPassId] = useState('')
  const [status, setStatus] = useState('')

  const requestPassage = async () => {
    const tx = new Transaction()
    tx.moveCall({
      target: `${MY_PACKAGE}::guard_extension::request_safe_passage`,
      arguments: [
        tx.object(TURRET_ID),
        tx.object(CHARACTER_ID),
        tx.object(passId),  // 玩家的 MiningPass Object ID
      ],
    })

    try {
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('✅ 安全通行已记录，炮塔将放行')
    } catch (e: any) {
      setStatus('❌ 通行证验证失败，无法进入矿区')
    }
  }

  if (!isConnected) return <button onClick={handleConnect}>连接钱包</button>
  if (loading) return <div>加载炮塔状态...</div>

  return (
    <div className="player-panel">
      <h2>⚡ {assembly?.name ?? '矿区守卫炮塔'}</h2>
      <p>状态：{assembly?.status}</p>

      <div className="pass-input">
        <label>输入你的矿区通行证 Object ID</label>
        <input
          value={passId}
          onChange={e => setPassId(e.target.value)}
          placeholder="0x..."
        />
        <button onClick={requestPassage}>🛡 申请安全通行</button>
      </div>

      {status && <p>{status}</p>}
    </div>
  )
}
```

---

## 🎯 完整实现回顾

```
1. Move 合约
   ├── mining_pass.move → 定义 MiningPass NFT + AdminCap + issue_pass / revoke_pass
   └── guard_extension.move → 炮塔扩展 + request_safe_passage（验证通行证后调用炮塔 API）

2. 注册流程
   └── authorize_extension<GuardAuth>(turret, owner_cap)

3. 管理员 dApp
   └── 输入地址和名称 → 调用 issue_pass → 将 NFT 转给目标角色

4. 玩家 dApp
   └── 输入通行证 ID → 调用 request_safe_passage → 炮塔放行记录上链
```

## 🔧 扩展练习

1. 给 `MiningPass` 添加过期时间，过期后炮塔不再放行
2. 在合约中记录所有活跃通行证的集合，供 dApp 查询展示
3. 实现"团队许可证"：一张许可证可供多个预定成员使用

---

## 📚 关联文档

- [Smart Turret 文档](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/turret/README.md)
- [Chapter 3：Move 安全模式](./chapter-03.md#35-关键安全模式)
- [Chapter 4：注册扩展到组件](./chapter-04.md#47-将扩展发布并注册到组件)
