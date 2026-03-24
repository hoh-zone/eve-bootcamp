// 演示：升级包发布后，V1 和 V2 API 并存（向后兼容设计）
module my_market::market;

use sui::object::{Self, UID};
use sui::dynamic_field as df;
use sui::transfer;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::clock::Clock;

// ── 错误码 ────────────────────────────────────────────────
const ENotOwner: u64 = 0;
const EInsufficientPayment: u64 = 1;

// ── 数据结构 ───────────────────────────────────────────────

/// V2 Market（与 market_v1 是不同的类型，展示 Package Upgrade 后的新版本）
public struct MarketV2 has key {
    id: UID,
    base_toll: u64,
    owner: address,
    revenue: Balance<SUI>,
    discount_active: bool,
    discount_bps: u64,   // 折扣率，例如 500 = 5%
}

// ── 初始化 ────────────────────────────────────────────────

public fun create(base_toll: u64, ctx: &mut TxContext) {
    transfer::share_object(MarketV2 {
        id: object::new(ctx),
        base_toll,
        owner: ctx.sender(),
        revenue: balance::zero(),
        discount_active: false,
        discount_bps: 0,
    });
}

// ── V1 API（永远保持向后兼容）────────────────────────────

public fun pay_toll_v1(
    market: &mut MarketV2,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(coin::value(&payment) >= market.base_toll, EInsufficientPayment);
    let toll_coin = coin::split(&mut payment, market.base_toll, ctx);
    balance::join(&mut market.revenue, coin::into_balance(toll_coin));
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };
}

// ── V2 API（新功能：支持折扣）────────────────────────────

public fun pay_toll_v2(
    market: &mut MarketV2,
    mut payment: Coin<SUI>,
    discount_code: Option<vector<u8>>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let effective_toll = if (market.discount_active && option::is_some(&discount_code)) {
        market.base_toll * (10_000 - market.discount_bps) / 10_000
    } else {
        market.base_toll
    };

    assert!(coin::value(&payment) >= effective_toll, EInsufficientPayment);
    let toll_coin = coin::split(&mut payment, effective_toll, ctx);
    balance::join(&mut market.revenue, coin::into_balance(toll_coin));
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    // 使用 clock 可记录访问时间戳（通过动态字段）
    let ts = clock.timestamp_ms();
    if (!df::exists_(&market.id, b"last_access_ms")) {
        df::add(&mut market.id, b"last_access_ms", ts);
    } else {
        *df::borrow_mut<vector<u8>, u64>(&mut market.id, b"last_access_ms") = ts;
    };
}

// ── 管理操作 ──────────────────────────────────────────────

public fun set_discount(
    market: &mut MarketV2,
    active: bool,
    discount_bps: u64,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == market.owner, ENotOwner);
    market.discount_active = active;
    market.discount_bps = discount_bps;
}

public fun withdraw(market: &mut MarketV2, ctx: &mut TxContext) {
    assert!(ctx.sender() == market.owner, ENotOwner);
    let amount = balance::value(&market.revenue);
    if (amount > 0) {
        let coin = coin::take(&mut market.revenue, amount, ctx);
        transfer::public_transfer(coin, market.owner);
    }
}
