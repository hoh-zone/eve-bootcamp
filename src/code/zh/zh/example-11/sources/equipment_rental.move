module rental::equipment_rental;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::{Self, String};

// ── 常量 ──────────────────────────────────────────────────

const DAY_MS: u64 = 86_400_000;

// ── 错误码 ────────────────────────────────────────────────
const ENotOwner: u64 = 0;
const EItemCurrentlyRented: u64 = 1;
const ENotAvailable: u64 = 2;
const EInvalidDays: u64 = 3;
const EInsufficientPayment: u64 = 4;
const EWrongListing: u64 = 5;
const ENotRenter: u64 = 6;
const EAlreadyExpired: u64 = 7;
const EAlreadyAvailable: u64 = 8;
const ELeaseNotExpired: u64 = 9;

// ── 数据结构 ───────────────────────────────────────────────

/// 租赁挂单（共享对象）
public struct RentalListing has key {
    id: UID,
    item_id: ID,
    item_name: String,
    owner: address,
    daily_rate_sui: u64,
    max_days: u64,
    is_available: bool,
    current_renter: Option<address>,
    lease_expires_ms: u64,
}

/// 租用凭证 NFT（租用者持有）
public struct RentalPass has key, store {
    id: UID,
    listing_id: ID,
    item_name: String,
    renter: address,
    expires_ms: u64,
    prepaid_days: u64,
    refundable_balance: Balance<SUI>,
}

// ── 事件 ──────────────────────────────────────────────────

public struct ItemRented has copy, drop {
    listing_id: ID,
    renter: address,
    days: u64,
    total_paid: u64,
    expires_ms: u64,
}

public struct ItemReturned has copy, drop {
    listing_id: ID,
    renter: address,
    early: bool,
    refund_amount: u64,
}

// ── 出租者操作 ────────────────────────────────────────────

public fun create_listing(
    item_name: vector<u8>,
    tracked_item_id: ID,
    daily_rate_sui: u64,
    max_days: u64,
    ctx: &mut TxContext,
) {
    let listing = RentalListing {
        id: object::new(ctx),
        item_id: tracked_item_id,
        item_name: string::utf8(item_name),
        owner: ctx.sender(),
        daily_rate_sui,
        max_days,
        is_available: true,
        current_renter: option::none(),
        lease_expires_ms: 0,
    };
    transfer::share_object(listing);
}

public fun delist(
    listing: &mut RentalListing,
    ctx: &TxContext,
) {
    assert!(listing.owner == ctx.sender(), ENotOwner);
    assert!(listing.is_available, EItemCurrentlyRented);
    listing.is_available = false;
}

// ── 租用者操作 ────────────────────────────────────────────

public fun rent_item(
    listing: &mut RentalListing,
    days: u64,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(listing.is_available, ENotAvailable);
    assert!(days >= 1 && days <= listing.max_days, EInvalidDays);

    let total_cost = listing.daily_rate_sui * days;
    assert!(coin::value(&payment) >= total_cost, EInsufficientPayment);

    let expires_ms = clock.timestamp_ms() + days * DAY_MS;

    // 扣除租金，70% 给出租者，30% 作押金锁在 pass 中
    let mut rent_payment = coin::split(&mut payment, total_cost, ctx);
    let owner_amount = total_cost * 70 / 100;
    let owner_share = coin::split(&mut rent_payment, owner_amount, ctx);
    transfer::public_transfer(owner_share, listing.owner);

    // 更新挂单状态
    listing.is_available = false;
    listing.current_renter = option::some(ctx.sender());
    listing.lease_expires_ms = expires_ms;

    // 发放 RentalPass NFT，押金（剩余 30%）锁入 pass
    let pass = RentalPass {
        id: object::new(ctx),
        listing_id: object::id(listing),
        item_name: listing.item_name,
        renter: ctx.sender(),
        expires_ms,
        prepaid_days: days,
        refundable_balance: coin::into_balance(rent_payment),
    };

    // 退找零
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    transfer::public_transfer(pass, ctx.sender());

    event::emit(ItemRented {
        listing_id: object::id(listing),
        renter: ctx.sender(),
        days,
        total_paid: total_cost,
        expires_ms,
    });
}

/// 验证租赁有效性（供其他合约调用）
public fun verify_rental(
    pass: &RentalPass,
    listing_id: ID,
    clock: &Clock,
): bool {
    pass.listing_id == listing_id && clock.timestamp_ms() <= pass.expires_ms
}

/// 提前归还，退押金
public fun return_early(
    listing: &mut RentalListing,
    mut pass: RentalPass,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(pass.listing_id == object::id(listing), EWrongListing);
    assert!(pass.renter == ctx.sender(), ENotRenter);
    assert!(clock.timestamp_ms() < pass.expires_ms, EAlreadyExpired);

    let remaining_ms = pass.expires_ms - clock.timestamp_ms();
    let remaining_days = remaining_ms / DAY_MS;
    let refund = if (remaining_days > 0) {
        balance::value(&pass.refundable_balance) * remaining_days / pass.prepaid_days
    } else {
        0
    };

    if (refund > 0) {
        let refund_coin = coin::take(&mut pass.refundable_balance, refund, ctx);
        transfer::public_transfer(refund_coin, ctx.sender());
    };

    // 剩余押金归出租者
    let remaining_bal = balance::withdraw_all(&mut pass.refundable_balance);
    if (balance::value(&remaining_bal) > 0) {
        transfer::public_transfer(coin::from_balance(remaining_bal, ctx), listing.owner);
    } else {
        balance::destroy_zero(remaining_bal);
    };

    listing.is_available = true;
    listing.current_renter = option::none();

    let RentalPass { id, refundable_balance, .. } = pass;
    balance::destroy_zero(refundable_balance);
    object::delete(id);

    event::emit(ItemReturned {
        listing_id: object::id(listing),
        renter: ctx.sender(),
        early: true,
        refund_amount: refund,
    });
}

/// 租期到期后，出租者收回控制权
public fun reclaim_after_expiry(
    listing: &mut RentalListing,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(listing.owner == ctx.sender(), ENotOwner);
    assert!(!listing.is_available, EAlreadyAvailable);
    assert!(clock.timestamp_ms() > listing.lease_expires_ms, ELeaseNotExpired);
    listing.is_available = true;
    listing.current_renter = option::none();
}
