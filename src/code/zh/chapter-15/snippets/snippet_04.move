module chapter_13::snippet_04;

// ── 非官方"市场接口"标准提案 ────────────────────────────
// 任何想接入聚合市场的 Builder 的合约应实现以下接口：

/// 列出物品：返回当前出售的物品类型和价格
public fun list_items(market: &T): vector<(u64, u64)>  // (type_id, price_sui)

/// 查询特定物品是否可购买
public fun is_available(market: &T, item_type_id: u64): bool

/// 购买（返回物品）
public fun purchase<Auth: drop>(
    market: &mut T,
    buyer: &Character,
    item_type_id: u64,
    payment: &mut Coin<SUI>,
    auth: Auth,
    ctx: &mut TxContext,
): Item
