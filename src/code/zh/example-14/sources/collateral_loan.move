module lending::collateral_loan;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::dynamic_field as df;
use sui::event;

// ── 常量 ──────────────────────────────────────────────────

const MONTH_MS: u64 = 30 * 24 * 60 * 60 * 1000;
const LTV_BPS: u64 = 6_000;
const MONTHLY_INTEREST_BPS: u64 = 300;
const LIQUIDATION_BONUS_BPS: u64 = 500;

// ── 错误码 ────────────────────────────────────────────────
const EInsufficientLiquidity: u64 = 0;
const ENotBorrower: u64 = 1;
const ELoanInactive: u64 = 2;
const EInsufficientRepayment: u64 = 3;
const ENotYetExpired: u64 = 4;
const EInsufficientPayment: u64 = 5;
const ENotAdmin: u64 = 6;

// ── 数据结构 ───────────────────────────────────────────────

public struct LendingPool has key {
    id: UID,
    liquidity: Balance<SUI>,
    total_loaned: u64,
    admin: address,
}

public struct Loan has key {
    id: UID,
    borrower: address,
    collateral_id: ID,
    collateral_value: u64,
    loan_amount: u64,
    interest_amount: u64,
    repay_by_ms: u64,
    is_active: bool,
}

// ── 事件 ──────────────────────────────────────────────────

public struct LoanCreated has copy, drop {
    loan_id: ID,
    borrower: address,
    loan_amount: u64,
    repay_by_ms: u64,
}

public struct LoanRepaid has copy, drop {
    loan_id: ID,
    repaid: u64,
}

public struct LoanLiquidated has copy, drop {
    loan_id: ID,
    liquidator: address,
    collateral_id: ID,
}

// ── 初始化 ────────────────────────────────────────────────

public fun create_pool(ctx: &mut TxContext) {
    transfer::share_object(LendingPool {
        id: object::new(ctx),
        liquidity: balance::zero(),
        total_loaned: 0,
        admin: ctx.sender(),
    });
}

public fun deposit_liquidity(
    pool: &mut LendingPool,
    coin: Coin<SUI>,
) {
    balance::join(&mut pool.liquidity, coin::into_balance(coin));
}

// ── 借款 ──────────────────────────────────────────────────

public fun create_loan<T: key + store>(
    pool: &mut LendingPool,
    collateral: T,
    collateral_value_sui: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let loan_amount = collateral_value_sui * LTV_BPS / 10_000;
    let interest = loan_amount * MONTHLY_INTEREST_BPS / 10_000;
    assert!(balance::value(&pool.liquidity) >= loan_amount, EInsufficientLiquidity);

    let collateral_id = object::id(&collateral);

    let mut loan = Loan {
        id: object::new(ctx),
        borrower: ctx.sender(),
        collateral_id,
        collateral_value: collateral_value_sui,
        loan_amount,
        interest_amount: interest,
        repay_by_ms: clock.timestamp_ms() + MONTH_MS,
        is_active: true,
    };

    df::add(&mut loan.id, b"collateral", collateral);

    let loan_coin = coin::take(&mut pool.liquidity, loan_amount, ctx);
    pool.total_loaned = pool.total_loaned + loan_amount;

    let loan_id = object::id(&loan);
    transfer::public_transfer(loan_coin, ctx.sender());

    event::emit(LoanCreated {
        loan_id,
        borrower: ctx.sender(),
        loan_amount,
        repay_by_ms: loan.repay_by_ms,
    });

    transfer::share_object(loan);
}

// ── 还款 ──────────────────────────────────────────────────

public fun repay_loan<T: key + store>(
    pool: &mut LendingPool,
    loan: &mut Loan,
    mut repayment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(loan.borrower == ctx.sender(), ENotBorrower);
    assert!(loan.is_active, ELoanInactive);

    let total_due = loan.loan_amount + loan.interest_amount;
    assert!(coin::value(&repayment) >= total_due, EInsufficientRepayment);

    let repay_coin = coin::split(&mut repayment, total_due, ctx);
    balance::join(&mut pool.liquidity, coin::into_balance(repay_coin));
    pool.total_loaned = pool.total_loaned - loan.loan_amount;

    if (coin::value(&repayment) > 0) {
        transfer::public_transfer(repayment, ctx.sender());
    } else {
        coin::destroy_zero(repayment);
    };

    let collateral: T = df::remove(&mut loan.id, b"collateral");
    transfer::public_transfer(collateral, ctx.sender());

    loan.is_active = false;

    event::emit(LoanRepaid {
        loan_id: object::id(loan),
        repaid: total_due,
    });
}

// ── 清算 ──────────────────────────────────────────────────

public fun liquidate<T: key + store>(
    pool: &mut LendingPool,
    loan: &mut Loan,
    mut liquidation_payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(loan.is_active, ELoanInactive);
    assert!(clock.timestamp_ms() > loan.repay_by_ms, ENotYetExpired);

    let liquidation_price = loan.collateral_value * (10_000 - LIQUIDATION_BONUS_BPS) / 10_000;
    assert!(coin::value(&liquidation_payment) >= liquidation_price, EInsufficientPayment);

    let pay = coin::split(&mut liquidation_payment, liquidation_price, ctx);
    balance::join(&mut pool.liquidity, coin::into_balance(pay));

    if (coin::value(&liquidation_payment) > 0) {
        transfer::public_transfer(liquidation_payment, ctx.sender());
    } else {
        coin::destroy_zero(liquidation_payment);
    };

    let collateral: T = df::remove(&mut loan.id, b"collateral");
    transfer::public_transfer(collateral, ctx.sender());

    loan.is_active = false;

    event::emit(LoanLiquidated {
        loan_id: object::id(loan),
        liquidator: ctx.sender(),
        collateral_id: loan.collateral_id,
    });
}

/// 管理员从准备金补充理赔池
public fun admin_withdraw(
    pool: &mut LendingPool,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == pool.admin, ENotAdmin);
    let coin = coin::take(&mut pool.liquidity, amount, ctx);
    transfer::public_transfer(coin, pool.admin);
}
