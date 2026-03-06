module chapter_23::snippet_01;

// 结算时：平台费 + Builder 费双层结构
public fun settle_sale(
    market: &mut Market,
    sale_price: u64,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
): Coin<SUI> {
    // 1. 平台协议费（EVE Frontier 官方，如果有的话）
    let protocol_fee = sale_price * market.protocol_fee_bps / 10_000;

    // 2. 你的 Builder 费
    let builder_fee = sale_price * market.builder_fee_bps / 10_000;    // 例：200 = 2%

    // 3. 剩余给卖家
    let seller_amount = sale_price - protocol_fee - builder_fee;

    // 分配
    transfer::public_transfer(payment.split(builder_fee, ctx), market.fee_recipient);
    // ... 协议费到官方地址，剩余给卖家

    payment // 返回 seller_amount
}
