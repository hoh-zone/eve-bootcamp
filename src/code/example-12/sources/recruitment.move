module alliance::recruitment;

use sui::table::{Self, Table};
use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::String;

// ── 常量 ──────────────────────────────────────────────────

const VOTE_WINDOW_MS: u64 = 72 * 60 * 60 * 1000; // 72 小时
const APPROVAL_THRESHOLD_BPS: u64 = 6_000;         // 60%
const APPLICATION_DEPOSIT: u64 = 10_000_000_000;   // 10 SUI

// ── 数据结构 ───────────────────────────────────────────────

public struct AllianceDAO has key {
    id: UID,
    name: String,
    founder: address,
    members: vector<address>,
    treasury: Balance<SUI>,
    pending_applications: Table<address, Application>,
    total_accepted: u64,
}

public struct Application has store {
    applicant: address,
    applied_at_ms: u64,
    votes_for: u64,
    votes_against: u64,
    voters: vector<address>,  // 防止重复投票
    deposit: Balance<SUI>,
    status: u8,  // 0=pending, 1=approved, 2=rejected, 3=vetoed
}

/// 成员 NFT
public struct MemberNFT has key, store {
    id: UID,
    alliance_name: String,
    member: address,
    joined_at_ms: u64,
    serial_number: u64,
}

public struct FounderCap has key, store { id: UID }

// ── 事件 ──────────────────────────────────────────────────

public struct ApplicationSubmitted has copy, drop { applicant: address, alliance_id: ID }
public struct VoteCast has copy, drop { applicant: address, voter: address, approve: bool }
public struct ApplicationResolved has copy, drop {
    applicant: address,
    approved: bool,
    votes_for: u64,
    votes_total: u64,
}

// ── 初始化 ────────────────────────────────────────────────

public entry fun create_alliance(
    name: vector<u8>,
    ctx: &mut TxContext,
) {
    let mut dao = AllianceDAO {
        id: object::new(ctx),
        name: std::string::utf8(name),
        founder: ctx.sender(),
        members: vector[ctx.sender()],
        treasury: balance::zero(),
        pending_applications: table::new(ctx),
        total_accepted: 0,
    };

    // 创始人获得 MemberNFT（编号 #1）
    let founder_nft = MemberNFT {
        id: object::new(ctx),
        alliance_name: dao.name,
        member: ctx.sender(),
        joined_at_ms: 0,
        serial_number: 1,
    };
    dao.total_accepted = 1;

    let founder_cap = FounderCap { id: object::new(ctx) };

    transfer::share_object(dao);
    transfer::public_transfer(founder_nft, ctx.sender());
    transfer::public_transfer(founder_cap, ctx.sender());
}

// ── 申请加入 ──────────────────────────────────────────────

public entry fun apply(
    dao: &mut AllianceDAO,
    mut deposit: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let applicant = ctx.sender();
    assert!(!vector::contains(&dao.members, &applicant), EAlreadyMember);
    assert!(!table::contains(&dao.pending_applications, applicant), EAlreadyApplied);
    assert!(coin::value(&deposit) >= APPLICATION_DEPOSIT, EInsufficientDeposit);

    let deposit_balance = coin::split(&mut deposit, APPLICATION_DEPOSIT, ctx);
    if (coin::value(&deposit) > 0) {
        transfer::public_transfer(deposit, applicant);
    } else {
        coin::destroy_zero(deposit);
    };

    table::add(&mut dao.pending_applications, applicant, Application {
        applicant,
        applied_at_ms: clock.timestamp_ms(),
        votes_for: 0,
        votes_against: 0,
        voters: vector::empty(),
        deposit: coin::into_balance(deposit_balance),
        status: 0,
    });

    event::emit(ApplicationSubmitted { applicant, alliance_id: object::id(dao) });
}

// ── 成员投票 ──────────────────────────────────────────────

