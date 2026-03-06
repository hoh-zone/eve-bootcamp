module chapter_17::snippet_05;

// 分片路由
public entry fun buy_item_sharded(
    shards: &mut vector<MarketShard>,
    item_type_id: u64,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    let shard_index = item_type_id % vector::length(shards);
    let shard = vector::borrow_mut(shards, shard_index);
    buy_from_shard(shard, item_type_id, payment, ctx);
}
