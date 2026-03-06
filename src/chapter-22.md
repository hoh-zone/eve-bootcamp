# Chapter 22：故障排查手册（常见错误与调试方法）

> **目标：** 系统整理 EVE Frontier Builder 开发过程中最常遇到的错误类型，掌握高效的调试工作流，把"踩坑"时间降到最低。

---

> 状态：工程保障章节。正文以排错路径和调试习惯为主。

## 22.1 错误分类总览

```
EVE Frontier 开发错误
├── 合约错误（Move）
│   ├── 编译错误（构建失败）
│   ├── 链上 Abort（运行时失败）
│   └── 逻辑错误（成功执行但结果错误）
├── 交易错误（Sui）
│   ├── Gas 问题
│   ├── 对象版本冲突
│   └── 权限错误
├── dApp 错误（TypeScript/React）
│   ├── 钱包连接失败
│   ├── 读取链上数据失败
│   └── 参数构建错误
└── 环境错误
    ├── Docker/本地节点问题
    ├── Sui CLI 配置问题
    └── ENV 变量缺失
```

真正高效的排错，不是背错误大全，而是先把问题定位到正确层。

一个很实用的思路是先问：

1. 这是编译前就坏了，还是链上执行时坏了？
2. 是对象和权限错了，还是前端构参错了？
3. 是环境不一致，还是逻辑本身真的有 bug？

只要第一层归类做对，后面的排查效率会高很多。

---

## 22.2 Move 编译错误

### 错误：`unbound module`

```
error[E02001]: unbound module
  ┌─ sources/my_ext.move:3:5
  │
3 │ use world::gate;
  │     ^^^^^^^^^^^ Unbound module 'world::gate'
```

**原因**：`Move.toml` 中缺少对 `world` 包的依赖声明。

**解决：**
```toml
# Move.toml
[dependencies]
World = { git = "https://github.com/evefrontier/world-contracts.git", subdir = "contracts/world", rev = "v0.0.14" }
```

---

### 错误：`ability constraint not satisfied`

```
error[E05001]: ability constraint not satisfied
   ┌─ sources/market.move:42:30
   |
42 │     transfer::public_transfer(listing, recipient);
   |                               ^^^^^^^ Missing 'store' ability
```

**原因**：`Listing` 结构体缺少 `store` ability，无法被 `public_transfer`。

**解决**：
```move
// 添加所需 ability
public struct Listing has key, store { ... }
//                            ^^^^^
```

---

### 错误：`unused variable` / `unused let binding`

```
warning[W09001]: unused let binding
  = 'receipt' is bound but not used
```

**解决**：用下划线忽略，或确认是否遗漏了归还步骤（Borrow-Use-Return 模式）：
```move
let (_receipt) = character::borrow_owner_cap(...); // 暂时忽略
// 更好的做法：确认归还
character::return_owner_cap(own_cap, receipt);
```

### 对编译错误最有用的习惯

不是复制粘贴报错去搜，而是立刻判断它属于哪一类：

- **依赖解析问题**
  `unbound module`
- **类型 / ability 问题**
  `ability constraint not satisfied`
- **资源生命周期问题**
  `unused let binding`、值未消费、借用冲突

Move 编译器给的错误往往已经很接近真实原因，只要别把它当成纯噪音。

---

## 22.3 链上 Abort 错误解读

链上 Abort 返回如下格式：
```
MoveAbort(MoveLocation { module: ModuleId { address: 0x..., name: Identifier("toll_gate_ext") }, function: 2, instruction: 6, function_name: Some("pay_toll") }, 1)
```

**关键信息**：`function_name` + abort code（末尾的数字）。

### 常见 Abort Code 对照表

| 错误代码 | 典型含义 | 排查方向 |
|---------|---------|---------|
| `0` | 权限不足（`assert!(ctx.sender() == owner)`） | 检查调用者地址 vs 合约中存储的 owner |
| `1` | 余额/数量不足 | 检查 `coin::value()` vs 所需金额 |
| `2` | 对象已存在（`table::add` 重复键） | 检查是否已注册/已购买过 |
| `3` | 对象不存在（`table::borrow` 找不到） | 检查 key 是否正确 |
| `4` | 时间校验失败（过期 / 未到时间） | `clock.timestamp_ms()` 与合约逻辑对比 |
| `5` | 状态不正确（如已结束、未开始） | 检查 `is_settled`、`is_online` 等状态字段 |

### 快速定位 Abort 来源

