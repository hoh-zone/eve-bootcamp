# Chapter 13：跨合约组合性（Composability）

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握如何设计对外友好的合约接口，以及如何安全地调用其他 Builder 发布的合约，构建可组合的 EVE Frontier 生态系统。

---

> 状态：设计进阶章节。正文以跨合约接口与可组合性为主。

## 前置依赖

- 建议先读 [Chapter 7](./chapter-07.md)
- 建议先读 [Chapter 8](./chapter-08.md)

## 源码位置

- [book/src/code/chapter-13](./code/chapter-13)

## 关键测试文件

- 当前目录以组合性示例模块为主；建议重点对照 `oracle.move` 与 `market_v2.move`。

## 推荐阅读顺序

1. 先读组合性原则
2. 再打开 [book/src/code/chapter-13](./code/chapter-13)
3. 最后结合 [Example 9](./example-09.md) 看产品级组合案例

## 验证步骤

1. 能识别对外暴露接口应该保持什么稳定性
2. 能解释组合性带来的依赖风险
3. 能把价格源、市场、支付资产拆成独立模块

## 常见报错

- 把对外接口和内部实现耦死，导致别人无法安全集成

---

## 13.1 可组合性的价值

EVE Frontier 最激动人心的特性之一：**你的合约可以直接调用他人的合约，无需任何中间人**。

```
Builder A：发行了 ALLY Token + 价格预言机
Builder B：调用 A 的价格预言机，以 ALLY Token 定价出售物品
Builder C：在 B 的市场上架，同时接受 A 的 ALLY 和 SUI 支付
```

这创造了真正意义上的**开放经济协议栈**。

---

## 13.2 设计对外友好的 Move 接口

好的 Move 接口设计应遵循：

```move
module my_protocol::oracle;

// ── 公开的视图函数（只读，免费调用）──────────────────────

/// 获取 ALLY/SUI 汇率（以 MIST 计）
public fun get_ally_price(oracle: &PriceOracle): u64 {
    oracle.ally_per_sui
}

/// 检查价格是否在有效期内
public fun is_price_fresh(oracle: &PriceOracle, clock: &Clock): bool {
    clock.timestamp_ms() - oracle.last_updated_ms < PRICE_TTL_MS
}

// ── 公开的可组合函数（其他合约可调用）───────────────────

/// 将 SUI 金额换算为 ALLY 数量
public fun sui_to_ally_amount(
    oracle: &PriceOracle,
    sui_amount: u64,
    clock: &Clock,
): u64 {
    assert!(is_price_fresh(oracle, clock), EPriceStale);
    sui_amount * oracle.ally_per_sui / 1_000_000_000
}
```

### 设计原则

| 原则 | 实现方式 |
|------|--------|
| **只读视图** | `public fun` 不含 `&mut`，零 Gas 调用 |
| **可组合操作** | 接受 Witness 参数，允许授权调用方执行 |
| **版本化** | 保留旧接口，新接口以新函数名/类型参数区分 |
| **事件发射** | 关键操作发射事件，方便监听 |
| **文档化** | 完整注释说明前置条件和返回值 |

---

## 13.3 调用其他 Builder 的合约

### 在 Move.toml 中添加外部依赖

```toml
[dependencies]
# 依赖其他 Builder 已发布的包（通过 Git）
AllyOracle = {
  git = "https://github.com/builder-alice/ally-oracle",
  subdir = "contracts",
  rev = "v1.0.0"
}

# 或直接指定链上地址（对已发布的包）
AllyOracleOnChain = { local = "../ally-oracle" }  # 本地测试用
```

### 在 Move 代码中调用

