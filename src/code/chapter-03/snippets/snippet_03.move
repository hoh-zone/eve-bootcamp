module chapter_03::snippet_03;

use std::string::String;

public struct TenantItemId has copy, drop, store {
    item_id: u64,          // 游戏内的唯一 ID
    tenant: String,        // 区分不同游戏服务器实例
}