```bash
# 在源代码中搜索错误码
grep -n "assert!.*4\b\|abort.*4\b\|= 4;" sources/*.move
```

### 遇到 Abort 时，第一反应不该是“合约坏了”

更稳的顺序通常是：

1. 先看 `function_name`
2. 再看 abort code
3. 再对照当时传入的对象、地址、金额、时间参数

很多 Abort 其实不是代码 bug，而是：

- 用了错对象
- 当前状态不满足前置条件
- 前端组装了过期或不完整的参数

---

## 22.4 Gas 相关问题

### `InsufficientGas`（Gas 耗尽）

```
TransactionExecutionError: InsufficientGas
```

**解决方案：阶梯排查**

```typescript
// 1. 先 dryRun 估算 Gas
const estimate = await client.dryRunTransactionBlock({
  transactionBlock: await tx.build({ client }),
});
console.log("Gas 估算：", estimate.effects.gasUsed);

// 2. 在实际交易中设置足够的 Gas Budget（+20% 缓冲）
const gasUsed = Number(estimate.effects.gasUsed.computationCost)
              + Number(estimate.effects.gasUsed.storageCost);
tx.setGasBudget(Math.ceil(gasUsed * 1.2));
```

### `GasBudgetTooHigh`

你的 Gas Budget 超过了账户余额：
```typescript
// 查询账户 SUI 余额
const balance = await client.getBalance({ owner: address, coinType: "0x2::sui::SUI" });
const maxBudget = Number(balance.totalBalance) * 0.5; // 最多用 50% 余额做 Gas
tx.setGasBudget(Math.min(desired_budget, maxBudget));
```

### Gas 问题最容易被误判成“钱包没钱”

实际上常见成因有三种：

- 真没钱
- Gas budget 设太保守
- 交易模型本身就太重

如果你只会不断调大 budget，而不去看 dry run 结果里的成本结构，最后通常只是把结构问题掩盖掉。

---

## 22.5 对象版本冲突

```
TransactionExecutionError: ObjectVersionUnavailableForConsumption
```

**原因**：你的代码持有一个旧版本的对象引用，但链上已经被其他交易修改。

**常见场景**：同时发起多个使用同一共享对象的交易（如 `Market`）。

**解决**：
```typescript
// ❌ 错误：并行发起多个使用同一共享对象的交易
await Promise.all([buyTx1, buyTx2])

// ✅ 正确：顺序执行
for (const tx of [buyTx1, buyTx2]) {
  await client.signAndExecuteTransaction({ transaction: tx })
  // 等待确认后再发下一笔
}
```

### 版本冲突本质上在提醒你：对象是活的

只要多个交易都要写同一个对象，就要假设它随时可能在你再次提交前已经变了。

所以这类问题往往不是“偶发玄学”，而是系统设计告诉你：

- 这里存在共享热点
- 这里需要串行化或刷新对象版本
- 这里可能需要重新考虑分片或拆对象

---

## 22.6 dApp 钱包连接问题

### EVE Vault 未检测到

```
WalletNotFoundError: No wallet found
```

**排查清单：**
1. ✅ EVE Vault 浏览器扩展是否已安装并启用？
2. ✅ `VITE_SUI_NETWORK` 是否与 Vault 当前网络一致（testnet/mainnet）？
3. ✅ `@evefrontier/dapp-kit` 版本是否与 Vault 版本兼容？

```typescript
// 列出所有检测到的钱包（调试用）
import { getWallets } from "@mysten/wallet-standard";
const wallets = getWallets();
console.log("检测到的钱包：", wallets.get().map(w => w.name));
```

### 签名请求被静默拒绝（无弹窗）

**原因**：Vault 可能处于锁定状态。

**解决**：在发起签名前检查钱包状态：
```typescript
const { currentAccount } = useCurrentAccount();
if (!currentAccount) {
  // 引导用户连接钱包，而不是直接发起签名
  showConnectModal();
  return;
}
```

### 钱包问题排查顺序

最稳的顺序通常是：

1. 钱包有没有被检测到
2. 当前账户有没有连接
3. 网络是不是对的
4. 对象和权限是不是当前账户可用的

不要一看到签名失败就直接怀疑 Vault 本身。有大量问题其实是前端状态、网络和对象上下文没对齐。

---

## 22.7 链上数据读取问题

### `getObject` 返回 `null`

```typescript
const obj = await client.getObject({ id: "0x...", options: { showContent: true } });
if (!obj.data) {
  // 对象不存在，或 ID 错误
  console.error("对象不存在，检查 ID 是否正确（可能是 testnet/mainnet 混淆）");
}
```

