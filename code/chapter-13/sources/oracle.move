module my_protocol::oracle;

// ── 公开的视图函数（只读，免费调用）──────────────────────

/// 获取 ALLY/SUI 汇率（以 MIST 计）
public fun get_ally_price(oracle: &PriceOracle): u64 {
    oracle.ally_per_sui
}

/// 检查价格是否在有效期内
public fun is_price_fresh(oracle: &PriceOracle, clock: &Clock): bool {
    clock.timestamp_ms() - oracle.last_updated_ms < PRICE_TTL_MS
}

// ── 公开的可组合函数（其他合约可调用）───────────────────

/// 将 SUI 金额换算为 ALLY 数量
public fun sui_to_ally_amount(
    oracle: &PriceOracle,
    sui_amount: u64,
    clock: &Clock,
): u64 {
    assert!(is_price_fresh(oracle, clock), EPriceStale);
    sui_amount * oracle.ally_per_sui / 1_000_000_000
}
