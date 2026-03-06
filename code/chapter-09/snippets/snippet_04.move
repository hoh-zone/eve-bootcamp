module chapter_09::snippet_04;

// ❌ 危险：OwnerCap 没有验证对应的对象 ID
public fun admin_action(vault: &mut Vault, _cap: &OwnerCap) {
    // 任何 OwnerCap 都能控制任何 Vault！
}

// ✅ 安全：验证 OwnerCap 和对象的绑定关系
public fun admin_action(vault: &mut Vault, cap: &OwnerCap) {
    assert!(cap.authorized_object_id == object::id(vault), ECapMismatch);
    // ...
}
