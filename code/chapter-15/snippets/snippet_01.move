module chapter_15::snippet_01;

// location.move（简化版）
public struct Location has store {
    location_hash: vector<u8>,  // 坐标的哈希，而不是明文坐标
}

/// 更新位置（需要游戏服务器签名授权）
public fun update_location(
    assembly: &mut Assembly,
    new_location_hash: vector<u8>,
    admin_acl: &AdminACL,  // 必须由授权服务器作为赞助者
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    assembly.location.location_hash = new_location_hash;
}
