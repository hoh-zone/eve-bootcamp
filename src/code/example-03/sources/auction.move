module dutch_auction::auction;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::object::{Self, UID, ID};
use sui::event;
use sui::transfer;

/// SSU 扩展 Witness
public struct AuctionAuth has drop {}

/// 拍卖状态
public struct DutchAuction has key {
    id: UID,
    storage_unit_id: ID,        // 绑定的存储箱
    item_type_id: u64,          // 拍卖的物品类型
    start_price: u64,           // 起始价（MIST）
    end_price: u64,             // 最低价
    start_time_ms: u64,         // 拍卖开始时间
    price_drop_interval_ms: u64, // 每次降价间隔（毫秒）
    price_drop_amount: u64,     // 每次降价幅度
    is_active: bool,            // 是否仍在进行
    proceeds: Balance<SUI>,     // 拍卖收益
    owner: address,             // 拍卖创建者
}

/// 事件
public struct AuctionCreated has copy, drop {
    auction_id: ID,
    item_type_id: u64,
    start_price: u64,
    end_price: u64,
}

public struct AuctionSettled has copy, drop {
    auction_id: ID,
    winner: address,
    final_price: u64,
    item_type_id: u64,
}

// ── 计算当前价格 ─────────────────────────────────────────

public fun current_price(auction: &DutchAuction, clock: &Clock): u64 {
    if !auction.is_active {
        return auction.end_price
    }

    let elapsed_ms = clock.timestamp_ms() - auction.start_time_ms;
    let drops = elapsed_ms / auction.price_drop_interval_ms;
    let total_drop = drops * auction.price_drop_amount;

    if total_drop >= auction.start_price - auction.end_price {
        auction.end_price  // 已降到最低价
    } else {
        auction.start_price - total_drop
    }
}

/// 计算下次降价的剩余时间（毫秒）
public fun ms_until_next_drop(auction: &DutchAuction, clock: &Clock): u64 {
    let elapsed = clock.timestamp_ms() - auction.start_time_ms;
    let interval = auction.price_drop_interval_ms;
    let next_drop_at = (elapsed / interval + 1) * interval;
    next_drop_at - elapsed
}

// ── 创建拍卖 ─────────────────────────────────────────────

public entry fun create_auction(
    storage_unit: &StorageUnit,
    item_type_id: u64,
    start_price: u64,
    end_price: u64,
    price_drop_interval_ms: u64,
    price_drop_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(start_price > end_price, EInvalidPricing);
    assert!(price_drop_amount > 0, EInvalidDropAmount);
    assert!(price_drop_interval_ms >= 60_000, EIntervalTooShort); // 最小1分钟

    let auction = DutchAuction {
        id: object::new(ctx),
        storage_unit_id: object::id(storage_unit),
        item_type_id,
        start_price,
        end_price,
        start_time_ms: clock.timestamp_ms(),
        price_drop_interval_ms,
        price_drop_amount,
        is_active: true,
        proceeds: balance::zero(),
        owner: ctx.sender(),
    };

    event::emit(AuctionCreated {
        auction_id: object::id(&auction),
        item_type_id,
        start_price,
        end_price,
    });

    transfer::share_object(auction);
}

// ── 竞拍：支付当前价格获得物品 ──────────────────────────

public entry fun buy_now(
    auction: &mut DutchAuction,
    storage_unit: &mut StorageUnit,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Item {
    assert!(auction.is_active, EAuctionEnded);

    let price = current_price(auction, clock);
    assert!(coin::value(&payment) >= price, EInsufficientPayment);

    // 退还多付的部分
    let change_amount = coin::value(&payment) - price;
    if change_amount > 0 {
        let change = payment.split(change_amount, ctx);
        transfer::public_transfer(change, ctx.sender());
    }

    // 收入进入拍卖金库
    balance::join(&mut auction.proceeds, coin::into_balance(payment));
    auction.is_active = false;

    event::emit(AuctionSettled {
        auction_id: object::id(auction),
        winner: ctx.sender(),
        final_price: price,
        item_type_id: auction.item_type_id,
    });

    // 从 SSU 取出物品
    storage_unit::withdraw_item(
        storage_unit,
        character,
        AuctionAuth {},
        auction.item_type_id,
        ctx,
    )
}

// ── Owner：提取拍卖收益 ──────────────────────────────────

public entry fun withdraw_proceeds(
    auction: &mut DutchAuction,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == auction.owner, ENotOwner);
    assert!(!auction.is_active, EAuctionStillActive);

    let amount = balance::value(&auction.proceeds);
    let coin = coin::take(&mut auction.proceeds, amount, ctx);
    transfer::public_transfer(coin, ctx.sender());
}

// ── Owner：取消拍卖 ──────────────────────────────────────

public entry fun cancel_auction(
    auction: &mut DutchAuction,
    storage_unit: &mut StorageUnit,
    character: &Character,
    ctx: &mut TxContext,
): Item {
    assert!(ctx.sender() == auction.owner, ENotOwner);
    assert!(auction.is_active, EAuctionAlreadyEnded);

    auction.is_active = false;

    // 将物品取回给 Owner
    storage_unit::withdraw_item(
        storage_unit, character, AuctionAuth {}, auction.item_type_id, ctx,
    )
}

// 错误码
const EInvalidPricing: u64 = 0;
const EInvalidDropAmount: u64 = 1;
const EIntervalTooShort: u64 = 2;
const EAuctionEnded: u64 = 3;
const EInsufficientPayment: u64 = 4;
const EAuctionStillActive: u64 = 5;
const EAuctionAlreadyEnded: u64 = 6;
const ENotOwner: u64 = 7;
