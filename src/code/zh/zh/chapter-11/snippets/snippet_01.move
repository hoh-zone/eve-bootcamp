module chapter_06::snippet_01;

// 验证调用者是否为授权赞助者
public fun verify_sponsor(admin_acl: &AdminACL, ctx: &TxContext) {
    assert!(
        admin_acl.sponsors.contains(ctx.sponsor().unwrap()),
        EUnauthorizedSponsor
    );
}
