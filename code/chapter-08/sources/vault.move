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
