module ally_dao::treasury;

use ally_dao::ally_token::ALLY_TOKEN;
use sui::coin::{Self, Coin, TreasuryCap};
use sui::balance::{Self, Balance};
use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::event;
use sui::transfer;
use sui::tx_context::TxContext;
use sui::sui::SUI;

// ── 数据结构 ──────────────────────────────────────────────

/// 联盟金库
public struct AllianceTreasury has key {
    id: UID,
    sui_balance: Balance<SUI>,          // 等待分配的 SUI
    total_distributed: u64,             // 历史累计分红总额
    distribution_index: u64,            // 当前分红轮次
    total_ally_supply: u64,             // 当前 ALLY Token 流通总量
}

/// 分红领取凭证（记录每个持有者已领到哪一轮）
public struct DividendClaim has key, store {
    id: UID,
    holder: address,
    last_claimed_index: u64,
}

/// 提案（治理）
public struct Proposal has key {
    id: UID,
    proposer: address,
    description: vector<u8>,
    vote_yes: u64,      // 赞成票（ALLY Token 数量加权）
    vote_no: u64,       // 反对票
    deadline_ms: u64,
    executed: bool,
}

/// 分红快照（每次分红创建一个）
public struct DividendSnapshot has store {
    amount_per_token: u64,  // 每个 ALLY Token 对应的 SUI 数量（以最小精度计）
    total_supply_at_snapshot: u64,
}

// ── 事件 ──────────────────────────────────────────────────

public struct DividendDistributed has copy, drop {
    treasury_id: ID,
    total_amount: u64,
    per_token_amount: u64,
    distribution_index: u64,
}

public struct DividendClaimed has copy, drop {
    holder: address,
    amount: u64,
    rounds: u64,
}

// ── 初始化 ────────────────────────────────────────────────

public entry fun create_treasury(
    total_ally_supply: u64,
    ctx: &mut TxContext,
) {
    let treasury = AllianceTreasury {
        id: object::new(ctx),
        sui_balance: balance::zero(),
        total_distributed: 0,
        distribution_index: 0,
        total_ally_supply,
    };
    transfer::share_object(treasury);
}

// ── 收入存入 ──────────────────────────────────────────────

/// 任何合约（星门、市场等）都可以向金库存入收入
public fun deposit_revenue(treasury: &mut AllianceTreasury, coin: Coin<SUI>) {
    balance::join(&mut treasury.sui_balance, coin::into_balance(coin));
}

// ── 触发分红 ──────────────────────────────────────────────

/// 管理员触发：将当前金库余额按比例准备分红
/// 需要存储每轮的快照
public entry fun trigger_distribution(
    treasury: &mut AllianceTreasury,
    ctx: &TxContext,
) {
    let total = balance::value(&treasury.sui_balance);
    assert!(total > 0, ENoBalance);
    assert!(treasury.total_ally_supply > 0, ENoSupply);

    // 每个 Token 分到多少（以最小精度，即乘以 1e6 避免精度损失）
    let per_token_scaled = total * 1_000_000 / treasury.total_ally_supply;

    treasury.distribution_index = treasury.distribution_index + 1;
    treasury.total_distributed = treasury.total_distributed + total;

    // 存储快照到动态字段
    sui::dynamic_field::add(
        &mut treasury.id,
        treasury.distribution_index,
        DividendSnapshot {
            amount_per_token: per_token_scaled,
            total_supply_at_snapshot: treasury.total_ally_supply,
        }
    );

    event::emit(DividendDistributed {
        treasury_id: object::id(treasury),
        total_amount: total,
        per_token_amount: per_token_scaled,
        distribution_index: treasury.distribution_index,
    });
}

// ── 持有者领取分红 ────────────────────────────────────────

/// 持有者提供自己的 ALLY Token（不消耗，只读取数量）来领取分红
public entry fun claim_dividends(
    treasury: &mut AllianceTreasury,
    ally_coin: &Coin<ALLY_TOKEN>,    // 持有者的 ALLY Token（只读）
    claim_record: &mut DividendClaim,
    ctx: &mut TxContext,
) {
    assert!(claim_record.holder == ctx.sender(), ENotHolder);

    let holder_balance = coin::value(ally_coin);
    assert!(holder_balance > 0, ENoAllyTokens);

    let from_index = claim_record.last_claimed_index + 1;
    let to_index = treasury.distribution_index;
    assert!(from_index <= to_index, ENothingToClaim);

    let mut total_claim: u64 = 0;
    let mut i = from_index;

    while (i <= to_index) {
        let snapshot: &DividendSnapshot = sui::dynamic_field::borrow(
            &treasury.id, i
        );
        // 按持仓比例计算（反缩放）
        total_claim = total_claim + (holder_balance * snapshot.amount_per_token / 1_000_000);
        i = i + 1;
    };

    assert!(total_claim > 0, ENothingToClaim);

    claim_record.last_claimed_index = to_index;
    let payout = sui::coin::take(&mut treasury.sui_balance, total_claim, ctx);
    transfer::public_transfer(payout, ctx.sender());

    event::emit(DividendClaimed {
        holder: ctx.sender(),
        amount: total_claim,
        rounds: to_index - from_index + 1,
    });
}

/// 创建领取凭证（每个持有者创建一次）
public entry fun create_claim_record(ctx: &mut TxContext) {
    let record = DividendClaim {
        id: object::new(ctx),
        holder: ctx.sender(),
        last_claimed_index: 0,
    };
    transfer::transfer(record, ctx.sender());
}

const ENoBalance: u64 = 0;
const ENoSupply: u64 = 1;
const ENotHolder: u64 = 2;
const ENoAllyTokens: u64 = 3;
const ENothingToClaim: u64 = 4;
