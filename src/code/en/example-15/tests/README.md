# Example 15 Test Matrix

本目录用于约束 `pvp_shield.move` 的最小验收范围。由于该案例依赖 `AdminACL` 与战损证明，建议先把最关键的资金流和状态流测通。

## Happy Path

1. 成功投保
   输入：合法 `insured_item_id`、保额、天数和足额保费
   断言：
   - 铸造 `PolicyNFT`
   - `claims_pool` 与 `reserve` 按 70/30 分账
   - 过量保费被找零

2. 有效期内理赔
   输入：未理赔、未过期保单 + 有效服务器证明
   断言：
   - `policy.is_claimed == true`
   - 赔付金额等于 `coverage_amount`
   - `claims_pool` 与 `total_paid_out` 更新正确

3. 管理员补充理赔池
   输入：准备金余额足够、调用者为管理员
   断言：
   - `reserve` 减少
   - `claims_pool` 增加

## Failure Path

1. 保费不足时投保失败
2. 保单过期后理赔失败
3. 重复理赔失败
4. 理赔池不足时理赔失败
5. 非管理员补充理赔池失败
