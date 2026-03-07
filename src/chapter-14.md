# Chapter 14：链上经济系统设计

> **目标：** 学会在 EVE Frontier 中设计和实现完整的链上经济系统，包括自定义代币发行、去中心化市场、动态定价与金库管理。

---

> 状态：设计进阶章节。正文以代币、市场、金库和定价机制为主。

##  14.1 EVE Frontier 的经济体系

EVE Frontier 本身已有两种官方货币：

| 货币 | 用途 | 特点 |
|------|------|------|
| **LUX** | 游戏内主流交易货币 | 稳定，用于日常服务和商品交易 |
| **EVE Token** | 生态代币 | 用于开发者激励，可购买特殊资产 |

作为 Builder，你可以：
1. **接受 LUX/SUI 作为支付手段**（直接使用官方 Coin 类型）
2. **发行你自己的联盟代币**（自定义 Coin 模块）
3. **构建市场和交易机制**（基于 SSU 扩展）

这里最重要的不是“能发币、能收费”这些能力本身，而是要先分清：

> 你的经济系统，到底在卖什么、为什么有人会持续付费、什么情况下会被套利或抽干。

很多链上经济设计失败，不是因为代码写错，而是因为一开始就没有把下面这几件事想清楚：

- 你卖的是一次性物品、持续服务，还是准入资格？
- 收入是立即结算，还是长期分润？
- 价格由谁决定？固定、算法、拍卖，还是人工运营？
- 玩家为什么要在你的系统里留资产，而不是用完就走？

### 先区分四种最常见的 Builder 收费模型

| 模型 | 用户买的是什么 | 典型场景 | 风险点 |
|------|------|------|------|
| **一次性购买** | 一个物品或一次动作 | 售货机、跳门付费 | 容易变成纯比价市场 |
| **使用权购买** | 一段时间的访问或能力 | 租赁、订阅、通行证 | 到期、退款、滥用边界复杂 |
| **撮合抽成** | 平台流量和交易撮合 | 市场、拍卖、保险撮合 | 假交易、自买自卖、女巫刷量 |
| **长期金库分润** | 系统现金流的份额 | 联盟金库、协议收入分配 | 治理复杂、分配争议大 |

你在设计经济系统前，最好先明确自己属于哪一类。因为它们对应的对象模型、事件设计和风险控制完全不同。

---

##  14.2 发行自定义代币（Custom Coin）

Sui 的代币（Coin）模型非常标准化。通过 `sui::coin` 模块可以创建任意 Fungible Token：

```move
module my_alliance::alliance_token;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::object::UID;
use sui::transfer;
use sui::tx_context::TxContext;

/// 代币的"一次性见证"（One-Time Witness）
/// 必须与模块同名（全大写），只在 init 时能创建
public struct ALLIANCE_TOKEN has drop {}

/// 代币的元数据（名称、符号、小数位）
fun init(witness: ALLIANCE_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        6,                            // 小数位（decimals）
        b"ALLY",                      // 代币符号
        b"Alliance Token",            // 代币全名
        b"The official token of Alliance X",  // 描述
        option::none(),               // 图标 URL（可选）
        ctx,
    );

    // 将 TreasuryCap 发送给部署者（铸币权）
    transfer::public_transfer(treasury_cap, ctx.sender());
    // 将 CoinMetadata 共享（供 DEX、钱包展示）
    transfer::public_share_object(coin_metadata);
}

/// 铸造代币（只有持有 TreasuryCap 才能调用）
public entry fun mint(
    treasury: &mut TreasuryCap<ALLIANCE_TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::mint(treasury, amount, ctx);
    transfer::public_transfer(coin, recipient);
}

/// 销毁代币（降低总供应量）
public entry fun burn(
    treasury: &mut TreasuryCap<ALLIANCE_TOKEN>,
    coin: Coin<ALLIANCE_TOKEN>,
) {
    coin::burn(treasury, coin);
}
```

发币这件事在技术上很简单，在经济上却最容易被误用。

### 发币前先问的三个问题

#### 1. 这个币为什么存在？

常见合理用途包括：

- 联盟内部记账和激励
- 协议内折扣、分润或投票凭证
- 某种服务配额或准入层

如果答案只是“大家都有币，所以我也发一个”，那大概率不值得做。

#### 2. 这个币是否真的需要链上流通？

