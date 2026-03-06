module chapter_11::snippet_01;

public fun verify_sponsor(admin_acl: &AdminACL, ctx: &TxContext) {
    // tx_context::sponsor() 返回 Gas 付款人的地址
    let sponsor = ctx.sponsor().unwrap(); // 如果没有 sponsor 则 abort
    assert!(
        vector::contains(&admin_acl.sponsors, &sponsor),
        EUnauthorizedSponsor,
    );
}