```move
module my_market::ally_market;

// 引入其他 Builder 的模块（需要在 Move.toml 中声明依赖）
use ally_oracle::oracle::{Self, PriceOracle};
use ally_dao::ally_token::ALLY_TOKEN;

public entry fun buy_with_ally(
    storage_unit: &mut world::storage_unit::StorageUnit,
    character: &Character,
    price_oracle: &PriceOracle,     // 外部 Builder A 的价格预言机
    ally_payment: Coin<ALLY_TOKEN>, // 外部 Builder A 的代币
    item_type_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Item {
    // 调用外部合约的视图函数
    let price_in_sui = oracle::sui_to_ally_amount(
        price_oracle,
        ITEM_BASE_PRICE_SUI,
        clock,
    );

    assert!(coin::value(&ally_payment) >= price_in_sui, EInsufficientPayment);

    // 处理 ALLY Token 支付（转到联盟金库等）
    // ...

    // 从自己的 SSU 取出物品
    storage_unit::withdraw_item(
        storage_unit, character, MyMarketAuth {}, item_type_id, ctx,
    )
}
```

---

## 13.4 接口版本控制与协议标准

当你的合约被广泛使用后，升级接口必须保证向后兼容：

```move
module my_protocol::market_v2;

// 使用类型标记版本
public struct V1 has drop {}
public struct V2 has drop {}

// V1 接口（永远保留）
public fun get_price_v1(market: &Market, _: V1): u64 {
    market.price
}

// V2 接口（新增，支持动态价格）
public fun get_price_v2(
    market: &Market,
    clock: &Clock,
    _: V2,
): u64 {
    calculate_dynamic_price(market, clock)
}
```

### 定义跨合约接口标准（类似 ERC 标准）

在 EVE Frontier 生态中，可以通过文档约定接口标准，让多个 Builder 的合约相互兼容：

```move
// ── 非官方"市场接口"标准提案 ────────────────────────────
// 任何想接入聚合市场的 Builder 的合约应实现以下接口：

/// 列出物品：返回当前出售的物品类型和价格
public fun list_items(market: &T): vector<(u64, u64)>  // (type_id, price_sui)

/// 查询特定物品是否可购买
public fun is_available(market: &T, item_type_id: u64): bool

/// 购买（返回物品）
public fun purchase<Auth: drop>(
    market: &mut T,
    buyer: &Character,
    item_type_id: u64,
    payment: &mut Coin<SUI>,
    auth: Auth,
    ctx: &mut TxContext,
): Item
```

---

## 13.5 实战：聚合价格比较器

```typescript
// 在 dApp 中聚合多个 Builder 的市场价格
async function getAggregatedPrices(
  itemTypeId: number,
  marketIds: string[],
  client: SuiClient,
): Promise<Array<{ marketId: string; price: number; builder: string }>> {

  // 批量读取所有市场状态
  const markets = await client.multiGetObjects({
    ids: marketIds,
    options: { showContent: true },
  });

  const prices = markets
    .map((market, i) => {
      const fields = (market.data?.content as any)?.fields;
      if (!fields) return null;

      // 读取 listings Table 中的价格（简化）
      const listing = fields.listings?.fields?.contents?.find(
        (entry: any) => Number(entry.fields?.key) === itemTypeId
      );

      if (!listing) return null;

      return {
        marketId: marketIds[i],
        price: Number(listing.fields.value.fields.price),
        builder: fields.owner ?? "未知",
      };
    })
    .filter(Boolean)
    .sort((a, b) => a!.price - b!.price); // 按价格升序

  return prices as any[];
}
```

---

## 13.6 组合性的风险与防御

| 风险 | 描述 | 防御 |
|------|------|------|
| **依赖合约升级** | 外部合约升级可能破坏你的调用 | 锁定特定版本（rev = "v1.0.0"） |
| **外部合约暂停** | 依赖的合约被撤销或修改 | 设计降级路径（fallback 逻辑） |
| **重入型攻击** | 外部合约回调你的合约 | Move 通过所有权系统天然防御 |
| **价格操控** | 依赖的预言机被操控 | 使用多个预言机取中位数 |

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 可组合性价值 | 你的合约可以被他人调用，形成协议栈 |
| 接口设计 | 只读视图 + Witness 授权 + 文档注释 |
| 引用外部包 | Move.toml 依赖 + `use` 语句 |
| 版本控制 | 保留旧接口 + 类型标记版本 |
| 聚合 dApp | 批量读取多合约数据，前端聚合展示 |

## 📚 延伸阅读

- [EVE World Explainer](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/eve-frontier-world-explainer.md)
- [Move Book：包系统](https://move-book.com/programmability/packages.html)
