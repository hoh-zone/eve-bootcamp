module chapter_14::snippet_06;

// 默认：任何人都可以转让（public_transfer）
transfer::public_transfer(badge, recipient);

// 锁仓：NFT 只能由特定合约转移（通过 TransferPolicy）
use sui::transfer_policy;

// 在包初始化时建立 TransferPolicy（限制转让条件）
fun init(witness: SPACE_BADGE, ctx: &mut TxContext) {
    let publisher = package::claim(witness, ctx);
    let (policy, policy_cap) = transfer_policy::new<SpaceBadge>(&publisher, ctx);

    // 添加自定义规则（如需支付版税）
    // royalty_rule::add(&mut policy, &policy_cap, 200, 0); // 2% 版税

    transfer::public_share_object(policy);
    transfer::public_transfer(policy_cap, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}
