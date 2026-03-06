# Chapter 8：链上经济系统设计

> ⏱ 预计学习时间：2 小时
>
> **目标：** 学会在 EVE Frontier 中设计和实现完整的链上经济系统，包括自定义代币发行、去中心化市场、动态定价与金库管理。

---

> 状态：设计进阶章节。正文以代币、市场、金库和定价机制为主。

## 前置依赖

- 建议先读 [Chapter 3](./chapter-03.md)
- 建议先读 [Chapter 7](./chapter-07.md)

## 源码位置

- [book/src/code/chapter-08](./code/chapter-08)

## 关键测试文件

- 当前目录以 `alliance_token.move`、`item_market.move`、`vault.move` 为主。

## 推荐阅读顺序

1. 先读代币与金库设计
2. 再打开 [book/src/code/chapter-08](./code/chapter-08) 对照市场与定价示例
3. 最后结合 [Example 3](./example-03.md) 看完整产品化案例

## 验证步骤

1. 能比较固定价、荷兰拍卖和动态定价的区别
2. 能定位金库和代币模块的职责
3. 能把本章模型映射到拍卖或订阅类案例

## 常见报错

- 只描述经济模型，不给出可执行的对象与资金流设计

---

## 8.1 EVE Frontier 的经济体系

EVE Frontier 本身已有两种官方货币：

| 货币 | 用途 | 特点 |
|------|------|------|
| **LUX** | 游戏内主流交易货币 | 稳定，用于日常服务和商品交易 |
| **EVE Token** | 生态代币 | 用于开发者激励，可购买特殊资产 |

作为 Builder，你可以：
1. **接受 LUX/SUI 作为支付手段**（直接使用官方 Coin 类型）
2. **发行你自己的联盟代币**（自定义 Coin 模块）
3. **构建市场和交易机制**（基于 SSU 扩展）

---

## 8.2 发行自定义代币（Custom Coin）

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

---

## 8.3 建立去中心化市场

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

---

## 8.4 动态定价策略

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

---

## 8.5 金库管理模式

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

---

## 8.6 经济系统设计原则

| 原则 | 实践建议 |
|------|--------|
| **可持续性** | 设计回购机制（如用收入回购并销毁代币）避免通胀 |
| **透明度** | 所有经济参数链上可查，通过事件记录每笔交易 |
| **防操控** | 避免单点价格控制，引入 AMM 或荷兰式拍卖 |
| **激励对齐** | 让服务提供方（Builder）和用户的利益方向一致 |
| **升级保留** | 关键参数（费率、价格）设计成可更新的，避免合约锁死 |

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
- [Chapter 7：Table 与动态字段](./chapter-07.md)
