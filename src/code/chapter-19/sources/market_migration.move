// 场景：将 ListingsV1（vector）迁移为 ListingsV2（Table）
// 此文件演示批量数据迁移模式，MarketV1/V2 定义在同一包的其他文件中。
module migration::market_migration;

use sui::object::{Self, UID, ID};
use sui::table;
use sui::transfer;

// ── 迁移状态追踪 ──────────────────────────────────────────

public struct MigrationState has key {
    id: UID,
    source_market_id: ID,
    migrated_count: u64,
    total_count: u64,
    is_complete: bool,
}

public fun create_migration_state(
    source_market_id: ID,
    total_count: u64,
    ctx: &mut TxContext,
) {
    let state = MigrationState {
        id: object::new(ctx),
        source_market_id,
        migrated_count: 0,
        total_count,
        is_complete: false,
    };
    transfer::share_object(state);
}

// ── 迁移核心逻辑 ──────────────────────────────────────────

/// 每次迁移一批（避免单笔交易超出计算 Gas 限制）
/// 实际项目中，old_market 和 new_market 传入具体的 Market 类型。
/// 这里简化为演示控制流逻辑。
public fun mark_batch_migrated(
    state: &mut MigrationState,
    batch_size: u64,
) {
    assert!(!state.is_complete, EMigrationComplete);

    let start = state.migrated_count;
    let end = min_u64(start + batch_size, state.total_count);

    // 在实际项目中，这里会遍历 old_market 的数据并插入 new_market
    // 例如：
    // let mut i = start;
    // while (i < end) {
    //     let listing = old_market::get_listing(old_market, i);
    //     new_market::insert_listing(new_market, listing);
    //     i = i + 1;
    // };

    state.migrated_count = end;
    if (end == state.total_count) {
        state.is_complete = true;
    };
}

/// Move 没有内置 min，这里提供一个辅助函数
fun min_u64(a: u64, b: u64): u64 {
    if (a < b) { a } else { b }
}

// ── 状态读取 ──────────────────────────────────────────────

public fun is_complete(state: &MigrationState): bool { state.is_complete }
public fun progress(state: &MigrationState): (u64, u64) {
    (state.migrated_count, state.total_count)
}

const EMigrationComplete: u64 = 0;
