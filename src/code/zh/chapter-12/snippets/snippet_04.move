module chapter_07::snippet_04;

// ❌ 不灵活的方式：固定字段
public struct Inventory has key {
    id: UID,
    fuel: Option<u64>,
    ore: Option<u64>,
    // 新增物品类型就要修改合约...
}

// ✅ 灵活的方式：动态字段
public struct Inventory has key {
    id: UID,
    // 没有预定义字段，用动态字段存储
}
