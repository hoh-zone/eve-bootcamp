module chapter_20::snippet_03;

// 未来：费率参数由 DAO 投票决定
public entry fun update_energy_cost_via_dao(
    new_cost: u64,
    dao_proposal: &ExecutedProposal,  // 已通过的 DAO 提案凭证
    energy_config: &mut EnergyConfig,
) {
    // 验证提案已通过且未过期
    dao::verify_executed_proposal(dao_proposal);
    energy_config.update_cost(new_cost);
}
