module platform::registry;

/// 全局注册表（类似域名系统）
public struct ObjectRegistry has key {
    id: UID,
    entries: Table<String, ID>,  // 名称 → ObjectID
}

/// 注册一个命名对象
public entry fun register(
    registry: &mut ObjectRegistry,
    name: vector<u8>,
    object_id: ID,
    _admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    table::add(
        &mut registry.entries,
        std::string::utf8(name),
        object_id,
    );
}

/// 查询
public fun resolve(registry: &ObjectRegistry, name: String): ID {
    *table::borrow(&registry.entries, name)
}
