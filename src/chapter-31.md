# 第31章：Builder Scaffold 完整使用指南（一）——项目结构与合约开发

> **学习目标**：掌握 `builder-scaffold` 的完整目录结构，理解 Docker 和本机两种开发流程，并能独立完成 smart_gate 合约的本地开发与发布。

---

> 状态：已映射到本地脚手架目录。正文命令以本仓库现有 `builder-scaffold` 目录为准。

## 最小调用链

`启动本地链 -> 编译 smart_gate -> 发布 -> 记录 package/object id -> 配置规则 -> 发 permit`

## 对应代码目录

- [builder-scaffold](https://github.com/evefrontier/builder-scaffold)

## 1. 什么是 Builder Scaffold？

`builder-scaffold` 是 EVE Frontier 官方提供的**一站式 Builder 开发脚手架**，包含：

- **Move 合约模板**：两个完整的 Smart Gate Extension 示例
- **TypeScript 交互脚本**：发布后立即可用的链上交互脚本
- **Docker 开发环境**：零配置、开箱即用的本地链
- **dApp 模板**：React + EVE Frontier dapp-kit 的前端起点

```
builder-scaffold/
├── docker/             # Docker 开发环境（Sui CLI + Node.js 容器）
├── move-contracts/     # Move 合约示例
│   ├── smart_gate/     # 主要示例：Star Gate Extension
│   ├── storage_unit/   # 存储单元 Extension 示例
│   └── tokens/         # 代币合约示例
├── ts-scripts/         # TypeScript 交互脚本
│   ├── smart_gate/     # 针对 smart_gate 的 6 个操作脚本
│   ├── utils/          # 公共工具：env配置、derive-object-id、proof
│   └── helpers/        # 查询 OwnerCap 等辅助函数
├── dapps/              # React dApp 模板（EVE Frontier dapp-kit）
└── docs/               # 完整的部署流程文档
```

这一章最重要的不是背目录，而是理解：

> `builder-scaffold` 不是一个示例仓库而已，它其实是在替你把“本地链、合约、脚本、前端”这几条线预先接好。

所以真正的价值是：

- 降低第一次打通闭环的成本
- 给你一个能边改边跑的标准骨架
- 让后面的自定义开发尽量从“改模板”开始，而不是从“自己搭平台”开始

---

## 2. 选择开发流程

官方支持两种流程：

| 流程 | 适用场景 | 前置要求 |
|------|---------|---------|
| **Docker 流程** | 不想在本机安装 Sui/Node 的用户 | 仅 Docker |
| **本机（Host）流程** | 已有 Sui CLI + Node.js | Sui CLI + Node.js |

### 这两种流程真正的取舍

- **Docker**
  更稳，环境差异更少，适合先跑通
- **Host**
  更快，更贴近日常开发，但更依赖你本机环境已经干净

如果你的目标是“先理解完整闭环”，优先 Docker。  
如果你的目标是“高频迭代自己写代码”，后面通常会逐步转向 Host。

---

## 3. Docker 开发环境（推荐新手）

### 快速启动

```bash
# 克隆仓库
git clone https://github.com/evefrontier/builder-scaffold.git
cd builder-scaffold

# 启动开发容器（首次会下载镜像约 2-3 分钟）
cd docker
docker compose run --rm --service-ports sui-dev
```

首次启动时，容器会自动：
1. 创建 3 个 ed25519 密钥对（`ADMIN`、`PLAYER_A`、`PLAYER_B`）
2. 启动本地 Sui 节点
3. 向账户发放测试 SUI

密钥持久保存在 Docker Volume，容器重启后不会丢失。

### 容器内工作目录结构

```
/workspace/
├── builder-scaffold/    # 完整仓库（与宿主机同步）
└── world-contracts/     # 在宿主机克隆后在容器内可见
```

在宿主机编辑文件，在容器内运行命令——两者实时同步。

### 为什么 build 时用 `-e testnet`?

```bash
sui move build -e testnet   # ← 这里的 testnet 是"构建环境"，不是发布目标
```

本地链的 chain ID 每次重启都变化，无法固定在 `Move.toml` 里。`-e testnet` 让依赖解析用 testnet 规则，但实际发布仍然到本地链。

这里最容易误解的是把“构建环境”和“发布目标”混成一件事。

这一步用 `-e testnet`，并不是说你现在真的在往 testnet 发，而是告诉构建器：

- 依赖地址按哪套规则解析
- 包构建按哪套环境约定处理

如果这个概念不分开，后面你在 localnet / testnet / mainnet 切换时会非常容易判断错误。

### 容器常用命令速查

| 任务 | 命令 |
|------|------|
| 查看所有密钥 | `cat /workspace/builder-scaffold/docker/.env.sui` |
| 切换到测试网 | `sui client switch --env testnet` |
| 导入已有密钥 | `sui keytool import <key> ed25519` |
| 编译合约 | `cd .../smart_gate && sui move build -e testnet` |
| 运行 TS 脚本 | `cd /workspace/builder-scaffold && pnpm configure-rules` |
| 启动 GraphQL | `curl http://localhost:9125/graphql` |
| 清除重置 | `docker compose down --volumes && docker compose run --rm --service-ports sui-dev` |

### PostgreSQL + GraphQL 索引器

Docker 环境内置了 Sui 索引器和 GraphQL 支持：

```bash
# 查询链 ID（验证 GraphQL 是否启动）
curl -X POST http://localhost:9125/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ chainIdentifier }"}'
```

GraphQL 端点：`http://localhost:9125/graphql`（可用 [Altair](https://altairgraphql.dev/) 调试）

---

## 4. Smart Gate 合约的文件结构

```
move-contracts/smart_gate/
├── Move.toml                # 包配置（依赖 world-contracts）
├── sources/
│   ├── config.move          # 共享配置基础：ExtensionConfig + AdminCap + XAuth
│   ├── tribe_permit.move    # 示例1：部族身份验证通行证
│   └── corpse_gate_bounty.move # 示例2：提交尸体物品换通行证
└── tests/
    └── gate_tests.move      # 测试
```

### Move.toml 分析

```toml
[package]
name = "smart_gate"
edition = "2024"

[dependencies]
# Git 依赖（推荐锁定稳定 tag）
world = { git = "https://github.com/evefrontier/world-contracts.git", subdir = "contracts/world", rev = "v0.0.14" }

[addresses]
smart_gate = "0x0"   # 发布时自动替换为实际地址
```

> **重要**：建议直接使用 git 依赖并锁定 `rev`（如 `v0.0.14`），不要追踪 `main`，否则 world-contracts 主分支的 Breaking Change 会直接影响编译结果。

### 为什么脚手架示例最适合拿来学“扩展模式”

因为它不是抽象 demo，而是把几个最关键的 Builder 要素都放进去了：

- 动态字段配置
- AdminCap 管理
- Typed Witness 扩展
- Gate 组件接入

换句话说，`smart_gate` 不是在教你写某一个具体业务，而是在教你 EVE Builder 最核心的扩展骨架。

---

## 5. config.move：Extension 基础框架

```move
module smart_gate::config;

use sui::dynamic_field as df;

/// 发布后自动创建，是所有规则的共享存储
public struct ExtensionConfig has key {
    id: UID,
}

/// 管理员权限凭证（init 时转移给部署者）
public struct AdminCap has key, store {
    id: UID,
}

/// 授权见证类型（Typed Witness），传入 gate::issue_jump_permit<XAuth>
public struct XAuth has drop {}

fun init(ctx: &mut TxContext) {
    // AdminCap 转移给部署者
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
    // ExtensionConfig 共享化（所有人可读，只有 AdminCap 持有者可写）
    transfer::share_object(ExtensionConfig { id: object::new(ctx) });
}
```

### 动态字段规则系统

`ExtensionConfig` 使用动态字段来存储各种规则，这样一个配置对象可以同时支持多种不同的扩展规则：

```move
// set_rule：插入或覆盖规则（value 需要 drop ability）
public fun set_rule<K: copy + drop + store, V: store + drop>(
    config: &mut ExtensionConfig,
    _: &AdminCap,      // 只有 AdminCap 才能设置
    key: K,
    value: V,
) {
    if (df::exists_(&config.id, copy key)) {
        let _old: V = df::remove(&mut config.id, copy key);
    };
    df::add(&mut config.id, key, value);
}
```

---

## 6. tribe_permit.move：部族通行证（精读）

这是最简单的 Extension 实现，适合理解扩展模式的核心结构：

```move
module smart_gate::tribe_permit;

// 规则配置（动态字段值）
public struct TribeConfig has drop, store {
    tribe: u32,              // 允许通过的部族 ID
    expiry_duration_ms: u64, // 通行证有效期（毫秒）
}

// 规则标识（动态字段 Key）
public struct TribeConfigKey has copy, drop, store {}
```

### 颁发通行证

```move
pub fun issue_jump_permit(
    extension_config: &ExtensionConfig,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. 读取规则配置
    let tribe_cfg = extension_config.borrow_rule<TribeConfigKey, TribeConfig>(TribeConfigKey {});

    // 2. 验证角色部族
    assert!(character.tribe() == tribe_cfg.tribe, ENotStarterTribe);

    // 3. 计算过期时间（防溢出检查）
    let ts = clock.timestamp_ms();
    assert!(ts <= (0xFFFFFFFFFFFFFFFFu64 - tribe_cfg.expiry_duration_ms), EExpiryOverflow);
    let expires_at = ts + tribe_cfg.expiry_duration_ms;

    // 4. 调用 world 合约颁发 JumpPermit NFT
    gate::issue_jump_permit<XAuth>(
        source_gate, destination_gate, character,
        config::x_auth(),  // 包内唯一的 XAuth 实例
        expires_at, ctx,
    );
}
```

> **设计细节**：与 world-contracts 的原版相比，这里增加了**防溢出检查**（`EExpiryOverflow`），是更健壮的生产实现。

### 管理员设置规则

```move
pub fun set_tribe_config(
    extension_config: &mut ExtensionConfig,
    admin_cap: &AdminCap,
    tribe: u32,
    expiry_duration_ms: u64,
) {
    extension_config.set_rule<TribeConfigKey, TribeConfig>(
        admin_cap,
        TribeConfigKey {},
        TribeConfig { tribe, expiry_duration_ms },
    );
}
```

---

## 7. 编译与测试

```bash
# 进入 smart_gate 目录
cd move-contracts/smart_gate

# 编译（使用 testnet 作为构建环境）
sui move build -e testnet

# 运行测试
sui move test -e testnet
```

### 编译失败常见问题

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `Unpublished dependencies: World` | world-contracts 未部署 | 先部署 world-contracts，或切换为 local 依赖 |
| `Move.lock wrong env` | Move.lock 记录的环境不匹配 | `rm Move.lock && sui move build -e testnet` |
| `edition = "legacy"` 警告 | 使用了旧版 Move | 在 `Move.toml` 中改为 `edition = "2024"` |

---

## 8. 发布合约到本地链

```bash
# 确保 world-contracts 已部署，获得其 publication file
sui client test-publish \
  --build-env testnet \
  --pubfile-path ../../deployments/Pub.localnet.toml

# 发布成功后记录输出的 Package ID
# 填入 .env 文件的 BUILDER_PACKAGE_ID
```

> **`test-publish` vs `publish`**：`test-publish` 是 Sui 的特殊发布模式，允许在本地链上发布依赖未发布的包（用于测试）。实际发布到测试网/主网时使用 `sui client publish`。

---

## 9. 添加你自己的 Extension 规则

以添加"付费通道规则"为例：

### 第一步：在 `config.move` 旁创建新文件 `toll_gate.move`

```move
module smart_gate::toll_gate;

use smart_gate::config::{Self, AdminCap, XAuth, ExtensionConfig};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};

// 规则数据
public struct TollConfig has drop, store {
    toll_amount: u64,
    expiry_duration_ms: u64,
}
public struct TollConfigKey has copy, drop, store {}

// 收费账本（共享对象）
public struct TollVault has key {
    id: UID,
    balance: Balance<SUI>,
}

// 初始化时创建金库
public fun create_vault(ctx: &mut TxContext) {
    transfer::share_object(TollVault {
        id: object::new(ctx),
        balance: balance::zero(),
    });
}
```

### 第二步：实现颁发函数

```move
pub fun pay_and_jump(
    extension_config: &ExtensionConfig,
    vault: &mut TollVault,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let toll_cfg = extension_config.borrow_rule<TollConfigKey, TollConfig>(TollConfigKey {});
    assert!(coin::value(&payment) >= toll_cfg.toll_amount, ETollInsufficient);

    let toll = coin::split(&mut payment, toll_cfg.toll_amount, ctx);
    balance::join(&mut vault.balance, coin::into_balance(toll));
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    let expires = clock.timestamp_ms() + toll_cfg.expiry_duration_ms;
    gate::issue_jump_permit<XAuth>(
        source_gate, destination_gate, character, config::x_auth(), expires, ctx,
    );
}

const ETollInsufficient: u64 = 0;
```

---

## 本章小结

| 组件 | 用途 |
|------|------|
| `docker/compose.yml` | 本地 Sui 链 + GraphQL 索引器一键启动 |
| `move-contracts/smart_gate/` | Gate Extension 主模板 |
| `config.move` | ExtensionConfig + AdminCap + XAuth 基础框架 |
| `tribe_permit.move` | 示例①：部族身份验证 |
| `corpse_gate_bounty.move` | 示例②：物品消耗换通行证 |
| `-e testnet` 构建标志 | 解决本地链 chain ID 不稳定的问题 |

> 下一章：**TypeScript 脚本与 dApp 开发** —— 合约发布后，如何用 6 个现成脚本与链上合约交互，以及如何基于 dApp 模板构建 EVE Frontier 前端。
