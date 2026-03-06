# Chapter 9：测试、调试与安全审计

> **目标：** 能为 Move 合约编写完整的单元测试，识别常见安全漏洞，制定合约升级策略。

---

> 状态：工程保障章节。正文以测试、安全与升级风险控制为主。

## 9.1 为什么安全测试至关重要？

链上合约一旦部署，资产是真实的。以下是常见损失场景：
- 价格计算溢出，导致物品以 0 价格出售
- 权限检查遗漏，任何人都能调用 "仅 Owner" 函数
- 可重入漏洞（在 Move 中较少见但仍需关注）
- 升级失误导致旧数据无法被新合约读取

**防御策略：** 先测试，再发布。

这里最值得建立的观念不是“测试很重要”这种空话，而是：

> 链上合约测试的目标，不是证明它能跑，而是证明它在错误输入、错误顺序、错误权限下也不会失控。

很多初学者写测试，只会验证“正常路径成功”。但真实资产损失通常来自另外三类路径：

- 本来就不该成功的调用却成功了
- 边界值输入让系统进入异常状态
- 升级或维护后，旧对象与新逻辑不再兼容

所以对 Builder 来说，测试不是收尾工作，而是设计工作的一部分。

---

## 9.2 Move 单元测试基础

Move 内置了测试框架，测试代码写在同一个 `.move` 文件中，用 `#[test]` 注解标记：

```move
module my_package::my_module;

// ... 正常合约代码 ...

// 测试模块：只在 test 环境编译
#[test_only]
module my_package::my_module_tests;

use my_package::my_module;
use sui::test_scenario::{Self, Scenario};
use sui::coin;
use sui::sui::SUI;
use sui::clock;

// ── 基础测试 ─────────────────────────────────────────────

#[test]
fun test_deposit_and_withdraw() {
    // 初始化测试场景（模拟区块链状态）
    let mut scenario = test_scenario::begin(@0xALICE);

    // 测试步骤 1：Alice 部署合约
    {
        let ctx = scenario.ctx();
        my_module::init_for_testing(ctx);  // 测试专用 init
    };

    // 测试步骤 2：Alice 存入物品
    scenario.next_tx(@0xALICE);
    {
        let mut vault = scenario.take_shared<my_module::Vault>();
        let ctx = scenario.ctx();

        my_module::deposit(&mut vault, 100, ctx);
        assert!(my_module::balance(&vault) == 100, 0);

        test_scenario::return_shared(vault);
    };

    // 测试步骤 3：Bob 尝试取款（应该失败）
    scenario.next_tx(@0xBOB);
    {
        let mut vault = scenario.take_shared<my_module::Vault>();
        // 期望这个调用会失败（abort）
        // 用 #[test, expected_failure] 测试失败路径
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// ── 测试失败路径 ────────────────────────────────────────

#[test]
#[expected_failure(abort_code = my_module::ENotOwner)]
fun test_unauthorized_withdraw_fails() {
    let mut scenario = test_scenario::begin(@0xALICE);

    // 部署
    { my_module::init_for_testing(scenario.ctx()); };

    // Bob 尝试以 Alice 身份操作（应 abort）
    scenario.next_tx(@0xBOB);
    {
        let mut vault = scenario.take_shared<my_module::Vault>();
        my_module::owner_withdraw(&mut vault, scenario.ctx()); // 应 abort
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// ── 使用 Clock 测试时间相关逻辑 ─────────────────────────

#[test]
fun test_time_based_pricing() {
    let mut scenario = test_scenario::begin(@0xALICE);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 设置当前时间
    clock.set_for_testing(1_000_000);

    {
        let price = my_module::get_dutch_price(
            1000,  // 起始价
            100,   // 最低价
            0,     // 开始时间
            2_000_000,  // 持续时间（2秒）
            &clock,
        );
        // 经过一半时间，价格应为中间值
        assert!(price == 550, 0);
    };

    clock.destroy_for_testing();
    scenario.end();
}
```

运行测试：
```bash
# 运行所有测试
sui move test

# 只运行特定测试
sui move test test_deposit_and_withdraw

# 显示详细输出
sui move test --verbose
```

