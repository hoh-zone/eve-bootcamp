module chapter_07::snippet_06;

// 为特定角色创建临时仓库（以角色 OwnerCap ID 为 key）
df::add(
    &mut storage_unit.id,
    owner_cap_id,      // 用角色的 OwnerCap ID 作为 key
    EphemeralInventory::new(ctx),
);

// 角色访问自己的临时仓库
let my_inventory = df::borrow_mut<ID, EphemeralInventory>(
    &mut storage_unit.id,
    my_owner_cap_id,
);
