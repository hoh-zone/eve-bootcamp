module my_protocol::market_v2;

// 使用类型标记版本
public struct V1 has drop {}
public struct V2 has drop {}

// V1 接口（永远保留）
public fun get_price_v1(market: &Market, _: V1): u64 {
    market.price
}

// V2 接口（新增，支持动态价格）
public fun get_price_v2(
    market: &Market,
    clock: &Clock,
    _: V2,
): u64 {
    calculate_dynamic_price(market, clock)
}
