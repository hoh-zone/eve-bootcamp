module diplomacy::treaty;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::{Self, String, utf8};

// ── 常量 ──────────────────────────────────────────────────

const NOTICE_PERIOD_MS: u64 = 24 * 60 * 60 * 1000;  // 撕约提前通知 24 小时
const BREACH_FINE: u64 = 100_000_000_000;             // 违约罚款 100 SUI（从押金扣）

// 条约类型
const TREATY_CEASEFIRE: u8 = 0;       // 停火协议
const TREATY_PASSAGE: u8 = 1;         // 过路权协议
const TREATY_RESOURCE_SHARE: u8 = 2;  // 资源共享

// ── 数据结构 ───────────────────────────────────────────────

/// 外交条约（共享对象）
public struct Treaty has key {
    id: UID,
    treaty_type: u8,
    party_a: address,          // 联盟 A 的 Leader 地址
    party_b: address,          // 联盟 B 的 Leader 地址
    party_a_signed: bool,
    party_b_signed: bool,
    effective_at_ms: u64,      // 生效时间（双签后）
    expires_at_ms: u64,        // 到期时间（0 = 无限期）
    termination_notice_ms: u64, // 撕约通知时间（0 = 未通知）
    party_a_deposit: Balance<SUI>,  // A 方押金（用于违约赔偿）
    party_b_deposit: Balance<SUI>,  // B 方押金
    breach_count_a: u64,
    breach_count_b: u64,
    description: String,
}

/// 条约提案（由一方发起，等待对方签署）
public struct TreatyProposal has key {
    id: UID,
    proposed_by: address,
    counterparty: address,
    treaty_type: u8,
    duration_days: u64,        // 有效期（天），0 = 无限期
    deposit_required: u64,      // 要求各方押金
    description: String,
}

// ── 事件 ──────────────────────────────────────────────────

public struct TreatyProposed has copy, drop { proposal_id: ID, proposer: address, counterparty: address }
public struct TreatySigned has copy, drop { treaty_id: ID, party: address }
public struct TreatyEffective has copy, drop { treaty_id: ID, treaty_type: u8 }
public struct TreatyTerminated has copy, drop { treaty_id: ID, terminated_by: address }
public struct BreachReported has copy, drop { treaty_id: ID, breaching_party: address, fine: u64 }

// ── 发起条约提案 ──────────────────────────────────────────

public entry fun propose_treaty(
    counterparty: address,
    treaty_type: u8,
    duration_days: u64,
    deposit_required: u64,
    description: vector<u8>,
    ctx: &mut TxContext,
) {
    let proposal = TreatyProposal {
        id: object::new(ctx),
        proposed_by: ctx.sender(),
        counterparty,
        treaty_type,
        duration_days,
        deposit_required,
        description: utf8(description),
    };
    let proposal_id = object::id(&proposal);
    transfer::share_object(proposal);
    event::emit(TreatyProposed {
        proposal_id,
        proposer: ctx.sender(),
        counterparty,
    });
}

// ── 接受提案（发起方签署 + 押金）────────────────────────

public entry fun accept_and_sign_a(
    proposal: &TreatyProposal,
    mut deposit: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == proposal.proposed_by, ENotParty);

    let deposit_amt = coin::value(&deposit);
    assert!(deposit_amt >= proposal.deposit_required, EInsufficientDeposit);

    let deposit_coin = deposit.split(proposal.deposit_required, ctx);
    if coin::value(&deposit) > 0 {
        transfer::public_transfer(deposit, ctx.sender());
    } else { coin::destroy_zero(deposit); }

    let expires = if proposal.duration_days > 0 {
        clock.timestamp_ms() + proposal.duration_days * 86_400_000
    } else { 0 };

    let treaty = Treaty {
        id: object::new(ctx),
        treaty_type: proposal.treaty_type,
        party_a: proposal.proposed_by,
        party_b: proposal.counterparty,
        party_a_signed: true,
        party_b_signed: false,
        effective_at_ms: 0,
        expires_at_ms: expires,
        termination_notice_ms: 0,
        party_a_deposit: coin::into_balance(deposit_coin),
        party_b_deposit: balance::zero(),
        breach_count_a: 0,
        breach_count_b: 0,
        description: proposal.description,
    };
    let treaty_id = object::id(&treaty);
    transfer::share_object(treaty);
    event::emit(TreatySigned { treaty_id, party: ctx.sender() });
}

