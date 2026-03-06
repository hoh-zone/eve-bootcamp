module chapter_04::snippet_04;

// 注册扩展
public fun authorize_extension<Auth: drop>(
    gate: &mut Gate,
    owner_cap: &OwnerCap<Gate>,
)

// 发放跳跃许可（只有已注册的 Auth 类型才能调用）
public fun issue_jump_permit<Auth: drop>(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    _auth: Auth,
    expires_at_timestamp_ms: u64,
    ctx: &mut TxContext,
)

// 使用许可跳跃（消耗 JumpPermit）
public fun jump_with_permit(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    jump_permit: JumpPermit,
    admin_acl: &AdminACL,
    clock: &Clock,
    ctx: &mut TxContext,
)
