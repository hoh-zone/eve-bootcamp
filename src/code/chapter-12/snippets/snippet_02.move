module chapter_07::snippet_02;

// T 没有实际被使用，但创造了类型区分
public struct OwnerCap<phantom T> has key {
    id: UID,
    authorized_object_id: ID,
}

// 这两个是完全不同的类型，系统不会混淆
let gate_cap: OwnerCap<Gate> = ...;
let ssu_cap: OwnerCap<StorageUnit> = ...;
