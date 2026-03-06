module chapter_14::snippet_05;

// 使用 NFT 检查权限的方式
public entry fun enter_restricted_zone(
    gate: &Gate,
    character: &Character,
    badge: &AllianceBadge,   // 持有勋章才能调用
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 验证勋章等级（需要金牌才能进入）
    assert!(badge.tier >= 3, EInsufficientBadgeTier);
    // 验证勋章属于正确集合（防止伪造）
    assert!(badge.collection_id == OFFICIAL_COLLECTION_ID, EWrongCollection);
    // ...
}
