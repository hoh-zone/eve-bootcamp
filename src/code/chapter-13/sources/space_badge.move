module my_nft::space_badge;

use sui::object::{Self, UID};
use sui::display;
use sui::package;
use sui::transfer;
use std::string::{Self, String};

// ── 见证 & Publisher ──────────────────────────────────────

/// 一次性见证（用于创建 Publisher）
public struct SPACE_BADGE has drop {}

// ── NFT 结构 ──────────────────────────────────────────────

public struct SpaceBadge has key, store {
    id: UID,
    name: String,
    tier: u8,           // 1=铜牌, 2=银牌, 3=金牌
    earned_at_ms: u64,
    image_url: String,
}

// ── 初始化 ────────────────────────────────────────────────

fun init(witness: SPACE_BADGE, ctx: &mut TxContext) {
    let publisher = package::claim(witness, ctx);

    // 配置 Display（链上元数据模板）
    let mut display = display::new<SpaceBadge>(&publisher, ctx);
    display.add(string::utf8(b"name"), string::utf8(b"{name}"));
    display.add(string::utf8(b"image_url"), string::utf8(b"{image_url}"));
    display.add(string::utf8(b"description"), string::utf8(b"EVE Frontier Space Badge - Tier {tier}"));
    display.update_version();

    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(display, ctx.sender());
}

// ── Mint ──────────────────────────────────────────────────

public fun mint_badge(
    recipient: address,
    name: vector<u8>,
    tier: u8,
    earned_at_ms: u64,
    ctx: &mut TxContext,
): SpaceBadge {
    let image_url = if (tier == 1) {
        string::utf8(b"https://assets.example.com/badge-bronze.png")
    } else if (tier == 2) {
        string::utf8(b"https://assets.example.com/badge-silver.png")
    } else {
        string::utf8(b"https://assets.example.com/badge-gold.png")
    };

    SpaceBadge {
        id: object::new(ctx),
        name: string::utf8(name),
        tier,
        earned_at_ms,
        image_url,
    }
}

public fun transfer_badge(badge: SpaceBadge, recipient: address) {
    transfer::public_transfer(badge, recipient);
}

// ── 读取字段 ──────────────────────────────────────────────

public fun tier(badge: &SpaceBadge): u8 { badge.tier }
public fun name(badge: &SpaceBadge): &String { &badge.name }
public fun earned_at_ms(badge: &SpaceBadge): u64 { badge.earned_at_ms }
