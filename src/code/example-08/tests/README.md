# Example 8 Test Matrix

本目录用于约束 `weekly_race.move` 的最小验收范围。该案例目前仍有链下积分聚合与服务器校验边界，因此测试目标应先聚焦在可验证的状态流。

## Happy Path

1. 创建赛事
   断言：
   - `season`、`start_time_ms`、`end_time_ms` 写入成功
   - `is_settled == false`

2. 奖池充值
   断言：
   - `prize_pool_sui` 增加
   - 非预期资产类型不会混入奖池

3. 上报积分
   断言：
   - 新玩家积分可初始化为 0 后再累加
   - 老玩家积分可持续累加
   - `ScoreUpdated` 事件正确发出

4. 结算赛事
   断言：
   - 排名顺序满足 `s1 >= s2 >= s3`
   - 奖池按 50/30/20 分配
   - `top3` 写入成功
   - 三个奖杯 NFT 被铸造

## Failure Path

1. 赛事结束后继续上报积分失败
2. 重复结算失败
3. 传入伪造前三名时结算失败
4. 奖池为空或排名数据缺失时结算失败

## 链下协作检查

1. 积分来源必须绑定具体比赛周期
2. 上报 payload 必须绑定 `race_id`、`player`、`score_delta`
3. 服务器授权与积分聚合逻辑应独立记录，不能只信任前端提交
