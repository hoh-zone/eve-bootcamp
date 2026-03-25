# Example 18 Test Matrix

本目录用于约束 `treaty.move` 的最小验收范围。条约案例的关键不是 UI，而是状态机与押金流的正确性。

## Happy Path

1. 发起条约提案
   断言：共享 `TreatyProposal` 创建成功，事件正确发出

2. 发起方接受并签署
   断言：
   - 共享 `Treaty` 创建成功
   - `party_a_signed == true`
   - `party_a_deposit` 写入成功

3. 对方联盟复签生效
   断言：
   - `party_b_signed == true`
   - `effective_at_ms` 写入
   - 条约进入 active 状态

4. 提前通知并终止
   断言：
   - `termination_notice_ms` 写入
   - 满足通知期后押金退回双方

5. 举报违约并扣罚
   输入：有效服务器证明 + 明确的违约方
   断言：
   - 对应 `breach_count_*` 自增
   - 违约罚款从押金扣出并转给对方

## Failure Path

1. 非参与方签署失败
2. 押金不足时签署失败
3. 未到通知期终止失败
4. 非参与方被举报时失败
5. 押金不足时不应发生负余额
