# Practical Case 14: NFT Collateral Lending Protocol

> **Objective:** Build an on-chain lending protocol—players use NFTs or high-value items as collateral to borrow SUI liquidity; collateral is liquidated and auctioned to the highest bidder if loan is not repaid on time.

---

> Status: Teaching example. The main text covers core lending process, complete directory is based on `book/src/code/example-14/`.

## Corresponding Code Directory

- [example-14](./code/example-14)
- [example-14/dapp](./code/example-14/dapp)

## Minimal Call Chain

`Lender injects liquidity -> Borrower collateralizes NFT -> Contract issues SUI -> Repayment on time or liquidation triggered`

## Requirements Analysis

**Scenario:** Player holds a "rare shield" worth 1000 SUI but urgently needs SUI to buy mining machines. They pledge the shield, borrow 600 SUI (60% LTV), and must return 618 SUI within 30 days (including 3% monthly interest), otherwise the shield is liquidated.

---

## Contract

```move
module lending::collateral_loan;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::dynamic_field as df;
use sui::event;

// ── Constants ──────────────────────────────────────────────────

const MONTH_MS: u64 = 30 * 24 * 60 * 60 * 1000;
const LTV_BPS: u64 = 6_000;            // 60% loan-to-value
const MONTHLY_INTEREST_BPS: u64 = 300; // 3% monthly interest
const LIQUIDATION_BONUS_BPS: u64 = 500; // 5% liquidator reward

// ── Data Structures ───────────────────────────────────────────────

/// Lending pool (shared object, stores lender's SUI)
public struct LendingPool has key {
    id: UID,
    liquidity: Balance<SUI>,
    total_loaned: u64,
    admin: address,
}

/// Single loan
public struct Loan has key {
    id: UID,
    borrower: address,
    collateral_id: ID,    // Collateral ObjectID
    collateral_value: u64, // Evaluated value at lending time (SUI)
    loan_amount: u64,      // Actual borrowed amount
    interest_amount: u64,  // Interest due
    repay_by_ms: u64,      // Repayment deadline
    is_active: bool,
}

// ── Events ──────────────────────────────────────────────────

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

// ── Initialize Lending Pool ──────────────────────────────────────────

public fun create_pool(ctx: &mut TxContext) {
    transfer::share_object(LendingPool {
        id: object::new(ctx),
        liquidity: balance::zero(),
        total_loaned: 0,
        admin: ctx.sender(),
    });
}

/// Lender deposits liquidity into pool
public fun deposit_liquidity(
    pool: &mut LendingPool,
    coin: Coin<SUI>,
    _ctx: &TxContext,
) {
    balance::join(&mut pool.liquidity, coin::into_balance(coin));
}

// ── Borrow (with NFT as collateral) ────────────────────────────────

/// Created by Oracle/Admin with evaluation
/// (In real scenarios, collateral_value needs to be determined by off-chain price oracle)
public fun create_loan<T: key + store>(
    pool: &mut LendingPool,
    collateral: T,
    collateral_value_sui: u64,    // Valuation confirmed by price oracle or Admin
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let loan_amount = collateral_value_sui * LTV_BPS / 10_000; // 60% LTV
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

    // Lock collateral in Loan object (dynamic field)
    df::add(&mut loan.id, b"collateral", collateral);

    // Issue loan
    let loan_coin = coin::take(&mut pool.liquidity, loan_amount, ctx);
    pool.total_loaned = pool.total_loaned + loan_amount;

    transfer::public_transfer(loan_coin, ctx.sender());

    event::emit(LoanCreated {
        loan_id: object::id(&loan),
        borrower: ctx.sender(),
        loan_amount,
        repay_by_ms: loan.repay_by_ms,
    });

    transfer::share_object(loan);
}

// ── Repayment (return loan + interest, retrieve collateral) ──────────────────

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

    // Repayment to pool
    let repay_coin = repayment.split(total_due, ctx);
    balance::join(&mut pool.liquidity, coin::into_balance(repay_coin));
    pool.total_loaned = pool.total_loaned - loan.loan_amount;

    if coin::value(&repayment) > 0 {
        transfer::public_transfer(repayment, ctx.sender());
    } else { coin::destroy_zero(repayment); }

    // Retrieve collateral
    let collateral: T = df::remove(&mut loan.id, b"collateral");
    transfer::public_transfer(collateral, ctx.sender());

    loan.is_active = false;

    event::emit(LoanRepaid {
        loan_id: object::id(loan),
        repaid: total_due,
    });
}

// ── Liquidation (overdue, liquidator takes collateral) ──────────────────

public fun liquidate<T: key + store>(
    pool: &mut LendingPool,
    loan: &mut Loan,
    mut liquidation_payment: Coin<SUI>, // Liquidator pays collateral_value * 95%
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(loan.is_active, ELoanInactive);
    assert!(clock.timestamp_ms() > loan.repay_by_ms, ENotYetExpired);

    // Liquidator must pay 95% of collateral valuation (5% as reward)
    let liquidation_price = loan.collateral_value * (10_000 - LIQUIDATION_BONUS_BPS) / 10_000;
    assert!(coin::value(&liquidation_payment) >= liquidation_price, EInsufficientPayment);

    let pay = liquidation_payment.split(liquidation_price, ctx);
    // Repay principal + interest to pool, remainder to liquidator as reward
    balance::join(&mut pool.liquidity, coin::into_balance(pay));

    if coin::value(&liquidation_payment) > 0 {
        transfer::public_transfer(liquidation_payment, ctx.sender());
    } else { coin::destroy_zero(liquidation_payment); }

    // Liquidator receives collateral
    let collateral: T = df::remove(&mut loan.id, b"collateral");
    transfer::public_transfer(collateral, ctx.sender());

    loan.is_active = false;

    event::emit(LoanLiquidated {
        loan_id: object::id(loan),
        liquidator: ctx.sender(),
        collateral_id: loan.collateral_id,
    });
}

const EInsufficientLiquidity: u64 = 0;
const ENotBorrower: u64 = 1;
const ELoanInactive: u64 = 2;
const EInsufficientRepayment: u64 = 3;
const ENotYetExpired: u64 = 4;
const EInsufficientPayment: u64 = 5;
```

