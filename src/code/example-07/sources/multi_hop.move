module logistics::multi_hop;

use world::gate::{Self, Gate};
use world::character::Character;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::clock::Clock;
use sui::object::{Self, ID};
use sui::event;

public struct LogisticsAuth has drop {}

/// 一次购买多跳路线
public entry fun purchase_route(
    source_gate: &Gate,
    hop1_dest: &Gate,       // 第一跳目的
    hop2_source: &Gate,     // 第二跳起点（= hop1_dest 的链接门）
    hop2_dest: &Gate,       // 第二跳目的
    character: &Character,
    mut payment: Coin<SUI>,  // 支付两跳的总费用
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 验证路线连续性：hop1_dest 和 hop2_source 必须是链接的星门
    assert!(
        gate::are_linked(hop1_dest, hop2_source),
        ERouteDiscontinuous,
    );

    // 计算并扣除每跳费用
    let hop1_toll = get_toll(source_gate);
    let hop2_toll = get_toll(hop2_source);
    let total_toll = hop1_toll + hop2_toll;

    assert!(coin::value(&payment) >= total_toll, EInsufficientPayment);

    // 退还找零
    let change = payment.split(coin::value(&payment) - total_toll, ctx);
    if coin::value(&change) > 0 {
        transfer::public_transfer(change, ctx.sender());
    } else { coin::destroy_zero(change); }

    // 发放两个 JumpPermit（1小时有效期）
    let expires = clock.timestamp_ms() + 60 * 60 * 1000;

    gate::issue_jump_permit(
        source_gate, hop1_dest, character, LogisticsAuth {}, expires, ctx,
    );
    gate::issue_jump_permit(
        hop2_source, hop2_dest, character, LogisticsAuth {}, expires, ctx,
    );

    // 扣除收费
    let hop1_coin = payment.split(hop1_toll, ctx);
    let hop2_coin = payment;
    collect_toll(source_gate, hop1_coin, ctx);
    collect_toll(hop2_source, hop2_coin, ctx);

    event::emit(RouteTicketIssued {
        character_id: object::id(character),
        gates: vector[object::id(source_gate), object::id(hop1_dest), object::id(hop2_dest)],
        total_toll,
    });
}

/// 通用 N 跳路由（接受可变长度路线）
public entry fun purchase_route_n_hops(
    gates: vector<&Gate>,          // 星门列表 [A, B, C, D, ...]
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let n = vector::length(&gates);
    assert!(n >= 2, ETooFewGates);
    assert!(n <= 6, ETooManyHops); // 防止超大交易

    // 验证路线连续性（每对相邻目的/起点必须链接）
    let mut i = 1;
    while (i < n - 1) {
        assert!(
            gate::are_linked(vector::borrow(&gates, i), vector::borrow(&gates, i)),
            ERouteDiscontinuous,
        );
        i = i + 1;
    };

    // 计算总费用
    let mut total: u64 = 0;
    let mut j = 0;
    while (j < n - 1) {
        total = total + get_toll(vector::borrow(&gates, j));
        j = j + 1;
    };

    assert!(coin::value(&payment) >= total, EInsufficientPayment);

    // 发放所有 Permit
    let expires = clock.timestamp_ms() + 60 * 60 * 1000;
    let mut k = 0;
    while (k < n - 1) {
        gate::issue_jump_permit(
            vector::borrow(&gates, k),
            vector::borrow(&gates, k + 1),
            character,
            LogisticsAuth {},
            expires,
            ctx,
        );
        k = k + 1;
    };

    // 退款找零
    let change = payment.split(coin::value(&payment) - total, ctx);
    if coin::value(&change) > 0 {
        transfer::public_transfer(change, ctx.sender());
    } else { coin::destroy_zero(change); }
    // 处理 payment 到各个星门金库...
}

fun get_toll(gate: &Gate): u64 {
    // 从星门的扩展数据读取通行费（动态字段）
    // 简化版：固定费率
    10_000_000_000 // 10 SUI
}

fun collect_toll(gate: &Gate, coin: Coin<SUI>, ctx: &TxContext) {
    // 将 coin 转到星门对应的 Treasury
    // ...
}

public struct RouteTicketIssued has copy, drop {
    character_id: ID,
    gates: vector<ID>,
    total_toll: u64,
}

const ERouteDiscontinuous: u64 = 0;
const EInsufficientPayment: u64 = 1;
const ETooFewGates: u64 = 2;
const ETooManyHops: u64 = 3;
