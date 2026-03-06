module chapter_15::snippet_03;

// 资产只在特定位置哈希处有效
public entry fun claim_resource(
    claim: &mut ResourceClaim,
    claimant_location_hash: vector<u8>,  // 服务器证明的位置
    admin_acl: &AdminACL,
    ctx: &mut TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    // 验证玩家位置哈希与资源点匹配
    assert!(
        claimant_location_hash == claim.required_location_hash,
        EWrongLocation,
    );
    // 发放资源
}
