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
