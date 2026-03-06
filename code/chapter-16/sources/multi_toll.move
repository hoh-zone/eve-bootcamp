module platform::multi_toll;

use sui::table::{Self, Table};
use sui::object::{Self, ID};

/// 平台注册表（共享对象，所有租户共用）
public struct TollPlatform has key {
    id: UID,
    registrations: Table<ID, TollConfig>,  // gate_id → 收费配置
}

/// 每个租户（星门）的独立配置
public struct TollConfig has store {
    owner: address,          // 这个配置的 Owner（星门拥有者）
    toll_amount: u64,
    fee_recipient: address,
    total_collected: u64,
}

/// 租户注册（任意 Builder 都可以把自己的星门注册进来）
public entry fun register_gate(
    platform: &mut TollPlatform,
    gate: &Gate,
    owner_cap: &OwnerCap<Gate>,          // 证明你是这个星门的 Owner
    toll_amount: u64,
    fee_recipient: address,
    ctx: &TxContext,
) {
    // 验证 OwnerCap 和 Gate 对应
    assert!(owner_cap.authorized_object_id == object::id(gate), ECapMismatch);

    let gate_id = object::id(gate);
    assert!(!table::contains(&platform.registrations, gate_id), EAlreadyRegistered);

    table::add(&mut platform.registrations, gate_id, TollConfig {
        owner: ctx.sender(),
        toll_amount,
        fee_recipient,
        total_collected: 0,
    });
}

/// 调整租户配置（只有自己的配置才能修改）
public entry fun update_toll(
    platform: &mut TollPlatform,
    gate: &Gate,
    owner_cap: &OwnerCap<Gate>,
    new_toll_amount: u64,
    ctx: &TxContext,
) {
    assert!(owner_cap.authorized_object_id == object::id(gate), ECapMismatch);

    let config = table::borrow_mut(&mut platform.registrations, object::id(gate));
    assert!(config.owner == ctx.sender(), ENotConfigOwner);

    config.toll_amount = new_toll_amount;
}

/// 多租户跳跃（收费逻辑复用，但配置各自独立）
public entry fun multi_tenant_jump(
    platform: &mut TollPlatform,
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 读取该星门的专属收费配置
    let gate_id = object::id(source_gate);
    assert!(table::contains(&platform.registrations, gate_id), EGateNotRegistered);

    let config = table::borrow_mut(&mut platform.registrations, gate_id);
    assert!(coin::value(&payment) >= config.toll_amount, EInsufficientPayment);

    // 转给各自的 fee_recipient
    let toll = payment.split(config.toll_amount, ctx);
    transfer::public_transfer(toll, config.fee_recipient);
    config.total_collected = config.total_collected + config.toll_amount;

    // 还回找零
    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    // 发放跳跃许可
    gate::issue_jump_permit(
        source_gate, dest_gate, character, MultiTollAuth {}, clock.timestamp_ms() + 15 * 60 * 1000, ctx,
    );
}

public struct MultiTollAuth has drop {}
const ECapMismatch: u64 = 0;
const EAlreadyRegistered: u64 = 1;
const ENotConfigOwner: u64 = 2;
const EGateNotRegistered: u64 = 3;
const EInsufficientPayment: u64 = 4;
