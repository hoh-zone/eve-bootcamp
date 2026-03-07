module my_nft::evolving_ship;

use sui::object::{Self, UID};
use sui::transfer;
use std::string::{Self, String};

// ── 数据结构 ───────────────────────────────────────────────

/// 可进化的飞船 NFT
public struct EvolvingShip has key, store {
    id: UID,
    name: String,
    hull_class: u8,        // 0=护卫舰, 1=巡洋舰, 2=战列舰
    combat_score: u64,
    kills: u64,
    image_url: String,
}

// ── 铸造 ──────────────────────────────────────────────────

public fun mint(
    name: vector<u8>,
    recipient: address,
    ctx: &mut TxContext,
) {
    let ship = EvolvingShip {
        id: object::new(ctx),
        name: string::utf8(name),
        hull_class: 0,
        combat_score: 0,
        kills: 0,
        image_url: get_image_url(0),
    };
    transfer::public_transfer(ship, recipient);
}

// ── 战斗记录（进化触发）──────────────────────────────────

public fun record_kill(
    ship: &mut EvolvingShip,
    _ctx: &TxContext,
) {
    ship.kills = ship.kills + 1;
    ship.combat_score = ship.combat_score + 100;

    // 升级飞船等级（进化）
    if (ship.combat_score >= 10_000 && ship.hull_class < 2) {
        ship.hull_class = ship.hull_class + 1;
        ship.image_url = get_image_url(ship.hull_class);
    }
}

fun get_image_url(class: u8): String {
    if (class == 0) {
        string::utf8(b"https://assets.evefrontier.com/ships/frigate.png")
    } else if (class == 1) {
        string::utf8(b"https://assets.evefrontier.com/ships/cruiser.png")
    } else {
        string::utf8(b"https://assets.evefrontier.com/ships/battleship.png")
    }
}

// ── 读取字段 ──────────────────────────────────────────────

public fun hull_class(ship: &EvolvingShip): u8 { ship.hull_class }
public fun combat_score(ship: &EvolvingShip): u64 { ship.combat_score }
public fun kills(ship: &EvolvingShip): u64 { ship.kills }
