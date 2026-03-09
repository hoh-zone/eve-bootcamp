// sources/toll_gate.move
module toll_gate::toll_gate_ext;

use toll_gate::treasury::{Self, TollTreasury};
use world::gate::{Self, Gate};
use world::character::Character;
use sui::coin::Coin;
use sui::sui::SUI;
use sui::clock::Clock;
use sui::tx_context::TxContext;

/// 星门扩展的 Witness 类型
public struct TollAuth has drop {}

/// 默认跳跃许可有效期：15 分钟
const PERMIT_DURATION_MS: u64 = 15 * 60 * 1000;

/// 支付通行费并获得跳跃许可
public fun pay_toll_and_get_permit(
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    treasury: &mut TollTreasury,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. 收取通行费
    treasury::deposit_toll(treasury, payment, ctx.sender());

    // 2. 计算 Permit 过期时间
    let expires_at = clock.timestamp_ms() + PERMIT_DURATION_MS;

    // 3. 向星门申请跳跃许可（TollAuth{} 是扩展凭证）
    gate::issue_jump_permit(
        source_gate,
        destination_gate,
        character,
        TollAuth {},
        expires_at,
        ctx,
    );

    // 注意：JumpPermit 对象会被自动转给 character 的 Owner
}
