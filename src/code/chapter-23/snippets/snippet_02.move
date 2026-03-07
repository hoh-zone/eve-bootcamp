module chapter_10::snippet_02;

// 公开查询接口，供其他合约调用
public fun get_current_price(market: &Market, item_type_id: u64): u64 {
    // 返回当前价格，其他合约可以用于定价参考
}

public fun is_item_available(market: &Market, item_type_id: u64): bool {
    table::contains(&market.listings, item_type_id)
}
