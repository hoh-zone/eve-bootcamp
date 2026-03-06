module chapter_03::snippet_04;

public struct StorageUnit has key, store {
    id: UID,
}

public struct Item has key, store {
    id: UID,
}

// 定义能力对象
public struct OwnerCap<phantom T> has key, store {
    id: UID,
}

// 需要 OwnerCap 才能调用的函数
public fun withdraw_by_owner<T: key>(
    _storage_unit: &mut StorageUnit,
    _owner_cap: &OwnerCap<T>,  // 必须持有此凭证
    _ctx: &mut TxContext,
): Item {
    abort 0
}
