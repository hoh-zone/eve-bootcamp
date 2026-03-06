module my_market::ally_market;

// 引入其他 Builder 的模块（需要在 Move.toml 中声明依赖）
use ally_oracle::oracle::{Self, PriceOracle};
use ally_dao::ally_token::ALLY_TOKEN;

public entry fun buy_with_ally(
    storage_unit: &mut world::storage_unit::StorageUnit,
    character: &Character,
    price_oracle: &PriceOracle,     // 外部 Builder A 的价格预言机
    ally_payment: Coin<ALLY_TOKEN>, // 外部 Builder A 的代币
    item_type_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Item {
    // 调用外部合约的视图函数
    let price_in_sui = oracle::sui_to_ally_amount(
        price_oracle,
        ITEM_BASE_PRICE_SUI,
        clock,
    );

    assert!(coin::value(&ally_payment) >= price_in_sui, EInsufficientPayment);

    // 处理 ALLY Token 支付（转到联盟金库等）
    // ...

    // 从自己的 SSU 取出物品
    storage_unit::withdraw_item(
        storage_unit, character, MyMarketAuth {}, item_type_id, ctx,
    )
}
