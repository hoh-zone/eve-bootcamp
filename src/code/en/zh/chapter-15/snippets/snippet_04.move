module chapter_13::snippet_04;

// ── 非官方"市场接口"标准提案 ────────────────────────────
// 任何想接入聚合市场的 Builder 的合约应实现以下接口：

/// 列出item：返回当前出售的item类型and价格
public fun list_items(market: &T): vector<(u64, u64)>  // (type_id, price_sui)

/// query特定item是否可购买
public fun is_available(market: &T, item_type_id: u64): bool

/// 购买（返回item）
public fun purchase<Auth: drop>(
    market: &mut T,
    buyer: &Character,
    item_type_id: u64,
    payment: &mut Coin<SUI>,
    auth: Auth,
    ctx: &mut TxContext,
): Item
