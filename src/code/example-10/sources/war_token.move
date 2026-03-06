module war_game::war_token;

/// WAR Token（标准 Coin 设计，参考 Chapter 8）
public struct WAR_TOKEN has drop {}

fun init(witness: WAR_TOKEN, ctx: &mut TxContext) {
    let (treasury, metadata) = sui::coin::create_currency(
        witness, 6, b"WAR", b"War Token",
        b"Earned through combat and mining in the Space Resource War",
        option::none(), ctx,
    );
    transfer::public_transfer(treasury, ctx.sender());
    transfer::public_freeze_object(metadata);
}
