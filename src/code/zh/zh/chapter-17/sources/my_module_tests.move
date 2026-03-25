// Test examples for Chapter 9 - Testing patterns for Move contracts
// NOTE: This file demonstrates test patterns. Replace my_package::my_module
//       with your actual module path when using in real projects.
#[test_only]
module my_package::my_module_tests;

use sui::test_scenario;
use sui::clock;

// ── 基础测试模板 ────────────────────────────────────────

#[test]
fun test_placeholder() {
    // Replace with real tests referencing your module
    let mut scenario = test_scenario::begin(@0xA);
    scenario.end();
}

// ── 使用 Clock 测试时间相关逻辑 ─────────────────────────

#[test]
fun test_clock_usage() {
    let mut scenario = test_scenario::begin(@0xA);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    // 验证时间设置生效
    assert!(clock.timestamp_ms() == 1_000_000, 0);

    clock.destroy_for_testing();
    scenario.end();
}