有些积分型系统其实不需要独立币，更适合：

- 链上记分对象
- 非转让 badge
- 金库份额记录

因为一旦做成真正可转让 Coin，你就默认引入了：

- 二级市场
- 囤积和投机
- 流动性预期
- 更高的合规和运营负担

#### 3. 谁掌握供应量，供应怎么增长？

`TreasuryCap` 在技术上代表铸币权，在经济上代表货币主权。只要供应策略模糊，后面很容易演变成：

- Builder 随意增发
- 早期用户被稀释
- 价格和预期迅速崩掉

### One-Time Witness 解决了什么，不解决什么？

它解决的是：

- 币种创建身份唯一
- 初始化路径规范
- 元数据和 TreasuryCap 的创建流程安全

它不解决的是：

- 你的供应曲线是否合理
- 币是否有需求
- 币价是否稳定

也就是说，语言保证“币不会被随便伪造”，但不会保证“你发的是个好币”。

---

##  14.3 建立去中心化市场

基于 Smart Storage Unit，可以构建去中心化的物品市场：

```move
module my_market::item_market;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::object::{Self, ID};
use sui::event;

/// 市场扩展 Witness
public struct MarketAuth has drop {}

/// 商品上架信息
public struct Listing has store {
    seller: address,
    item_type_id: u64,
    price: u64,           // 以 MIST（SUI 最小单位）计
    expiry_ms: u64,       // 0 = 永不过期
}

/// 市场注册表
public struct Market has key {
    id: UID,
    storage_unit_id: ID,
    listings: Table<u64, Listing>,  // item_type_id -> Listing
    fee_rate_bps: u64,              // 手续费（基点，100 bps = 1%）
    fee_balance: Balance<SUI>,
}

/// 事件
public struct ItemListed has copy, drop {
    market_id: ID,
    seller: address,
    item_type_id: u64,
    price: u64,
}

public struct ItemSold has copy, drop {
    market_id: ID,
    buyer: address,
    seller: address,
    item_type_id: u64,
    price: u64,
    fee: u64,
}

/// 上架物品
public entry fun list_item(
    market: &mut Market,
    storage_unit: &mut StorageUnit,
    character: &Character,
    item_type_id: u64,
    price: u64,
    expiry_ms: u64,
    ctx: &mut TxContext,
) {
    // 将物品从存储箱取出，存入市场的专属临时仓库
    // （实现细节：使用 MarketAuth{} 调用 SSU 的 withdraw_item）
    // ...

    // 记录上架信息
    table::add(&mut market.listings, item_type_id, Listing {
        seller: ctx.sender(),
        item_type_id,
        price,
        expiry_ms,
    });

    event::emit(ItemListed {
        market_id: object::id(market),
        seller: ctx.sender(),
        item_type_id,
        price,
    });
}

/// 购买物品
public entry fun buy_item(
    market: &mut Market,
    storage_unit: &mut StorageUnit,
    character: &Character,
    item_type_id: u64,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Item {
    let listing = table::borrow(&market.listings, item_type_id);

    // 检查有效期
    if listing.expiry_ms > 0 {
        assert!(clock.timestamp_ms() < listing.expiry_ms, EListingExpired);
    }

    // 验证支付金额
    assert!(coin::value(&payment) >= listing.price, EInsufficientPayment);

    // 扣除手续费
    let fee = listing.price * market.fee_rate_bps / 10_000;
    let seller_amount = listing.price - fee;

    // 分割代币：手续费 + 卖家收益 + 找零
    let fee_coin = payment.split(fee, ctx);
    let seller_coin = payment.split(seller_amount, ctx);
    let change = payment;  // 剩余找零

    balance::join(&mut market.fee_balance, coin::into_balance(fee_coin));
    transfer::public_transfer(seller_coin, listing.seller);
    transfer::public_transfer(change, ctx.sender());

    let seller_addr = listing.seller;
    let price = listing.price;

    // 移除上架记录
    table::remove(&mut market.listings, item_type_id);

    event::emit(ItemSold {
        market_id: object::id(market),
        buyer: ctx.sender(),
        seller: seller_addr,
        item_type_id,
        price,
        fee,
    });

    // 从 SSU 取出物品给买家
    storage_unit::withdraw_item(
        storage_unit, character, MarketAuth {}, item_type_id, ctx,
    )
}
```

