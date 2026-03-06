# Chapter 13：跨合约组合性（Composability）

> **目标：** 掌握如何设计对外友好的合约接口，以及如何安全地调用其他 Builder 发布的合约，构建可组合的 EVE Frontier 生态系统。

---

> 状态：设计进阶章节。正文以跨合约接口与可组合性为主。

## 13.1 可组合性的价值

EVE Frontier 最激动人心的特性之一：**你的合约可以直接调用他人的合约，无需任何中间人**。

```
Builder A：发行了 ALLY Token + 价格预言机
Builder B：调用 A 的价格预言机，以 ALLY Token 定价出售物品
Builder C：在 B 的市场上架，同时接受 A 的 ALLY 和 SUI 支付
```

这创造了真正意义上的**开放经济协议栈**。

可组合性真正厉害的地方，不是“大家都能互相调用”这句口号，而是：

> 你写的协议一旦足够清晰，别人就能把它当积木，而不是把它当黑盒。

这会直接改变 Builder 的思路：

- 你不再只是做一个单点功能
- 你是在决定自己要成为“终端产品”还是“底层能力”

很多最有价值的协议，并不是自己包办所有事，而是把某一个能力做成别人愿意反复接入的模块。

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

### 好接口的标准，不只是“别人能调通”

一个真正对外友好的接口，至少应该让外部集成者能快速回答这些问题：

1. 这个函数会不会改状态？
2. 调用前必须准备哪些对象和权限？
3. 调用失败最常见的原因是什么？
4. 返回值和事件各自代表什么？

如果这些都不清楚，别人虽然“理论上能调”，但集成成本会高得离谱。

### 接口设计里最容易犯的三个错

#### 1. 把内部实现细节直接暴露成外部依赖

一旦你的接口强依赖内部对象布局，后面每次重构都会把外部集成者一起拖下水。

#### 2. 读接口和写接口混得太近

只读查询最好尽量简单稳定。可写入口则应该明确标注权限和副作用。两者混在一起，集成方很容易误用。

#### 3. 错误边界不清楚

如果函数可能因为：

- 权限不足
- 数据过期
- 价格无效
- 对象状态不匹配

而失败，那这些前提最好能通过文档、命名或辅助只读接口提前暴露出来。

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

### 依赖别人合约时，真正绑定的是什么？

不是“一个 Git 仓库地址”这么简单，而是同时绑定了：

- 对方的接口稳定性
- 对方的升级策略
- 对方的经济和治理选择
- 你自己的故障半径

也就是说，你每引入一个外部协议，就等于把自己的一部分稳定性外包给了别人。

### 所以接外部协议前先问四个问题

1. 这个协议的核心接口是否稳定？
2. 它升级时会不会破坏我当前用法？
3. 如果它暂停或失效，我有没有降级路径？
4. 我能不能把关键依赖收敛到只读接口，而不是深度写入耦合？

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

### 为什么版本控制要从第一版就开始想？

因为只要别人开始依赖你，“改接口”就不再只是你的内部事务。

你要同时考虑：

- 老调用方还能不能继续活
- 新功能能不能逐步引入
- 前端、脚本、聚合器是否要同步迁移

很多协议不是死于功能不足，而是死于“第二版把第一版都打碎了”。

### 标准化接口最值钱的地方

不是显得专业，而是能催生二级生态：

- 聚合器更容易接
- 比价工具更容易做
- 第三方前端更容易复用
- 其他 Builder 更愿意基于你继续搭

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

这个例子很适合说明一个现实：

> 可组合性的价值，很多时候是在链下被放大的。

也就是说，链上协议只要把接口和事件设计清楚，链下就能做出：

- 比价器
- 聚合器
- 推荐路由
- 策略编排

所以你设计合约时，不要只想着“链上另一个合约会不会调我”，也要想“链下工具会不会愿意消费我”。

---

## 13.6 组合性的风险与防御

| 风险 | 描述 | 防御 |
|------|------|------|
| **依赖合约升级** | 外部合约升级可能破坏你的调用 | 锁定特定版本（rev = "v1.0.0"） |
| **外部合约暂停** | 依赖的合约被撤销或修改 | 设计降级路径（fallback 逻辑） |
| **重入型攻击** | 外部合约回调你的合约 | Move 通过所有权系统天然防御 |
| **价格操控** | 依赖的预言机被操控 | 使用多个预言机取中位数 |

### 再补三个实际项目里很常见的风险

| 风险 | 描述 | 防御 |
|------|------|------|
| **接口语义漂移** | 函数名没变，但行为口径变了 | 用版本号、文档和事件语义一起约束 |
| **外部协议活着，但数据质量下降** | 预言机没坏，只是更新变慢或价格异常 | 增加 freshness / sanity check |
| **降级路径缺失** | 外部依赖不可用时，自己的主流程直接瘫痪 | 预设 fallback、暂停开关、手动接管路径 |

### 组合不是越深越好

组合层次越深，你获得的能力越强，但也越难维护。

一个实用原则是：

- 优先依赖稳定、只读、可验证的外部能力
- 谨慎依赖深度耦合、强状态写入的外部流程

因为前者坏了通常只是“数据变差”，后者坏了可能直接把你的核心业务链打断。

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
