module chapter_15::snippet_02;

// 星门链接时的距离Verify
public fun link_gates(
    gate_a: &mut Gate,
    gate_b: &mut Gate,
    owner_cap_a: &OwnerCap<Gate>,
    distance_proof: vector<u8>,  // 服务器签名的"两门距离 > 20km"证明
    admin_acl: &AdminACL,
    ctx: &TxContext,
) {
    // Verify服务器签名（简化；实际实现Verify ed25519 签名）
    verify_sponsor(admin_acl, ctx);
    // ...
}
