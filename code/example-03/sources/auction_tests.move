#[test_only]
module dutch_auction::auction_tests;

use dutch_auction::auction;
use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;

#[test]
fun test_price_decreases_over_time() {
    let mut scenario = test_scenario::begin(@0xOwner);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 设置0时刻
    clock.set_for_testing(0);

    // 创建伪造拍卖对象测试价格计算
    let auction = auction::create_test_auction(
        5000,   // start_price
        500,    // end_price
        600_000, // 10分钟 (ms)
        500,    // 每次降 500
        &clock,
        scenario.ctx(),
    );

    // 时刻 0：价格应为 5000
    assert!(auction::current_price(&auction, &clock) == 5000, 0);

    // 经过 10 分钟：价格应为 4500
    clock.set_for_testing(600_000);
    assert!(auction::current_price(&auction, &clock) == 4500, 0);

    // 经过 90 分钟（降价9次 × 500 = 4500，但最低 500）：价格应为 500
    clock.set_for_testing(5_400_000);
    assert!(auction::current_price(&auction, &clock) == 500, 0);

    clock.destroy_for_testing();
    auction.destroy_test_auction();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = auction::EInsufficientPayment)]
fun test_underpayment_fails() {
    // ...测试支付不足时的失败路径
}
