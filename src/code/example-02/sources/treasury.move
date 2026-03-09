// sources/treasury.move
module toll_gate::treasury;

use sui::object::{Self, UID};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::tx_context::TxContext;
use sui::transfer;
use sui::event;

// ── 类型定义 ─────────────────────────────────────────────

/// 这里用 SUI 代币代表 LUX（演示）
/// 真实部署中换成 LUX 的 Coin 类型

/// 金库：收集所有通行费
public struct TollTreasury has key {
    id: UID,
    balance: Balance<SUI>,
    total_jumps: u64,      // 累计跳跃次数（统计用）
    toll_amount: u64,      // 当前票价（以 MIST 计，1 SUI = 10^9 MIST）
}

/// OwnerCap：只有持有此对象才能提取金库资金
public struct TreasuryOwnerCap has key, store {
    id: UID,
}

// ── 事件 ──────────────────────────────────────────────────

public struct TollCollected has copy, drop {
    payer: address,
    amount: u64,
    total_jumps: u64,
}

public struct TollWithdrawn has copy, drop {
    recipient: address,
    amount: u64,
}

// ── 初始化 ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    // 创建金库（共享对象，任何人可以存入）
    let treasury = TollTreasury {
        id: object::new(ctx),
        balance: balance::zero(),
        total_jumps: 0,
        toll_amount: 50_000_000_000,  // 50 SUI（单位：MIST）
    };

    // 创建 Owner 凭证（转给部署者）
    let owner_cap = TreasuryOwnerCap {
        id: object::new(ctx),
    };

    transfer::share_object(treasury);
    transfer::transfer(owner_cap, ctx.sender());
}

// ── 公开函数 ──────────────────────────────────────────────

/// 存入通行费（由星门扩展调用）
public fun deposit_toll(
    treasury: &mut TollTreasury,
    payment: Coin<SUI>,
    payer: address,
) {
    let amount = coin::value(&payment);

    // 验证金额正确
    assert!(amount >= treasury.toll_amount, 1); // E_INSUFFICIENT_FEE

    treasury.total_jumps = treasury.total_jumps + 1;
    balance::join(&mut treasury.balance, coin::into_balance(payment));

    event::emit(TollCollected {
        payer,
        amount,
        total_jumps: treasury.total_jumps,
    });
}

/// 提取金库 LUX（只有持有 TreasuryOwnerCap 才能调用）
public fun withdraw(
    treasury: &mut TollTreasury,
    _cap: &TreasuryOwnerCap,
    amount: u64,
    ctx: &mut TxContext,
) {
    let coin = coin::take(&mut treasury.balance, amount, ctx);
    transfer::public_transfer(coin, ctx.sender());

    event::emit(TollWithdrawn {
        recipient: ctx.sender(),
        amount,
    });
}

/// 修改票价（Owner 调用）
public fun set_toll_amount(
    treasury: &mut TollTreasury,
    _cap: &TreasuryOwnerCap,
    new_amount: u64,
) {
    treasury.toll_amount = new_amount;
}

/// 读取当前票价
public fun toll_amount(treasury: &TollTreasury): u64 {
    treasury.toll_amount
}

/// 读取金库余额
public fun balance_amount(treasury: &TollTreasury): u64 {
    balance::value(&treasury.balance)
}
