module quest_system::quest_gate;

use quest_system::registry::{Self, QuestRegistry};
use world::gate::{Self, Gate};
use world::character::Character;
use sui::clock::Clock;
use sui::tx_context::TxContext;

/// 星门扩展 Witness
public struct QuestGateAuth has drop {}

/// 任务完成后申请跳跃许可
public entry fun quest_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    quest_registry: &QuestRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 验证调用者已完成所有任务
    assert!(
        registry::is_all_complete(quest_registry, ctx.sender()),
        EQuestsNotComplete,
    );

    // 签发跳跃许可（有效期 30 分钟）
    let expires_at = clock.timestamp_ms() + 30 * 60 * 1000;

    gate::issue_jump_permit(
        source_gate,
        dest_gate,
        character,
        QuestGateAuth {},
        expires_at,
        ctx,
    );
}

const EQuestsNotComplete: u64 = 0;