---

## dApp Interface (Lending Dashboard)

```tsx
// LendingDashboard.tsx
import { useQuery } from '@tanstack/react-query'
import { useCurrentClient } from '@mysten/dapp-kit-react'

const LENDING_PKG = "0x_LENDING_PACKAGE_"
const POOL_ID = "0x_POOL_ID_"

export function LendingDashboard() {
  const client = useCurrentClient()

  const { data: pool } = useQuery({
    queryKey: ['lending-pool'],
    queryFn: async () => {
      const obj = await client.getObject({ id: POOL_ID, options: { showContent: true } })
      return (obj.data?.content as any)?.fields
    },
    refetchInterval: 15_000,
  })

  const availableLiquidity = Number(pool?.liquidity?.fields?.value ?? 0) / 1e9
  const totalLoaned = Number(pool?.total_loaned ?? 0) / 1e9
  const utilization = totalLoaned / (availableLiquidity + totalLoaned) * 100

  return (
    <div className="lending-dashboard">
      <h1>NFT Collateral Lending</h1>

      <div className="pool-stats">
        <div className="stat">
          <span>Available Liquidity</span>
          <strong>{availableLiquidity.toFixed(2)} SUI</strong>
        </div>
        <div className="stat">
          <span>Total Loaned</span>
          <strong>{totalLoaned.toFixed(2)} SUI</strong>
        </div>
        <div className="stat">
          <span>Utilization Rate</span>
          <strong>{utilization.toFixed(1)}%</strong>
        </div>
        <div className="stat">
          <span>Monthly Interest</span>
          <strong>3%</strong>
        </div>
      </div>

      <div className="loan-info">
        <h3>Loan Terms</h3>
        <ul>
          <li>Loan-to-Value (LTV): 60%</li>
          <li>Monthly Interest: 3% (fixed)</li>
          <li>Maximum Term: 30 days</li>
          <li>Overdue Liquidation: Collateral acquired by liquidator at 95% valuation</li>
        </ul>
      </div>
    </div>
  )
}
```

---

## Related Documentation
- [Chapter 12: Dynamic Fields](./chapter-12.md)
- [Chapter 14: Economic System](./chapter-14.md)
- [Chapter 15: Cross-contract Composition](./chapter-15.md)
