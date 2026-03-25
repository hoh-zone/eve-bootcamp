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
