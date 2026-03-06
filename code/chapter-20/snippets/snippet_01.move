module chapter_20::snippet_01;

// 现在：用 AdminACL 验证服务器签名
public fun jump(
    gate: &Gate,
    admin_acl: &AdminACL,   // 现在：验证服务器赞助
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);  // 检查服务器在授权列表
}

// 未来（ZK 时代）：替换验证逻辑，业务代码不变
public fun jump(
    gate: &Gate,
    proximity_proof: vector<u8>,    // 换成 ZK 证明
    proof_inputs: vector<u8>,       // 公开输入（位置哈希、距离阈值）
    verifier: &ZkVerifier,          // Sui 的 ZK 验证合约
    ctx: &TxContext,
) {
    // 同一链上验证 ZK 证明
    zk_verifier::verify_proof(verifier, proximity_proof, proof_inputs);
}