### 写测试时，先分四类场景

一个实用的测试分层是：

1. **正常路径**
   合法输入下，系统是否按预期完成
2. **权限失败路径**
   没有权限时，是否稳定 abort
3. **边界值路径**
   0、最大值、过期、空集合、最后一个条目等情况是否正确
4. **状态演进路径**
   做完一步后，再做下一步，系统是否仍然一致

如果你的测试只有第一类，那其实还不够叫“有测试”。

### `test_scenario` 真正适合拿来干什么？

它最适合模拟：

- 多个地址轮流发起交易
- 共享对象在多笔交易里的状态变化
- 时间推进后的行为变化
- 对象创建、取回、归还的完整生命周期

这恰好就是 EVE Builder 项目最常见的风险集中区。

### 测试不是越细碎越好

有些测试太碎，最后只证明“小函数按字面工作”，却没有覆盖真正的业务闭环。

更有价值的做法通常是：

- 保留少量关键单元测试
- 再写几条端到端业务场景测试

例如租赁系统里，比起只测 `calc_refund()`，更重要的是测：

1. 创建挂单
2. 成功租用
3. 提前归还
4. 到期回收

这条完整链路是否闭合。

---

## 9.3 常见安全漏洞与防御

### 漏洞一：整数溢出/下溢

```move
// ❌ 危险：u64 减法下溢会 abort，但如果逻辑错误可能算出极大值
fun unsafe_calc(a: u64, b: u64): u64 {
    a - b  // 如果 b > a，直接 abort（Move 会检查）
}

// ✅ 安全：在操作前检查
fun safe_calc(a: u64, b: u64): u64 {
    assert!(a >= b, EInsufficientBalance);
    a - b
}

// ✅ 对于有意允许的下溢，使用检查后的计算
fun safe_pct(total: u64, bps: u64): u64 {
    // bps 最大 10000，防止 total * bps 溢出
    assert!(bps <= 10_000, EInvalidBPS);
    total * bps / 10_000  // Move u64 最大 1.8e19，需要注意大数
}
```

> ✅ **Move 的优势**：Move 默认会检查 u64 运算溢出，溢出时 abort 而不是静默返回错误值（不同于 Solidity 早期版本）。

但要注意，Move 帮你解决的是“机器级溢出安全”，不是“业务数学正确”。

比如下面这些问题，类型系统并不会替你思考：

- 手续费是否应该先算再扣，还是先扣再算分润
- 百分比是否该向下取整还是四舍五入
- 多地址分账后余数应该留在金库还是返给用户

很多经济 bug 最后不是“黑客级漏洞”，而是结算口径本身设计错了。

### 漏洞二：权限检查遗漏

```move
// ❌ 危险：没有验证调用者
public fun withdraw_all(treasury: &mut Treasury, ctx: &mut TxContext) {
    let all = coin::take(&mut treasury.balance, balance::value(&treasury.balance), ctx);
    transfer::public_transfer(all, ctx.sender()); // 任何人都能取走资金！
}

// ✅ 安全：要求 OwnerCap
public fun withdraw_all(
    treasury: &mut Treasury,
    _cap: &TreasuryOwnerCap,  // 检查调用者持有 OwnerCap
    ctx: &mut TxContext,
) {
    let all = coin::take(&mut treasury.balance, balance::value(&treasury.balance), ctx);
    transfer::public_transfer(all, ctx.sender());
}
```

权限检查里最容易犯的错，是只验证“某种权限存在”，却没验证：

- 这张权限是不是这个对象的
- 这笔调用是不是当前场景允许的
- 这张权限是不是应该只在某一时段或某一路径里使用

### 漏洞三：Capability 未正确绑定

```move
// ❌ 危险：OwnerCap 没有验证对应的对象 ID
public fun admin_action(vault: &mut Vault, _cap: &OwnerCap) {
    // 任何 OwnerCap 都能控制任何 Vault！
}

// ✅ 安全：验证 OwnerCap 和对象的绑定关系
public fun admin_action(vault: &mut Vault, cap: &OwnerCap) {
    assert!(cap.authorized_object_id == object::id(vault), ECapMismatch);
    // ...
}
```

