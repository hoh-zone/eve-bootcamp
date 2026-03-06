module insurance::pvp_shield;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::table::{Self, Table};
use sui::transfer;
use sui::event;

// ── 常量 ──────────────────────────────────────────────────

const COVERAGE_BPS: u64 = 8_000;        // 赔付率 80%
const DAY_MS: u64 = 86_400_000;
const MIN_PREMIUM_BPS: u64 = 300;        // 最低保费：保额的 3%/月

// ── 数据结构 ───────────────────────────────────────────────

/// 保险池（共享）
public struct InsurancePool has key {
    id: UID,
    reserve: Balance<SUI>,       // 准备金
    total_collected: u64,        // 累计保费
    total_paid_out: u64,         // 累计赔付
    claims_pool: Balance<SUI>,   // 专用理赔池（保费的 70%）
    admin: address,
}

/// 保单 NFT
public struct PolicyNFT has key, store {
    id: UID,
    insured_item_id: ID,          // 被保物品 ObjectID
    insured_value: u64,           // 保额（SUI）
    coverage_amount: u64,         // 最高赔付（= 保额 × 80%）
    valid_until_ms: u64,          // 有效期
    is_claimed: bool,
    policy_holder: address,
}

// ── 事件 ──────────────────────────────────────────────────

public struct PolicyIssued has copy, drop {
    policy_id: ID,
    holder: address,
    insured_item_id: ID,
    coverage: u64,
    expires_ms: u64,
}

public struct ClaimPaid has copy, drop {
    policy_id: ID,
    holder: address,
    amount_paid: u64,
}

// ── 初始化 ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::share_object(InsurancePool {
        id: object::new(ctx),
        reserve: balance::zero(),
        total_collected: 0,
        total_paid_out: 0,
        claims_pool: balance::zero(),
        admin: ctx.sender(),
    });
}

// ── 购买保险 ──────────────────────────────────────────────

public entry fun purchase_policy(
    pool: &mut InsurancePool,
    insured_item_id: ID,         // 被保物品的 ObjectID
    insured_value: u64,           // 声明保额
    days: u64,                    // 保险天数（1-90）
    mut premium: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(days >= 1 && days <= 90, EInvalidDuration);

    // 计算保费：保额 × 月费率 × 天数
    let monthly_premium = insured_value * MIN_PREMIUM_BPS / 10_000;
    let required_premium = monthly_premium * days / 30;
    assert!(coin::value(&premium) >= required_premium, EInsufficientPremium);

    let pay = premium.split(required_premium, ctx);
    let premium_amount = coin::value(&pay);

    // 70% 进理赔池，30% 进准备金
    let claims_share = premium_amount * 70 / 100;
    let reserve_share = premium_amount - claims_share;

    let mut pay_balance = coin::into_balance(pay);
    let claims_portion = balance::split(&mut pay_balance, claims_share);
    balance::join(&mut pool.claims_pool, claims_portion);
    balance::join(&mut pool.reserve, pay_balance);
    pool.total_collected = pool.total_collected + premium_amount;

    if coin::value(&premium) > 0 {
        transfer::public_transfer(premium, ctx.sender());
    } else { coin::destroy_zero(premium); }

    let coverage = insured_value * COVERAGE_BPS / 10_000;
    let valid_until_ms = clock.timestamp_ms() + days * DAY_MS;

    let policy = PolicyNFT {
        id: object::new(ctx),
        insured_item_id,
        insured_value,
        coverage_amount: coverage,
        valid_until_ms,
        is_claimed: false,
        policy_holder: ctx.sender(),
    };
    let policy_id = object::id(&policy);

    transfer::public_transfer(policy, ctx.sender());

    event::emit(PolicyIssued {
        policy_id,
        holder: ctx.sender(),
        insured_item_id,
        coverage,
        expires_ms: valid_until_ms,
    });
}

// ── 理赔（需要游戏服务器签名证明物品已损毁）────────────

public entry fun file_claim(
    pool: &mut InsurancePool,
    policy: &mut PolicyNFT,
    admin_acl: &AdminACL,   // 游戏服务器验证物品确实损毁
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 验证服务器签名（即服务器确认物品已经损毁）
    verify_sponsor(admin_acl, ctx);

    assert!(!policy.is_claimed, EAlreadyClaimed);
    assert!(clock.timestamp_ms() <= policy.valid_until_ms, EPolicyExpired);
    assert!(policy.policy_holder == ctx.sender(), ENotPolicyHolder);

    // 检查赔付池余额是否足够
    let payout = policy.coverage_amount;
    assert!(balance::value(&pool.claims_pool) >= payout, EInsufficientClaimsPool);

    // 标记已理赔（防止重复理赔）
    policy.is_claimed = true;

    // 赔付
    let payout_coin = coin::take(&mut pool.claims_pool, payout, ctx);
    pool.total_paid_out = pool.total_paid_out + payout;
    transfer::public_transfer(payout_coin, ctx.sender());

    event::emit(ClaimPaid {
        policy_id: object::id(policy),
        holder: ctx.sender(),
        amount_paid: payout,
    });
}

/// 管理员从准备金补充理赔池（当理赔池不足时）
public entry fun replenish_claims_pool(
    pool: &mut InsurancePool,
    amount: u64,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == pool.admin, ENotAdmin);
    assert!(balance::value(&pool.reserve) >= amount, EInsufficientReserve);
    let replenish = balance::split(&mut pool.reserve, amount);
    balance::join(&mut pool.claims_pool, replenish);
}

const EInvalidDuration: u64 = 0;
const EInsufficientPremium: u64 = 1;
const EAlreadyClaimed: u64 = 2;
const EPolicyExpired: u64 = 3;
const ENotPolicyHolder: u64 = 4;
const EInsufficientClaimsPool: u64 = 5;
const ENotAdmin: u64 = 6;
const EInsufficientReserve: u64 = 7;
