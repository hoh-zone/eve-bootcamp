module chapter_15::snippet_04;

public struct BaseZone has key {
    id: UID,
    center_hash: vector<u8>,   // 基地中心位置哈希
    owner: address,
    zone_nft_ids: vector<ID>,  // 在这个区域内的友方 NFT 列表
}

// 授权组件只对在基地范围内的玩家开放
public entry fun base_service(
    zone: &BaseZone,
    service: &mut StorageUnit,
    player_in_zone_proof: vector<u8>,  // 服务器证明"玩家在基地范围内"
    admin_acl: &AdminACL,
    ctx: &mut TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    // ...提供服务
}
