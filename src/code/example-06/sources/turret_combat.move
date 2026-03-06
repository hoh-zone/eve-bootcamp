module dynamic_nft::turret_combat;

use dynamic_nft::plasma_rifle::{Self, PlasmaRifle};
use world::turret::{Self, Turret};
use world::character::Character;

public struct CombatAuth has drop {}

/// 炮塔击杀事件（炮塔扩展调用）
public entry fun on_kill(
    turret: &Turret,
    killer: &Character,
    weapon: &mut PlasmaRifle,       // 玩家使用的武器
    ctx: &TxContext,
) {
    // 验证是合法的炮塔扩展调用（需要 CombatAuth）
    turret::verify_extension(turret, CombatAuth {});

    // 记录击杀到武器
    plasma_rifle::record_kill(weapon, ctx);
}
