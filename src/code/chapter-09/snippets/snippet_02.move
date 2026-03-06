module chapter_09::snippet_02;

// ❌ 危险：u64 减法下溢会 abort，但如果逻辑错误可能算出极大值
fun unsafe_calc(a: u64, b: u64): u64 {
    a - b  // 如果 b > a，直接 abort（Move 会检查）
}

// ✅ 安全：在操作前检查
fun safe_calc(a: u64, b: u64): u64 {
    assert!(a >= b, EInsufficientBalance);
    a - b
}

// ✅ 对于有意允许的下溢，使用检查后的计算
fun safe_pct(total: u64, bps: u64): u64 {
    // bps 最大 10000，防止 total * bps 溢出
    assert!(bps <= 10_000, EInvalidBPS);
    total * bps / 10_000  // Move u64 最大 1.8e19，需要注意大数
}
