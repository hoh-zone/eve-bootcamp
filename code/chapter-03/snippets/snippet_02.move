module chapter_03::snippet_02;

// JumpPermit：有 key + store，是真实的链上资产，不可复制
public struct JumpPermit has key, store {
    id: UID,
    character_id: ID,
    route_hash: vector<u8>,
    expires_at_timestamp_ms: u64,
}

// VendingAuth：只有 drop，是一次性的"凭证"（Witness Pattern）
public struct VendingAuth has drop {}
