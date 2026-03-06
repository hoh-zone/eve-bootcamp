module dynamic_nft::plasma_rifle;

use sui::object::{Self, UID};
use sui::display;
use sui::package;
use sui::transfer;
use sui::event;
use std::string::{Self, String, utf8};

// ── 一次性见证 ─────────────────────────────────────────────

public struct PLASMA_RIFLE has drop {}

// ── 武器等级常量 ───────────────────────────────────────────

const TIER_BASIC: u8 = 1;
const TIER_ELITE: u8 = 2;
const TIER_LEGENDARY: u8 = 3;

const KILLS_FOR_ELITE: u64 = 10;
const KILLS_FOR_LEGENDARY: u64 = 50;

// ── 数据结构 ───────────────────────────────────────────────

public struct PlasmaRifle has key, store {
    id: UID,
    name: String,
    tier: u8,
    kills: u64,
    damage_bonus_pct: u64,   // 伤害加成（百分比）
    image_url: String,
    description: String,
    owner_history: u64,      // 历史流通次数
}

public struct ForgeAdminCap has key, store {
    id: UID,
}

// ── 事件 ──────────────────────────────────────────────────

public struct RifleEvolved has copy, drop {
    rifle_id: ID,
    from_tier: u8,
    to_tier: u8,
    total_kills: u64,
}

// ── 初始化 ────────────────────────────────────────────────

fun init(witness: PLASMA_RIFLE, ctx: &mut TxContext) {
    let publisher = package::claim(witness, ctx);

    let keys = vector[
        utf8(b"name"),
        utf8(b"description"),
        utf8(b"image_url"),
        utf8(b"attributes"),
        utf8(b"project_url"),
    ];

    let values = vector[
        utf8(b"{name}"),
        utf8(b"{description}"),
        utf8(b"{image_url}"),
        // attributes 拼接多个字段
        utf8(b"[{\"trait_type\":\"Tier\",\"value\":\"{tier}\"},{\"trait_type\":\"Kills\",\"value\":\"{kills}\"},{\"trait_type\":\"Damage Bonus\",\"value\":\"{damage_bonus_pct}%\"}]"),
        utf8(b"https://evefrontier.com/weapons"),
    ];

    let mut display = display::new_with_fields<PlasmaRifle>(
        &publisher, keys, values, ctx,
    );
    display::update_version(&mut display);

    let admin_cap = ForgeAdminCap { id: object::new(ctx) };

    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_freeze_object(display);
    transfer::public_transfer(admin_cap, ctx.sender());
}

// ── 铸造初始武器 ──────────────────────────────────────────

public entry fun forge_rifle(
    _admin: &ForgeAdminCap,
    recipient: address,
    ctx: &mut TxContext,
) {
    let rifle = PlasmaRifle {
        id: object::new(ctx),
        name: utf8(b"Plasma Rifle Mk.1"),
        tier: TIER_BASIC,
        kills: 0,
        damage_bonus_pct: 0,
        image_url: utf8(b"https://assets.example.com/weapons/plasma_mk1.png"),
        description: utf8(b"A standard-issue plasma rifle. Prove yourself in combat."),
        owner_history: 0,
    };

    transfer::public_transfer(rifle, recipient);
}

// ── 记录击杀（炮塔扩展调用此函数）────────────────────────

public entry fun record_kill(
    rifle: &mut PlasmaRifle,
    ctx: &TxContext,
) {
    rifle.kills = rifle.kills + 1;
    check_and_evolve(rifle);
}

fun check_and_evolve(rifle: &mut PlasmaRifle) {
    let old_tier = rifle.tier;

    if rifle.kills >= KILLS_FOR_LEGENDARY && rifle.tier < TIER_LEGENDARY {
        rifle.tier = TIER_LEGENDARY;
        rifle.name = utf8(b"Plasma Rifle Mk.3 \"Inferno\"");
        rifle.damage_bonus_pct = 60;
        rifle.image_url = utf8(b"https://assets.example.com/weapons/plasma_legendary.png");
        rifle.description = utf8(b"This weapon has bathed in the fires of a thousand battles. Its plasma burns with legendary fury.");
    } else if rifle.kills >= KILLS_FOR_ELITE && rifle.tier < TIER_ELITE {
        rifle.tier = TIER_ELITE;
        rifle.name = utf8(b"Plasma Rifle Mk.2");
        rifle.damage_bonus_pct = 30;
        rifle.image_url = utf8(b"https://assets.example.com/weapons/plasma_mk2.png");
        rifle.description = utf8(b"Battle-hardened and upgraded. The plasma cells burn hotter than standard.");
    };

    if old_tier != rifle.tier {
        event::emit(RifleEvolved {
            rifle_id: object::id(rifle),
            from_tier: old_tier,
            to_tier: rifle.tier,
            total_kills: rifle.kills,
        });
    }
}

// ── 读取函数 ──────────────────────────────────────────────

public fun get_tier(rifle: &PlasmaRifle): u8 { rifle.tier }
public fun get_kills(rifle: &PlasmaRifle): u64 { rifle.kills }
public fun get_damage_bonus(rifle: &PlasmaRifle): u64 { rifle.damage_bonus_pct }

// ── 转让追踪（可选） ─────────────────────────────────────

// 如果使用 TransferPolicy，可以追踪转让次数
// 此处简化为通过事件监听实现
