module chapter_17::snippet_01;

// ❌ 把所有数据放在一个对象（最大 250KB）
public struct BadMarket has key {
    id: UID,
    listings: vector<Listing>,     // 随商品增多，对象越来越大
    bid_history: vector<BidRecord>, // 历史数据无限增长
}

// ✅ 用动态字段或独立对象分散存储
public struct GoodMarket has key {
    id: UID,
    listing_count: u64,  // 只存计数器
    // 具体 Listing 用动态字段存储：df::add(id, item_id, listing)
}
