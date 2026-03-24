# Example 10 Test Matrix

## Happy Path

1. 势力 NFT 发放成功
2. 星门与炮塔按势力规则工作
3. 采矿奖励与 WAR Token 发放成功
4. 资源刷新后前端可见

## Failure Path

1. 非势力成员无法通过对应星门
2. 资源不足时仍发奖励应被阻止
3. 多模块状态更新未放进同一事务时应暴露不一致
