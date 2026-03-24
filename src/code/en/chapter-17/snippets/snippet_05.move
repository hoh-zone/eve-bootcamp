module chapter_09::snippet_05;

// ❌ 不推荐：直接依赖 ctx.epoch() as精确时间
// epoch 的粒度是约 24 小时，不适合细粒度时效

// ✅ 推荐：Use Clock object
public fun check_expiry(expiry_ms: u64, clock: &Clock): bool {
    clock.timestamp_ms() < expiry_ms
}
