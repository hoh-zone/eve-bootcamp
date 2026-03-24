// 演示：在不破坏向后兼容的情況下，通过动态字段扩展 Market 对象（V1 基础版）
module my_market::market_v1;

use sui::object::{Self, UID};
use sui::dynamic_field as df;
use sui::transfer;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};

// ── 错误码 ────────────────────────────────────────────────
const ENotOwner: u64 = 0;

// ── 数据结构 ───────────────────────────────────────────────

/// V1 Market：只有 toll 和 owner 两个字段
/// 后续通过动态字段扩展，无需 V1 对象升级
public struct Market has key {
    id: UID,
    toll: u64,
    owner: address,
    revenue: Balance<SUI>,
}

// ── 初始化 ────────────────────────────────────────────────

public fun create(toll: u64, ctx: &mut TxContext) {
    transfer::share_object(Market {
        id: object::new(ctx),
        toll,
        owner: ctx.sender(),
        revenue: balance::zero(),
    });
}

// ── V1 核心逻辑 ───────────────────────────────────────────

public fun pay_toll(
    market: &mut Market,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(coin::value(&payment) >= market.toll, ENotOwner);
    let toll_coin = coin::split(&mut payment, market.toll, ctx);
    balance::join(&mut market.revenue, coin::into_balance(toll_coin));
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };
}

/// V1 → V2 升级：用动态字段追加 expiry_ms（无需重新部署 Market 对象）
public fun add_expiry_field(
    market: &mut Market,
    expiry_ms: u64,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == market.owner, ENotOwner);
    if (!df::exists_(&market.id, b"expiry_ms")) {
        df::add(&mut market.id, b"expiry_ms", expiry_ms);
    }
}

/// V2 版本读取 expiry（向后兼容：旧对象没有此字段时返回默认值 0）
public fun get_expiry(market: &Market): u64 {
    if (df::exists_(&market.id, b"expiry_ms")) {
        *df::borrow<vector<u8>, u64>(&market.id, b"expiry_ms")
    } else {
        0
    }
}

public fun withdraw(market: &mut Market, ctx: &mut TxContext) {
    assert!(ctx.sender() == market.owner, ENotOwner);
    let amount = balance::value(&market.revenue);
    if (amount > 0) {
        let coin = coin::take(&mut market.revenue, amount, ctx);
        transfer::public_transfer(coin, market.owner);
    }
}
