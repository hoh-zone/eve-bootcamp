module chapter_08::snippet_04;

public struct LiquidityPool has key {
    id: UID,
    reserve_sui: Balance<SUI>,
    reserve_item_count: u64,
    k_constant: u64,  // x * y = k
}

/// 计算购买 n 个物品需要支付多少 SUI
public fun get_buy_price(pool: &LiquidityPool, buy_count: u64): u64 {
    let new_item_count = pool.reserve_item_count - buy_count;
    let new_sui_reserve = pool.k_constant / new_item_count;
    new_sui_reserve - balance::value(&pool.reserve_sui)
}
