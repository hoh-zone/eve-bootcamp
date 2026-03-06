module chapter_06::snippet_04;

// 在你的扩展合约中，维护一个操作员白名单
public struct OperatorRegistry has key {
    id: UID,
    operators: Table<address, bool>,
}

public fun delegated_action(
    registry: &OperatorRegistry,
    ctx: &TxContext,
) {
    // 验证调用者在操作员名单中
    assert!(registry.operators.contains(ctx.sender()), ENotOperator);
    // ... 执行操作
}
