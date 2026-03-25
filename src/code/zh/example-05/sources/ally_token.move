module ally_dao::ally_token;

use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
use sui::transfer;
use sui::tx_context::TxContext;

/// 一次性见证（One-Time Witness）
public struct ALLY_TOKEN has drop {}

fun init(witness: ALLY_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        6,                          // 精度：6位小数
        b"ALLY",                    // 符号
        b"Alliance Token",          // 名称
        b"Governance and dividend token for Alliance X",
        option::none(),
        ctx,
    );

    // TreasuryCap 赋予联盟 DAO 合约（通过地址或多签）
    transfer::public_transfer(treasury_cap, ctx.sender());
    transfer::public_freeze_object(coin_metadata); // 元数据不可变
}

/// 铸造（由 DAO 合约控制，不直接暴露给外部）
public fun internal_mint(
    treasury: &mut TreasuryCap<ALLY_TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::mint(treasury, amount, ctx);
    transfer::public_transfer(coin, recipient);
}
