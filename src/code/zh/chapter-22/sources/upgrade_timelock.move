module my_gov::upgrade_timelock;

use sui::object::{Self, UID};
use sui::package::UpgradeCap;
use sui::clock::Clock;
use sui::transfer;

// ── 错误码 ────────────────────────────────────────────────
const EAlreadyAnnounced: u64 = 0;
const ENotAnnounced: u64 = 1;
const ETimelockNotExpired: u64 = 2;
const ENotAdmin: u64 = 3;

// ── 数据结构 ───────────────────────────────────────────────

public struct TimelockWrapper has key {
    id: UID,
    upgrade_cap: UpgradeCap,
    delay_ms: u64,
    announced_at_ms: u64,
    admin: address,
}

// ── 包装 UpgradeCap ───────────────────────────────────────

public fun wrap(
    upgrade_cap: UpgradeCap,
    delay_ms: u64,
    ctx: &mut TxContext,
) {
    let wrapper = TimelockWrapper {
        id: object::new(ctx),
        upgrade_cap,
        delay_ms,
        announced_at_ms: 0,
        admin: ctx.sender(),
    };
    transfer::share_object(wrapper);
}

// ── 第一步：公告升级意图（开始计时）──────────────────────

public fun announce_upgrade(
    wrapper: &mut TimelockWrapper,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == wrapper.admin, ENotAdmin);
    assert!(wrapper.announced_at_ms == 0, EAlreadyAnnounced);
    wrapper.announced_at_ms = clock.timestamp_ms();
}

// ── 第二步：延迟期满后执行升级 ────────────────────────────

public fun execute_upgrade_after_timelock(
    wrapper: &mut TimelockWrapper,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == wrapper.admin, ENotAdmin);
    assert!(wrapper.announced_at_ms > 0, ENotAnnounced);
    assert!(
        clock.timestamp_ms() >= wrapper.announced_at_ms + wrapper.delay_ms,
        ETimelockNotExpired,
    );
    // 重置：下次升级需要重新公告
    wrapper.announced_at_ms = 0;
    // 在实际使用中，此处调用 package::authorize_upgrade(&mut wrapper.upgrade_cap, ...)
}

// ── 取消公告 ──────────────────────────────────────────────

public fun cancel_announcement(
    wrapper: &mut TimelockWrapper,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == wrapper.admin, ENotAdmin);
    wrapper.announced_at_ms = 0;
}

// ── 读取状态 ──────────────────────────────────────────────

public fun time_remaining_ms(wrapper: &TimelockWrapper, clock: &Clock): u64 {
    if (wrapper.announced_at_ms == 0) {
        return wrapper.delay_ms
    };
    let elapsed = clock.timestamp_ms() - wrapper.announced_at_ms;
    if (elapsed >= wrapper.delay_ms) { 0 } else { wrapper.delay_ms - elapsed }
}
