module chapter_17::snippet_04;

// ❌ 在链上排序（极度消耗 Gas）
public fun get_top_bidders(auction: &Auction, n: u64): vector<address> {
    let mut sorted = vector::empty<BidRecord>();
    // ... O(n²) 排序，每次都在链上执行
}

// ✅ 链上只存原始数据，链下排序
public fun get_bid_at(auction: &Auction, index: u64): BidRecord {
    *df::borrow<u64, BidRecord>(&auction.id, index)
}
// dApp 或后端读取所有竞价，在内存中排序，展示排行榜
