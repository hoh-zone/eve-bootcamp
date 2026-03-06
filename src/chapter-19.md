# Chapter 19：Move 高级模式 — 升级兼容性设计

> **目标：** 掌握生产级 Move 合约的升级兼容架构，包括版本化 API、数据迁移、Policy 控制，以及在不中断服务的情况下平滑升级。

---

> 状态：设计进阶章节。正文以升级兼容、迁移和时间锁控制为主。

## 19.1 升级兼容性问题的本质

Move 合约升级面临两个核心约束：

```
约束1：结构体定义不可修改（不能加/删字段，不能改字段类型）
约束2：函数签名不可修改（参数和返回值不能变）

BUT：
✅ 可以添加新函数
✅ 可以添加新模块
✅ 可以修改函数内部逻辑（不变签名）
✅ 可以添加新结构体
```

**挑战**：如果你的合约 v1 有个 `Market` 结构体，v2 想增加一个 `expiry_ms` 字段，你不能直接修改。

升级兼容这一章真正要解决的，不是“怎么发新版本”，而是：

> 怎么让一个已经被对象、前端、脚本、用户共同依赖的系统继续活下去。

所以升级问题本质上是四层兼容问题：

- 链上对象兼容
- 链上接口兼容
- 前端解析兼容
- 运维流程兼容

---

## 19.2 扩展模式：用动态字段追加"未来字段"

**最佳实践**：预先为未来字段留下扩展空间：

```move
module my_market::market_v1;

/// 当前字段
public struct Market has key {
    id: UID,
    toll: u64,
    owner: address,
    // 注意：不要试图预测未来需要的字段——因为你改不了
    // 而是依赖动态字段做扩展
}

// V1 → V2：用动态字段追加 expiry_ms
// （升级包发布后，在迁移脚本中调用）
public entry fun add_expiry_field(
    market: &mut Market,
    expiry_ms: u64,
) {
    // 如果还没有这个字段，才添加
    if !df::exists_(&market.id, b"expiry_ms") {
        df::add(&mut market.id, b"expiry_ms", expiry_ms);
    }
}

/// V2 版本读取 expiry（向后兼容：旧对象没有这个字段时返回默认值）
public fun get_expiry(market: &Market): u64 {
    if df::exists_(&market.id, b"expiry_ms") {
        *df::borrow<vector<u8>, u64>(&market.id, b"expiry_ms")
    } else {
        0  // 默认永不过期
    }
}
```

### 动态字段为什么会成为升级逃生口？

因为它让你在不改原始 struct 布局的前提下，给旧对象补充新语义。

但它也有边界：

- 适合追加字段
- 不适合把所有未来复杂结构都硬塞进去

如果一个版本升级需要往对象上拼很多临时字段，那通常说明你该重新思考模型，而不是无限依赖补丁式扩展。

---

## 19.3 版本化 API 设计

当你需要改变函数行为时，保留旧版本，添加新版本：

```move
module my_market::market;

/// V1 API（永远保持向后兼容）
public entry fun buy_item_v1(
    market: &mut Market,
    payment: Coin<SUI>,
    item_type_id: u64,
    ctx: &mut TxContext,
): Item {
    // 原始逻辑
}

/// V2 API（新功能：支持折扣码）
public entry fun buy_item_v2(
    market: &mut Market,
    payment: Coin<SUI>,
    item_type_id: u64,
    discount_code: Option<vector<u8>>,  // 新参数
    clock: &Clock,                       // 新参数（时效验证）
    ctx: &mut TxContext,
): Item {
    // 新逻辑（包含折扣处理）
    let effective_price = apply_discount(market, item_type_id, discount_code, clock);
    // ...
}
```

**dApp 端适配**：在 TypeScript 端检查合约版本，选择调用哪个函数：

```typescript
async function buyItem(useV2: boolean, ...) {
  const tx = new Transaction();

  if (useV2) {
    tx.moveCall({ target: `${PKG}::market::buy_item_v2`, ... });
  } else {
    tx.moveCall({ target: `${PKG}::market::buy_item_v1`, ... });
  }
}
```

### 为什么“保留旧入口”往往比“强迫全部迁移”更稳？

因为线上系统的调用方从来不只有你自己：

- 旧前端还在跑
- 用户脚本可能还在用
- 第三方聚合器可能还没升级

所以最稳的升级路径往往不是“一刀切替换”，而是：

1. 新旧并存
2. 给迁移窗口
3. 逐步下线旧接口

---

## 19.4 升级锁定策略

对于高价值合约，可以在 UpgradeCap 上增加时间锁：

