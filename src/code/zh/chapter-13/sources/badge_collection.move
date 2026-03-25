module my_nft::badge_collection;

use sui::object::{Self, UID, ID};
use sui::transfer;
use std::string::String;

// ── 错误码 ────────────────────────────────────────────────
const ENotAdmin: u64 = 0;
const ESoldOut: u64 = 1;

// ── 数据结构 ───────────────────────────────────────────────

/// 勋章系列集合（元对象，描述这个 NFT 系列）
public struct BadgeCollection has key {
    id: UID,
    name: String,
    total_supply: u64,
    minted_count: u64,
    admin: address,
}

public struct NFTAttribute has store, copy, drop {
    trait_type: String,
    value: String,
}

/// 单个勋章
public struct AllianceBadge has key, store {
    id: UID,
    collection_id: ID,
    serial_number: u64,
    tier: u8,
    attributes: vector<NFTAttribute>,
}

// ── 初始化集合 ────────────────────────────────────────────

public fun create_collection(
    name: vector<u8>,
    total_supply: u64,
    ctx: &mut TxContext,
) {
    let collection = BadgeCollection {
        id: object::new(ctx),
        name: std::string::utf8(name),
        total_supply,
        minted_count: 0,
        admin: ctx.sender(),
    };
    transfer::share_object(collection);
}

// ── 铸造勋章 ──────────────────────────────────────────────

public fun mint_badge(
    collection: &mut BadgeCollection,
    recipient: address,
    tier: u8,
    attributes: vector<NFTAttribute>,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == collection.admin, ENotAdmin);
    assert!(collection.minted_count < collection.total_supply, ESoldOut);

    collection.minted_count = collection.minted_count + 1;

    let badge = AllianceBadge {
        id: object::new(ctx),
        collection_id: object::id(collection),
        serial_number: collection.minted_count,
        tier,
        attributes,
    };
    transfer::public_transfer(badge, recipient);
}

// ── 辅助构造函数 ──────────────────────────────────────────

public fun make_attribute(trait_type: vector<u8>, value: vector<u8>): NFTAttribute {
    NFTAttribute {
        trait_type: std::string::utf8(trait_type),
        value: std::string::utf8(value),
    }
}
