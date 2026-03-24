# Example 11 Test Matrix

本目录用于约束 `equipment_rental.move` 的最小验收范围。即使暂时没有完整的 Move 单测，也应先覆盖以下四条路径：

## Happy Path

1. 创建挂单
   输入：合法 `item_id`、`daily_rate_sui`、`max_days`
   断言：`RentalListing.is_available == true`

2. 成功租用
   输入：`days` 在允许范围内，付款金额 `>= total_cost`
   断言：
   - `current_renter` 被写入
   - `lease_expires_ms` 大于当前时间
   - 租用者收到 `RentalPass`
   - 出租者收到 70% 租金

3. 提前归还
   输入：有效 `RentalPass`，当前时间小于 `expires_ms`
   断言：
   - `RentalListing.is_available == true`
   - 租用者按剩余天数收到退款
   - 剩余押金结转给出租者

4. 到期回收
   输入：当前时间大于 `lease_expires_ms`
   断言：
   - 出租者可执行 `reclaim_after_expiry`
   - `current_renter` 被清空

## Failure Path

1. 付款不足时租用失败
2. 超过 `max_days` 时租用失败
3. 非租用者提前归还失败
4. 未到期时出租者回收失败