```move
module my_gov::upgrade_timelock;

use sui::package::UpgradeCap;
use sui::clock::Clock;

public struct TimelockWrapper has key {
    id: UID,
    upgrade_cap: UpgradeCap,
    delay_ms: u64,           // 升级需要提前公告的等待时间
    announced_at_ms: u64,    // 公告时间（0 = 未公告）
}

/// 第一步：公告升级意图（开始计时）
public entry fun announce_upgrade(
    wrapper: &mut TimelockWrapper,
    _admin: &AdminCap,
    clock: &Clock,
) {
    assert!(wrapper.announced_at_ms == 0, EAlreadyAnnounced);
    wrapper.announced_at_ms = clock.timestamp_ms();
}

/// 第二步：等待延迟期后才能执行升级
public fun authorize_upgrade(
    wrapper: &mut TimelockWrapper,
    clock: &Clock,
): &mut UpgradeCap {
    assert!(wrapper.announced_at_ms > 0, ENotAnnounced);
    assert!(
        clock.timestamp_ms() >= wrapper.announced_at_ms + wrapper.delay_ms,
        ETimelockNotExpired,
    );
    // 重置，下次升级需要重新公告
    wrapper.announced_at_ms = 0;
    &mut wrapper.upgrade_cap
}
```

### TimeLock 真正保护的不是代码，而是信任关系

它给社区、协作者和用户留出了观察窗口，让升级不至于变成“管理员今晚想改什么就改什么”。

这在高价值协议里非常关键，因为升级风险很多时候不是技术 bug，而是治理风险。

---

## 19.5 大规模数据迁移策略

当需要重建存储结构时，采用"增量迁移"而不是"一次性迁移"：

```move
// 场景：将 ListingsV1（vector）迁移为 ListingsV2（Table）
module migration::market_migration;

public struct MigrationState has key {
    id: UID,
    migrated_count: u64,
    total_count: u64,
    is_complete: bool,
}

/// 每次迁移一批（避免一笔交易超出计算限制）
public entry fun migrate_batch(
    old_market: &mut MarketV1,
    new_market: &mut MarketV2,
    state: &mut MigrationState,
    batch_size: u64,         // 每次处理 batch_size 条记录
    ctx: &TxContext,
) {
    let start = state.migrated_count;
    let end = min(start + batch_size, state.total_count);
    let mut i = start;

    while (i < end) {
        let listing = get_listing_v1(old_market, i);
        insert_listing_v2(new_market, listing);
        i = i + 1;
    };

    state.migrated_count = end;
    if end == state.total_count {
        state.is_complete = true;
    };
}
```

**迁移脚本：自动循环执行直到完成**

```typescript
async function runMigration(stateId: string) {
  let isComplete = false;
  let batchNum = 0;

  while (!isComplete) {
    const tx = new Transaction();
    tx.moveCall({
      target: `${MIGRATION_PKG}::market_migration::migrate_batch`,
      arguments: [/* ... */, tx.pure.u64(100)], // 每批 100 条
    });

    const result = await client.signAndExecuteTransaction({ signer: adminKeypair, transaction: tx });
    console.log(`Batch ${++batchNum} done:`, result.digest);

    // 检查迁移状态
    const state = await client.getObject({ id: stateId, options: { showContent: true } });
    isComplete = (state.data?.content as any)?.fields?.is_complete;

    await new Promise(r => setTimeout(r, 1000)); // 间隔 1 秒
  }

  console.log("迁移完成！");
}
```

### 为什么迁移最好增量做，而不是一把梭？

因为真实线上系统里，你通常要同时平衡：

- 计算上限
- 风险可控
- 失败可恢复
- 迁移期间服务还能继续运行

一次性迁移最大的问题不是写不出来，而是：

- 中途失败很难恢复
- 失败后状态容易半新半旧
- 交易太大时根本发不出去

---

## 19.6 升级完整工作流

```
① 开发新版本合约（本地 + testnet 验证）
② 声明升级意图（TimeLock 开始计时，通知社区）
③ 社区审查期（72 小时）
④ TimeLock 到期后，执行 sui client upgrade --upgrade-capability <CAP_ID>
⑤ 运行数据迁移脚本（如有必要）
⑥ 更新 dApp 配置（新 Package ID、新接口版本）
⑦ 公告升级完成
```

### 一个成熟团队会把升级视为一次“受控发布事件”

也就是说，除了链上动作本身，还应该同步准备：

- 升级公告
- 前端切换计划
- 回滚或停机预案
- 升级后观察指标

否则“链上已经升级完成”并不等于“系统已经稳定完成升级”。

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 升级约束 | 结构体/函数签名不可改，但可加新函数/模块 |
| 动态字段扩展 | `df::add()` 在运行时追加"未来字段" |
| 版本化 API | `buy_v1()` / `buy_v2()` 并存，dApp 按版本选择 |
| TimeLock 升级 | 公告 + 等待期 → 社区审查 → 才能执行 |
| 增量迁移 | `migrate_batch()` 分批处理，避免超出计算限制 |

## 📚 延伸阅读

- [Sui Package 升级](https://docs.sui.io/guides/developer/packages/upgrade)
- [Chapter 9：安全审计](./chapter-09.md)
- [EVE Builder 约束](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
