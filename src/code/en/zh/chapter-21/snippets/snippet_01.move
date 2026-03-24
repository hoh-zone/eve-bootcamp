module chapter_17::snippet_01;

// ❌ 把所有数据放在一个object（最大 250KB）
public struct BadMarket has key {
    id: UID,
    listings: vector<Listing>,     // 随商品增多，对象越来越大
    bid_history: vector<BidRecord>, // 历史数据无限增长
}

// ✅ 用dynamic field或独立object分散存储
public struct GoodMarket has key {
    id: UID,
    listing_count: u64,  // 只存计数器
    // 具体 Listing 用dynamic field storage：df::add(id, item_id, listing)
}
