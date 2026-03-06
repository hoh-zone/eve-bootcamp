module chapter_09::snippet_03;

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