这个市场示例已经能说明基本结构，但真实设计时你还要额外想清几件事。

### 一个市场最少包含哪四层？

1. **挂单层**
   卖家提供什么、价格多少、何时过期
2. **托管层**
   物品和资金由谁托管，什么时候真正转移
3. **结算层**
   手续费、卖家收益、找零如何分配
4. **索引层**
   前端如何查到当前可买列表，而不是只看到历史事件

这四层少一层都能“写出代码”，但写不出一个稳定市场。

### 市场设计最容易漏掉的边界

#### 1. 上架时，物品到底有没有真的被锁住？

如果只是记录了 `Listing`，但物品本体没有被安全托管：

- 卖家可能已经把物品挪走
- 前端还会继续展示“可购买”
- 买家付款后才发现无法交付

#### 2. 支付和交付是不是同一笔原子事务？

如果付款成功、交付失败，或交付成功、付款失败，都会造成严重体验和资产问题。链上市场最核心的价值之一，就是把这两个动作收进同一笔原子交易。

#### 3. 下架、过期、重复上架路径是否闭合？

很多市场不是挂单和购买出问题，而是：

- 过期条目还在列表里
- 下架后库存没回去
- 重复上架导致状态错乱

---

##  14.4 动态定价策略

### 策略一：固定价格

最简单的定价，Owner 设定价格，玩家按价购买（如上面的市场例子）。

### 策略二：荷兰式拍卖（价格递减）

```move
public fun get_current_price(
    start_price: u64,
    end_price: u64,
    start_time_ms: u64,
    duration_ms: u64,
    clock: &Clock,
): u64 {
    let elapsed = clock.timestamp_ms() - start_time_ms;
    if elapsed >= duration_ms {
        return end_price  // 已到最低价
    }

    // 线性递减
    let price_drop = (start_price - end_price) * elapsed / duration_ms;
    start_price - price_drop
}
```

### 策略三：供需动态定价（AMM 风格）

基于 **恒定乘积公式** `x * y = k`：

```move
public struct LiquidityPool has key {
    id: UID,
    reserve_sui: Balance<SUI>,
    reserve_item_count: u64,
    k_constant: u64,  // x * y = k
}

/// 计算购买 n 个物品需要支付多少 SUI
public fun get_buy_price(pool: &LiquidityPool, buy_count: u64): u64 {
    let new_item_count = pool.reserve_item_count - buy_count;
    let new_sui_reserve = pool.k_constant / new_item_count;
    new_sui_reserve - balance::value(&pool.reserve_sui)
}
```

### 策略四：会员折扣

```move
public fun calculate_price(
    base_price: u64,
    buyer: address,
    member_registry: &Table<address, MemberTier>,
): u64 {
    if table::contains(member_registry, buyer) {
        let tier = table::borrow(member_registry, buyer);
        match (tier) {
            MemberTier::Gold => base_price * 80 / 100,   // 8折
            MemberTier::Silver => base_price * 90 / 100, // 9折
            _ => base_price,
        }
    } else {
        base_price
    }
}
```

定价策略的选择，本质上是在做三件事之间的权衡：

- **收入最大化**
- **用户可预测性**
- **抗操纵能力**

### 固定价为什么永远不会过时？

因为它最容易被理解，也最容易被运营。

适合：

- 低频商品
- 价格预期稳定的服务
- 刚上线、还没掌握真实需求曲线的产品

很多 Builder 一开始就想上复杂定价，但实际上更稳的路径通常是：

1. 先用固定价跑出真实需求
2. 再根据数据决定是否引入动态机制

### 荷兰拍卖适合什么？

它适合：

- 稀缺资源首次发售
- 你不确定市场心理价位
- 希望让价格随时间自动回落

但你要接受一个现实：

- 它更适合“单次发售”
- 不一定适合长期稳定营业的商店

### AMM 风格为什么危险也强大？

强大在于：

- 连续可交易
- 不依赖人工逐条挂单
- 价格能自动响应库存变化

危险在于：

- 玩家会被滑点和曲线放大影响
- 参数设计不稳时容易被套利
- 池子深度不足时，价格会非常难看

所以如果你不是在做真正需要“持续流动性曲线”的系统，不一定非要上 AMM。

---

##  14.5 金库管理模式

每个商业设施都应该有金库来管理收入：

