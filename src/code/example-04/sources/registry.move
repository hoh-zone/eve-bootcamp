module quest_system::registry;

use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::event;
use sui::tx_context::TxContext;
use sui::transfer;

/// 任务的类型（用 u8 枚举）
const QUEST_DONATE_ORE: u8 = 0;
const QUEST_LEADER_CERT: u8 = 1;

/// 任务完成状态（位标志）
/// bit 0: QUEST_DONATE_ORE 完成
/// bit 1: QUEST_LEADER_CERT 完成
const QUEST_ALL_COMPLETE: u64 = 0b11;

/// 任务注册表（共享对象）
public struct QuestRegistry has key {
    id: UID,
    gate_id: ID,                          // 对应哪个星门
    completions: Table<address, u64>,     // address → 完成标志位
}

/// 任务管理员凭证
public struct QuestAdminCap has key, store {
    id: UID,
    registry_id: ID,
}

/// 事件
public struct QuestCompleted has copy, drop {
    registry_id: ID,
    player: address,
    quest_type: u8,
    all_done: bool,
}

/// 部署：创建任务注册表
public entry fun create_registry(
    gate_id: ID,
    ctx: &mut TxContext,
) {
    let registry = QuestRegistry {
        id: object::new(ctx),
        gate_id,
        completions: table::new(ctx),
    };

    let admin_cap = QuestAdminCap {
        id: object::new(ctx),
        registry_id: object::id(&registry),
    };

    transfer::share_object(registry);
    transfer::transfer(admin_cap, ctx.sender());
}

/// 管理员标记任务完成（由联盟 Leader 或管理脚本调用）
public entry fun mark_quest_complete(
    registry: &mut QuestRegistry,
    cap: &QuestAdminCap,
    player: address,
    quest_type: u8,
    ctx: &TxContext,
) {
    assert!(cap.registry_id == object::id(registry), ECapMismatch);

    // 初始化玩家条目
    if !table::contains(&registry.completions, player) {
        table::add(&mut registry.completions, player, 0u64);
    };

    let flags = table::borrow_mut(&mut registry.completions, player);
    *flags = *flags | (1u64 << (quest_type as u64));

    let all_done = *flags == QUEST_ALL_COMPLETE;

    event::emit(QuestCompleted {
        registry_id: object::id(registry),
        player,
        quest_type,
        all_done,
    });
}

/// 查询玩家是否完成了所有任务
public fun is_all_complete(registry: &QuestRegistry, player: address): bool {
    if !table::contains(&registry.completions, player) {
        return false
    }
    *table::borrow(&registry.completions, player) == QUEST_ALL_COMPLETE
}

/// 查询玩家完成了哪些任务
public fun get_completion_flags(registry: &QuestRegistry, player: address): u64 {
    if !table::contains(&registry.completions, player) {
        return 0
    }
    *table::borrow(&registry.completions, player)
}

const ECapMismatch: u64 = 0;
