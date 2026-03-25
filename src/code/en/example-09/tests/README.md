# Example 9 Test Matrix

## Happy Path

1. 适配器统一返回市场报价
2. 聚合层能选出最低价市场
3. 前端按统一接口发起购买

## Failure Path

1. 某个 Builder 市场接口变更后适配器立即报错
2. 单个市场查询失败不应拖垮全局报价
3. 聚合层返回价格和实际执行价格不一致
