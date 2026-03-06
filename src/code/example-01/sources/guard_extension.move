// sources/guard_extension.move
module mining_guard::guard_extension;

use mining_guard::mining_pass::{Self, MiningPass};
use world::turret::{Self, Turret};
use world::character::Character;
use sui::tx_context::TxContext;

/// 炮塔扩展的 Witness 类型
public struct GuardAuth has drop {}

/// 受保护的矿区 ID（这个版本保护 zone 1）
const PROTECTED_ZONE_ID: u64 = 1;

/// 请求安全通行（玩家持有通行证则被炮塔放过）
/// 
/// 注意：实际炮塔的"不开火"逻辑由游戏服务器执行，
/// 这里的合约用于验证和记录许可意图
public entry fun request_safe_passage(
    turret: &mut Turret,
    character: &Character,
    pass: &MiningPass,           // 必须持有通行证
    ctx: &mut TxContext,
) {
    // 验证通行证属于正确的矿区
    assert!(
        mining_pass::is_valid_for_zone(pass, PROTECTED_ZONE_ID),
        0  // 错误码：无效的矿区通行证
    );

    // 调用炮塔的安全通行函数，传入 GuardAuth{} 作为扩展凭证
    // （实际 API 以世界合约为准）
    turret::grant_safe_passage(
        turret,
        character,
        GuardAuth {},
        ctx,
    );
}