**常见原因**：
- 用了 testnet 的 Object ID 去查 mainnet（或反之）
- 对象已被删除（合约调用了 `id.delete()`）
- 拼写错误

### `showContent: true` 但 `content.fields` 为空

```typescript
const content = obj.data?.content;
if (content?.dataType !== "moveObject") {
  // 这是一个 package 对象，不是 Move 对象
  console.error("对象不是 MoveObject，可能 ID 指向的是一个 Package");
}
```

### 读不到数据时，优先检查哪四件事

1. ID 是否来自正确网络
2. 这个 ID 是对象还是包
3. 对象是否已经删除或迁移
4. 前端解析路径是不是和真实字段结构一致

很多“读不到”的问题，根本不是节点坏了，而是你自己查错对象了。

---

## 22.8 本地开发环境问题

### Docker 本地链启动失败

```bash
# 查看容器日志
docker compose logs -f

# 常见原因：端口被占用
lsof -i :9000
kill -9 <PID>

# 重置本地链状态（清空所有数据重新开始）
docker compose down -v
docker compose up -d
```

### `sui client publish` 失败

```bash
# 错误：Package verification failed
# 原因：依赖的 world-contracts 地址与本地节点不一致

# 在 Move.toml 中确认本地测试使用 localnet 的包地址
[addresses]
world = "0x_LOCAL_WORLD_ADDRESS_"  # 从本地链部署结果获取
```

### 合约部署后无法调用（找不到函数）

```bash
# 检查发布的包 ID 是否与 ENV 配置一致
echo $VITE_WORLD_PACKAGE

# 验证链上包是否包含预期函数
sui client object 0x_PACKAGE_ID_ --json | jq '.content.disassembled'
```

### 环境问题最怕“半正确”

也就是：

- 本地链是好的
- CLI 也能连
- 但某个地址、依赖或 ENV 还停在另一套环境

这种问题最烦，因为表面上每一层都“看起来没坏”。所以只要碰到环境类问题，最好把：

- 当前网络
- 当前地址
- 当前包 ID
- 当前 ENV 配置

一次性全打印出来比逐个猜快得多。

---

## 22.9 调试工作流：系统化排查

```
遇到问题时，按以下顺序排查：

1. 读错误信息（不要忽略任何细节）
   ├── 是 Move abort？→ 找 abort code → 查合约源码
   ├── 是 Gas 问题？→ dryRun 估算 → 调整 budget
   └── 是 TypeScript 错误？→ console.log 每一步的参数

2. 隔离问题
   ├── 用 Sui Explorer 直接调用合约（绕开 dApp）
   ├── 写 Move 单元测试重现问题
   └── 用 curl/Postman 测试 GraphQL 查询

3. 与社区对齐
   ├── 搜索 Discord #builders 频道
   ├── 粘贴完整错误信息（包括 Transaction Digest）
   └── 提供最小可复现代码
```

### 一个更实战的排查心法

每次都先尽量把问题缩成最小：

- 最少对象
- 最少一步操作
- 最短调用链

因为链上系统一旦把前端、后端、钱包、索引、游戏服都卷进来，问题会迅速放大。先缩小，再定位，效率最高。

---

## 22.10 常用调试工具

| 工具 | 用途 | 链接 |
|------|------|------|
| **Sui Explorer** | 查看交易详情、对象状态 | https://suiexplorer.com |
| **Sui GraphQL IDE** | 手动测试 GraphQL 查询 | https://graphql.testnet.sui.io |
| **Move Prover** | 形式化验证合约属性 | `sui move prove` |
| **dryRun** | 估算 Gas 与模拟执行 | `client.dryRunTransactionBlock()` |
| **sui client call** | 命令行直接调用合约 | `sui client call --help` |

---

## 🔖 本章小结

| 错误类型 | 最快排查路径 |
|--------|-----------|
| Move 编译错误 | 查 `Move.toml` 依赖 + ability 声明 |
| Abort (code N) | 合约源码 grep abort code，对照表速查 |
| Gas 耗尽 | `dryRun()` 预估 + 设置 20% 缓冲 |
| 对象版本冲突 | 顺序执行而非并发，等待每笔 confirm |
| 钱包未检测到 | 检查扩展安装、网络一致性、版本兼容 |
| 对象读取为空 | 确认网络环境（testnet vs mainnet） |
| 本地链问题 | `docker compose logs` + 重置数据卷 |