```move
module my_finance::vault;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;

/// 多资产金库
public struct MultiVault has key {
    id: UID,
    sui_balance: Balance<SUI>,
    total_deposited: u64,   // 历史累计存入
    total_withdrawn: u64,   // 历史累计取出
}

/// 存入资金
public fun deposit(vault: &mut MultiVault, coin: Coin<SUI>) {
    let amount = coin::value(&coin);
    vault.total_deposited = vault.total_deposited + amount;
    balance::join(&mut vault.sui_balance, coin::into_balance(coin));
}

/// 按比例分配给多个地址
public entry fun distribute(
    vault: &mut MultiVault,
    recipients: vector<address>,
    shares: vector<u64>,  // 份额（百分比，总和需等于 100）
    ctx: &mut TxContext,
) {
    assert!(vector::length(&recipients) == vector::length(&shares), EMismatch);

    let total = balance::value(&vault.sui_balance);
    let len = vector::length(&recipients);
    let mut i = 0;

    while (i < len) {
        let share = *vector::borrow(&shares, i);
        let payout = total * share / 100;
        let coin = coin::take(&mut vault.sui_balance, payout, ctx);
        transfer::public_transfer(coin, *vector::borrow(&recipients, i));
        vault.total_withdrawn = vault.total_withdrawn + payout;
        i = i + 1;
    };
}
```

金库设计的重点从来不是“把钱装进去”，而是：

> 收入如何沉淀、谁能动、什么时候分、分完还能不能追账。

### 一个稳的金库至少要回答这些问题

1. 收入按什么资产计价？
2. 资金是实时分发还是先沉淀再结算？
3. 谁能提取？谁能暂停？谁能改分润比例？
4. 分配时的余数和舍入误差怎么处理？
5. 出现争议时，链上记录能不能追溯？

### “立即分发” 和 “先入库后结算” 的取舍

#### 立即分发

优点：

- 逻辑直观
- 收入立刻到各方手里

缺点：

- 每次交易都更重
- 分润路径一多，失败面会扩大

#### 先入库后结算

优点：

- 主交易更轻
- 分润、提现、审计更容易拆开

缺点：

- 要额外处理提现权限和结算时点

大多数真实产品里，后者会更稳。

---

##  14.6 经济系统设计原则

| 原则 | 实践建议 |
|------|--------|
| **可持续性** | 设计回购机制（如用收入回购并销毁代币）避免通胀 |
| **透明度** | 所有经济参数链上可查，通过事件记录每笔交易 |
| **防操控** | 避免单点价格控制，引入 AMM 或荷兰式拍卖 |
| **激励对齐** | 让服务提供方（Builder）和用户的利益方向一致 |
| **升级保留** | 关键参数（费率、价格）设计成可更新的，避免合约锁死 |

### 再补三条最容易被低估的原则

| 原则 | 为什么重要 |
|------|------|
| **反刷量** | 只要你的系统有手续费返佣、活跃激励或排行榜，就会有人刷 |
| **退出路径** | 玩家能不能退订、取回保证金、下架资产，决定了系统是否可信 |
| **参数可解释** | 玩家看不懂价格和费用来源时，会天然不信任你的协议 |

### 设计时一定要主动问的攻击面

- 玩家能不能自己和自己交易来刷奖励？
- 大户能不能瞬间抽干流动性或操纵价格？
- 折扣和返佣能不能被循环套利？
- 金库收益分配时能不能被抢跑或重复领取？

如果你在设计阶段就把这些问题写出来，后面很多漏洞根本不会进代码。

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 自定义代币 | `ALLIANCE_TOKEN` 一次性见证 + `coin::create_currency()` |
| 去中心化市场 | SSU 扩展 + Listing Table + 手续费机制 |
| 定价策略 | 固定价 / 荷兰拍卖 / AMM 恒定乘积 / 会员折扣 |
| 金库管理 | `Balance<T>` 作为内部账本，按比例分配 |
| 经济设计原则 | 可持续 + 透明 + 防操控 + 可升级 |

## 📚 延伸阅读

- [Sui Coin 标准](https://docs.sui.io/guides/developer/sui-101/create-coin)
- [Move Book：Coin 模块](https://move-book.com/programmability/coin.html)
- [EVE Frontier 经济设计](https://github.com/evefrontier/builder-documentation/blob/main/README.md)
- [Chapter 12：Table 与动态字段](./chapter-12.md)
