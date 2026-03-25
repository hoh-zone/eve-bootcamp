module chapter_17::snippet_02;

// Auction结束后，删除 Listing 获得 Gas 退款
public fun end_auction(auction: DutchAuction) {
    let DutchAuction { id, .. } = auction;
    id.delete(); // 删除对象 → 存储退款
}

// 领取完毕后，删除 DividendClaim object
public fun close_claim_record(record: DividendClaim) {
    let DividendClaim { id, .. } = record;
    id.delete();
}
