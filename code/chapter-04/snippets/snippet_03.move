module chapter_04::snippet_03;

// 跳跃许可证：有时效性的链上对象
public struct JumpPermit has key, store {
    id: UID,
    character_id: ID,
    route_hash: vector<u8>,   // A↔B 双向有效
    expires_at_timestamp_ms: u64,
}
