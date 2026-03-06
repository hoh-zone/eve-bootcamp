module chapter_08::snippet_03;

public fun get_current_price(
    start_price: u64,
    end_price: u64,
    start_time_ms: u64,
    duration_ms: u64,
    clock: &Clock,
): u64 {
    let elapsed = clock.timestamp_ms() - start_time_ms;
    if elapsed >= duration_ms {
        return end_price  // 已到最低价
    }

    // 线性递减
    let price_drop = (start_price - end_price) * elapsed / duration_ms;
    start_price - price_drop
}