### 漏洞四：时间戳操控

```move
// ❌ 不推荐：直接依赖 ctx.epoch() 作为精确时间
// epoch 的粒度是约 24 小时，不适合细粒度时效

// ✅ 推荐：使用 Clock 对象
public fun check_expiry(expiry_ms: u64, clock: &Clock): bool {
    clock.timestamp_ms() < expiry_ms
}
```

### 漏洞五：共享对象的竞态条件

共享对象可以被多个交易并发访问。当多个交易同时抢购同一物品时：

```move
// ❌ 有竞态问题：两个交易可能同时通过检查
public fun buy_item(market: &mut Market, ...) {
    let listing = table::borrow(&market.listings, item_type_id);
    assert!(listing.amount > 0, EOutOfStock);
    // ← 另一个 TX 可能在这里同时通过同样的检查
    // ... 然后两个都执行购买，导致超卖
}

// ✅ Sui 的解决方案：通过对共享对象的写锁确保序列化
// Sui 的 Move 执行器保证：写同一个共享对象的交易是顺序执行的
// 所以上面的代码在 Sui 上实际是安全的！但要确保你的逻辑正确处理负库存
public fun buy_item(market: &mut Market, ...) {
    // 这次检查是原子的，其他 TX 会等待
    assert!(table::contains(&market.listings, item_type_id), ENotListed);
    let listing = table::remove(&mut market.listings, item_type_id);  // 原子移除
    // ...
}
```

虽然 Sui 会对共享对象写入做顺序化，但这不代表你就可以忽略业务竞态。

你仍然要测试：

- 同一商品被连续快速购买
- 一个对象被先下架再购买
- 价格更新与购买在相邻交易发生时的表现

也就是说，底层执行器帮你解决了一部分并发安全，但没有替你设计完整业务一致性。

---

## 9.4 使用 Move Prover 进行形式验证

Move Prover 是一个形式化验证工具，可以数学证明某些属性永远成立：

```move
// spec 块：形式规范
spec fun total_supply_conserved(treasury: TreasuryCap<TOKEN>): bool {
    // 声明：铸造后总供应量增加的精确量
    ensures result == old(total_supply(treasury)) + amount;
}

#[verify_only]
spec module {
    // 不变量：金库余额永远不超过某个上限
    invariant forall vault: Vault:
        balance::value(vault.balance) <= MAX_VAULT_SIZE;
}
```

运行验证：
```bash
sui move prove
```

### Move Prover 什么时候值得上？

并不是所有项目都需要一开始就做形式验证。更实际的策略通常是：

- 普通案例和中小项目：先把单测和失败路径覆盖做好
- 高价值金库、清算、权限系统：再引入 Prover 证明关键不变量

最适合用 Prover 的地方通常包括：

- 总量守恒
- 余额不会为负
- 某类权限不能越权
- 某个状态机不会跳非法状态

---

## 9.5 合约升级策略

Move 包一旦发布是**不可变的**，但可以通过升级机制发布新版本：

```bash
# 首次发布
sui client publish 
# 得到 UpgradeCap 对象（升级权凭证）

# 升级（需要 UpgradeCap）
sui client upgrade \
  --upgrade-capability <UPGRADE_CAP_ID> \

```

### 升级兼容性规则

| 变更类型 | 是否允许 |
|---------|---------|
| 添加新函数 | ✅ 允许 |
| 添加新模块 | ✅ 允许 |
| 修改函数逻辑（不变签名） | ✅ 允许 |
| 修改函数签名 | ❌ 不允许 |
| 删除函数 | ❌ 不允许 |
| 修改结构体字段 | ❌ 不允许 |
| 添加结构体字段 | ❌ 不允许 |

### 升级真正难的不是命令，而是数据继续活着

很多人第一次做升级，会把重点放在“怎么发新包”。但用户真正关心的是：

- 旧对象还能不能继续用
- 旧前端还能不能读
- 旧事件和新对象如何一起解释

也就是说，升级本质上是在维护一个还在运行的系统，而不是重新开服。

### 升级前必须问的四个问题

