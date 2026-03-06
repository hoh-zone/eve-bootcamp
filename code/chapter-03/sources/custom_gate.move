// Builder 在自己的包中定义一个 Witness 类型
module my_extension::custom_gate {
    // 只有这个模块能创建 Auth 实例（因为它没有公开构造函数）
    public struct Auth has drop {}

    // 调用星门 API 时，把 Auth {} 作为凭证传入
    public entry fun request_jump(
        gate: &mut Gate,
        character: &Character,
        ctx: &mut TxContext,
    ) {
        // 自定义逻辑（例如检查费用）
        // ...

        // 用 Auth {} 证明调用来自这个已授权的模块
        gate::issue_jump_permit(
            gate, destination, character,
            Auth {},      // Witness：证明我是 my_extension::custom_gate
            expires_at,
            ctx,
        )
    }
}
