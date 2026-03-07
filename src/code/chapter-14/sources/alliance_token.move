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
