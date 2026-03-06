module chapter_09::snippet_06;

// ❌ 有竞态问题：两个交易可能同时通过检查
public fun buy_item(market: &mut Market, ...) {
    let listing = table::borrow(&market.listings, item_type_id);
    assert!(listing.amount > 0, EOutOfStock);
    // ← 另一个 TX 可能在这里同时通过同样的检查
    // ... 然后两个都执行购买，导致超卖
}

// ✅ Sui 的解决方案：通过对共享对象的写锁确保序列化
// Sui 的 Move 执行器保证：写同一个共享对象的交易是顺序执行的
// 所以上面的代码在 Sui 上实际是安全的！但要确保你的逻辑正确处理负库存
public fun buy_item(market: &mut Market, ...) {
    // 这次检查是原子的，其他 TX 会等待
    assert!(table::contains(&market.listings, item_type_id), ENotListed);
    let listing = table::remove(&mut market.listings, item_type_id);  // 原子移除
    // ...
}
