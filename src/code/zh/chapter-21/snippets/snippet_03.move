module chapter_17::snippet_03;

// ❌ 浪费空间
public struct Config has key {
    id: UID,
    tier: u64,     // 只存 1-5，但占 8 字节
    status: u64,   // 只存 0-3，但占 8 字节
}

// ✅ 紧凑存储
public struct Config has key {
    id: UID,
    tier: u8,      // 只占 1 字节
    status: u8,    // 只占 1 字节
}