public entry fun vote(
    dao: &mut AllianceDAO,
    applicant: address,
    approve: bool,
    _member_nft: &MemberNFT,  // 持有 NFT 才能投票
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(vector::contains(&dao.members, &ctx.sender()), ENotMember);
    assert!(table::contains(&dao.pending_applications, applicant), ENoApplication);

    let app = table::borrow_mut(&mut dao.pending_applications, applicant);
    assert!(app.status == 0, EApplicationClosed);
    assert!(clock.timestamp_ms() <= app.applied_at_ms + VOTE_WINDOW_MS, EVoteWindowClosed);
    assert!(!vector::contains(&app.voters, &ctx.sender()), EAlreadyVoted);

    vector::push_back(&mut app.voters, ctx.sender());
    if (approve) {
        app.votes_for = app.votes_for + 1;
    } else {
        app.votes_against = app.votes_against + 1;
    };

    event::emit(VoteCast { applicant, voter: ctx.sender(), approve });

    // 若票数已足够，尝试自动结算
    try_resolve(dao, applicant, clock, ctx);
}

fun try_resolve(
    dao: &mut AllianceDAO,
    applicant: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let app = table::borrow(&dao.pending_applications, applicant);
    let total_votes = app.votes_for + app.votes_against;
    let member_count = vector::length(&dao.members);

    // 提前结算条件：赞成 >= 60% 且至少 3 票，或反对 > 40% 且覆盖全员
    let enough_approval = app.votes_for * 10_000 / member_count >= APPROVAL_THRESHOLD_BPS
                          && total_votes >= 3;
    let definite_rejection = app.votes_against * 10_000 / member_count > 4_000
                             && total_votes == member_count;

    let time_expired = clock.timestamp_ms() > app.applied_at_ms + VOTE_WINDOW_MS;

    if (enough_approval || time_expired || definite_rejection) {
        resolve_application(dao, applicant, ctx);
    }
}

fun resolve_application(
    dao: &mut AllianceDAO,
    applicant: address,
    ctx: &mut TxContext,
) {
    let app = table::borrow_mut(&mut dao.pending_applications, applicant);
    let total_votes = app.votes_for + app.votes_against;
    let approved = total_votes > 0
        && app.votes_for * 10_000 / (total_votes) >= APPROVAL_THRESHOLD_BPS;

    if (approved) {
        app.status = 1;
        // 退还押金
        let deposit = balance::withdraw_all(&mut app.deposit);
        transfer::public_transfer(coin::from_balance(deposit, ctx), applicant);

        // 加入成员列表并发放 NFT
        vector::push_back(&mut dao.members, applicant);
        dao.total_accepted = dao.total_accepted + 1;

        let nft = MemberNFT {
            id: object::new(ctx),
            alliance_name: dao.name,
            member: applicant,
            joined_at_ms: 0, // clock 无法传进内部函数，简化处理
            serial_number: dao.total_accepted,
        };
        transfer::public_transfer(nft, applicant);
    } else {
        app.status = 2;
        // 没收押金入金库
        let deposit = balance::withdraw_all(&mut app.deposit);
        balance::join(&mut dao.treasury, deposit);
    };

    event::emit(ApplicationResolved {
        applicant,
        approved,
        votes_for: app.votes_for,
        votes_total: total_votes,
    });
}

/// 创始人一票否决
public entry fun veto(
    dao: &mut AllianceDAO,
    applicant: address,
    _cap: &FounderCap,
    ctx: &mut TxContext,
) {
    assert!(table::contains(&dao.pending_applications, applicant), ENoApplication);
    let app = table::borrow_mut(&mut dao.pending_applications, applicant);
    assert!(app.status == 0, EApplicationClosed);
    app.status = 3;
    // 没收押金
    let deposit = balance::withdraw_all(&mut app.deposit);
    balance::join(&mut dao.treasury, deposit);
}

// ── 错误码 ────────────────────────────────────────────────

const EAlreadyMember: u64 = 0;
const EAlreadyApplied: u64 = 1;
const EInsufficientDeposit: u64 = 2;
const ENotMember: u64 = 3;
const ENoApplication: u64 = 4;
const EApplicationClosed: u64 = 5;
const EVoteWindowClosed: u64 = 6;
const EAlreadyVoted: u64 = 7;