1. 旧对象是否还能被新版本安全读取？
2. 新版本是否要求额外迁移脚本？
3. 前端是不是要同步更新字段解析？
4. 一旦升级后发现问题，有没有回滚或止损路径？

### 数据迁移模式

当需要改变数据结构时，使用"新旧并存"策略：

```move
// v1：旧版存储结构
public struct MarketV1 has key {
    id: UID,
    price: u64,
}

// v2：新版增加字段（不能直接修改 V1）
// 改为用动态字段扩展
public fun get_expiry_v2(market: &MarketV1): Option<u64> {
    if df::exists_(&market.id, b"expiry") {
        option::some(*df::borrow<vector<u8>, u64>(&market.id, b"expiry"))
    } else {
        option::none()
    }
}

// 给旧对象添加新字段（迁移脚本）
public entry fun migrate_add_expiry(
    market: &mut MarketV1,
    expiry_ms: u64,
    ctx: &mut TxContext,
) {
    df::add(&mut market.id, b"expiry", expiry_ms);
}
```

---

## 9.6 EVE Frontier 特有的安全限制

引用官方文档中的关键约束：

| 约束 | 详情 |
|------|------|
| **对象大小** | Move 对象最大 250KB |
| **动态字段** | 单次交易最多访问 1024 个 |
| **结构体字段** | 单个结构体最多 32 个字段 |
| **交易计算上限** | 超出计算限制会直接 abort |
| **某些 Admin 操作** | 仅限游戏服务器签名 |

这些限制不要只当成“文档知识点”。它们会直接影响你的建模方式。

例如：

- 对象有大小上限，你就不能把所有状态塞进一个巨物对象
- 动态字段有访问上限，你就不能假设一笔交易能扫完整个市场
- 某些操作依赖服务器签名，你就不能把系统设计成纯用户自驱

---

## 9.7 安全清单

在发布合约前，逐项检查：

```
权限控制
✅ 所有写函数是否都有权限验证？
✅ OwnerCap 是否验证了 authorized_object_id？
✅ AdminACL 保护的函数是否有赞助者验证？

数学运算
✅ 所有乘法是否可能溢出？（u64 最大约 1.8 × 10^19）
✅ 百分比计算是否用 bps（基点）避免精度丢失？
✅ 减法操作前是否检查了 a >= b？

状态一致性
✅ 存入和取出逻辑是否完全对称？
✅ 热土豆对象是否总是被消耗？
✅ 共享对象的原子操作是否正确？

升级兼容
✅ 有没有规划 UpgradeCap 的安全存储？
✅ 是否设计了未来的数据迁移路径？

测试覆盖
✅ 是否测试了正常路径？
✅ 是否测试了所有 assert 失败路径？
✅ 是否测试了边界值（0、最大值）？
```

### 更实用的排查顺序

每次准备发布前，建议按这个顺序过一遍：

1. **权限**
   谁能调、调谁、调完会改什么
2. **钱**
   钱从哪来，到哪去，中途有没有可能丢
3. **状态**
   成功和失败后，对象是否仍保持一致
4. **升级**
   现在这版如果以后要改，会不会把自己锁死

这比纯粹照 checklist 打勾更有用，因为它逼你按真正的风险面重新审视设计。

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| Move 测试框架 | `test_scenario`、`#[test]`、`#[expected_failure]` |
| 溢出安全 | Move 默认检查，但要正确处理逻辑错误 |
| 权限检查 | 所有写操作必须验证 Capability + object_id 绑定 |
| 竞态条件 | Sui 写共享对象是顺序执行的，原子操作是安全的 |
| 合约升级 | UpgradeCap + 兼容性规则 + 动态字段迁移 |
| EVE Frontier 约束 | 250KB 对象，1024 动态字段/tx，32 个结构体字段 |

## 📚 延伸阅读

- [Builder 约束文档](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
- [Move Prover](https://move-language.github.io/move/prover/prover-guide.html)
- [Sui Package 升级指南](https://docs.sui.io/guides/developer/packages/upgrade)
- [Move 测试框架](https://docs.sui.io/guides/developer/first-app/write-package#testing-with-sui-move)
