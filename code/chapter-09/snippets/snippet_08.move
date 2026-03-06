module chapter_09::snippet_08;

// v1：旧版存储结构
public struct MarketV1 has key {
    id: UID,
    price: u64,
}

// v2：新版增加字段（不能直接修改 V1）
// 改为用动态字段扩展
public fun get_expiry_v2(market: &MarketV1): Option<u64> {
    if df::exists_(&market.id, b"expiry") {
        option::some(*df::borrow<vector<u8>, u64>(&market.id, b"expiry"))
    } else {
        option::none()
    }
}

// 给旧对象添加新字段（迁移脚本）
public entry fun migrate_add_expiry(
    market: &mut MarketV1,
    expiry_ms: u64,
    ctx: &mut TxContext,
) {
    df::add(&mut market.id, b"expiry", expiry_ms);
}
