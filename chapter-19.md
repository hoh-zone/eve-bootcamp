# Chapter 19：Move 高级模式 — 升级兼容性设计

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握生产级 Move 合约的升级兼容架构，包括版本化 API、数据迁移、Policy 控制，以及在不中断服务的情况下平滑升级。

---

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
- [EVE Builder 约束](../welcome/contstraints.md)
