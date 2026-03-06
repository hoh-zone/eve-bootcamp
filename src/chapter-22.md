# Chapter 22：故障排查手册（常见错误与调试方法）

> ⏱ 预计学习时间：2 小时
>
> **目标：** 系统整理 EVE Frontier Builder 开发过程中最常遇到的错误类型，掌握高效的调试工作流，把"踩坑"时间降到最低。

---

> 状态：工程保障章节。正文以排错路径和调试习惯为主。

## 前置依赖

- 建议先读 [Chapter 4](./chapter-04.md)
- 建议先读 [Chapter 5](./chapter-05.md)
- 建议先读 [Chapter 11](./chapter-11.md)

## 源码位置

- [book/src/code/chapter-22](./code/chapter-22)

## 关键测试文件

- 当前目录以错误片段与修复示例为主。

## 推荐阅读顺序

1. 先读错误分类
2. 再对照 [book/src/code/chapter-22](./code/chapter-22) 片段
3. 最后把本章排错顺序应用到一个真实案例

## 验证步骤

1. 能按“读错误 -> 缩范围 -> 验证输入输出”走一遍调试流程
2. 能从常见报错中快速定位到网络、对象 ID、权限、签名等层面
3. 能把一类错误归到合约、交易或前端

## 常见报错

- 看到报错后直接改代码，不先确认输入、环境和对象 ID 是否正确

---

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