/// 对方联盟签署（条约正式生效）
public entry fun countersign(
    treaty: &mut Treaty,
    mut deposit: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == treaty.party_b, ENotParty);
    assert!(treaty.party_a_signed, ENotYetSigned);
    assert!(!treaty.party_b_signed, EAlreadySigned);

    let required = balance::value(&treaty.party_a_deposit); // 对等押金
    assert!(coin::value(&deposit) >= required, EInsufficientDeposit);

    let dep = deposit.split(required, ctx);
    balance::join(&mut treaty.party_b_deposit, coin::into_balance(dep));
    if coin::value(&deposit) > 0 {
        transfer::public_transfer(deposit, ctx.sender());
    } else { coin::destroy_zero(deposit); }

    treaty.party_b_signed = true;
    treaty.effective_at_ms = clock.timestamp_ms();

    event::emit(TreatyEffective { treaty_id: object::id(treaty), treaty_type: treaty.treaty_type });
    event::emit(TreatySigned { treaty_id: object::id(treaty), party: ctx.sender() });
}

// ── 验证条约是否生效（炮塔/星门扩展调用）───────────────

public fun is_treaty_active(treaty: &Treaty, clock: &Clock): bool {
    if !treaty.party_a_signed || !treaty.party_b_signed { return false };
    if treaty.expires_at_ms > 0 && clock.timestamp_ms() > treaty.expires_at_ms { return false };
    // 撕约通知期内，条约仍然有效
    true
}

/// 检查某地址是否在条约保护下
public fun is_protected_by_treaty(
    treaty: &Treaty,
    protected_member: address, // 受保护的联盟成员（通过 FactionNFT.owner 或 member 列表核查）
    aggressor_faction: address,
    clock: &Clock,
): bool {
    is_treaty_active(treaty, clock)
    // 真实场景中需要额外核查成员与联盟的关联
}

// ── 提交撕约通知（24 小时后生效）───────────────────────

public entry fun give_termination_notice(
    treaty: &mut Treaty,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == treaty.party_a || ctx.sender() == treaty.party_b, ENotParty);
    assert!(is_treaty_active(treaty, clock), ETreatyNotActive);
    treaty.termination_notice_ms = clock.timestamp_ms();
    event::emit(TreatyTerminated { treaty_id: object::id(treaty), terminated_by: ctx.sender() });
}

/// 通知期满后正式终止条约，双方取回押金
public entry fun finalize_termination(
    treaty: &mut Treaty,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(treaty.termination_notice_ms > 0, ENoNoticeGiven);
    assert!(
        clock.timestamp_ms() >= treaty.termination_notice_ms + NOTICE_PERIOD_MS,
        ENoticeNotMature,
    );
    // 退还押金
    let a_dep = balance::withdraw_all(&mut treaty.party_a_deposit);
    let b_dep = balance::withdraw_all(&mut treaty.party_b_deposit);
    if balance::value(&a_dep) > 0 {
        transfer::public_transfer(coin::from_balance(a_dep, ctx), treaty.party_a);
    } else { balance::destroy_zero(a_dep); }
    if balance::value(&b_dep) > 0 {
        transfer::public_transfer(coin::from_balance(b_dep, ctx), treaty.party_b);
    } else { balance::destroy_zero(b_dep); }
}

// ── 举报违约（由游戏服务器验证并签名）──────────────────

public entry fun report_breach(
    treaty: &mut Treaty,
    breaching_party: address,  // 违约联盟的 Leader 地址
    admin_acl: &AdminACL,
    ctx: &mut TxContext,
) {
    verify_sponsor(admin_acl, ctx);  // 服务器证明违约事件真实发生

    let fine = BREACH_FINE;

    if breaching_party == treaty.party_a {
        treaty.breach_count_a = treaty.breach_count_a + 1;
        // 从 A 的押金中扣除罚款转给 B
        if balance::value(&treaty.party_a_deposit) >= fine {
            let fine_coin = coin::take(&mut treaty.party_a_deposit, fine, ctx);
            transfer::public_transfer(fine_coin, treaty.party_b);
        }
    } else if breaching_party == treaty.party_b {
        treaty.breach_count_b = treaty.breach_count_b + 1;
        if balance::value(&treaty.party_b_deposit) >= fine {
            let fine_coin = coin::take(&mut treaty.party_b_deposit, fine, ctx);
            transfer::public_transfer(fine_coin, treaty.party_a);
        }
    } else abort ENotParty;

    event::emit(BreachReported {
        treaty_id: object::id(treaty),
        breaching_party,
        fine,
    });
}

const ENotParty: u64 = 0;
const EInsufficientDeposit: u64 = 1;
const ENotYetSigned: u64 = 2;
const EAlreadySigned: u64 = 3;
const ETreatyNotActive: u64 = 4;
const ENoNoticeGiven: u64 = 5;
const ENoticeNotMature: u64 = 6;
