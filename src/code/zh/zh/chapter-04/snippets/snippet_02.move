module chapter_04::snippet_02;

// 1. 注册扩展（Owner 调用）
public fun authorize_extension<Auth: drop>(
    storage_unit: &mut StorageUnit,
    owner_cap: &OwnerCap<StorageUnit>,
)

// 2. 扩展存入物品
public fun deposit_item<Auth: drop>(
    storage_unit: &mut StorageUnit,
    character: &Character,
    item: Item,
    _auth: Auth,           // Witness
    ctx: &mut TxContext,
)

// 3. 扩展取出物品
public fun withdraw_item<Auth: drop>(
    storage_unit: &mut StorageUnit,
    character: &Character,
    _auth: Auth,           // Witness
    type_id: u64,
    ctx: &mut TxContext,
): Item
