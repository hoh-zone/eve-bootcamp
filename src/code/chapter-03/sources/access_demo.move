module example::access_demo {

    // 私有函数：只能在本模块内调用
    fun internal_logic() { }

    // 包内可见：同一个包的其他模块可调用（Layer 1 Primitives 使用这个）
    public(package) fun package_only() { }

    // Entry：可以直接作为交易（Transaction）的顶层调用
    public entry fun user_action(ctx: &mut TxContext) { }

    // 公开：任何模块都可以调用
    public fun read_data(): u64 { 42 }
}
