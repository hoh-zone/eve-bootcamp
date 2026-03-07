# 实战案例 14：物品质押借贷协议

> **目标：** 构建链上借贷协议——玩家以 NFT 或高价物品作为抵押，借取 SUI 流动性；逾期未还则抵押物被清算拍卖给出价最高者。

---

> 状态：教学示例。正文覆盖核心借贷流程，完整目录以 `book/src/code/example-14/` 为准。

## 对应代码目录

- [example-14](./code/example-14)
- [example-14/dapp](./code/example-14/dapp)

## 最小调用链

`出借人注入流动性 -> 借款人抵押 NFT -> 合约发放 SUI -> 到期还款或触发清算`

## 需求分析

**场景：** 玩家持有一件价值 1000 SUI 的"稀有护盾"，但急需 SUI 购买矿机。他将护盾质押，借出 600 SUI（60% LTV），30 天内归还 618 SUI（含 3% 月息），否则护盾被清算。

---

## 合约

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

// ── 常量 ──────────────────────────────────────────────────

const MONTH_MS: u64 = 30 * 24 * 60 * 60 * 1000;
const LTV_BPS: u64 = 6_000;            // 60% 贷款价值比
const MONTHLY_INTEREST_BPS: u64 = 300; // 3% 月息
const LIQUIDATION_BONUS_BPS: u64 = 500; // 清算人奖励 5%

// ── 数据结构 ───────────────────────────────────────────────

/// 借贷池（共享对象，存放出借方的 SUI）
public struct LendingPool has key {
    id: UID,
    liquidity: Balance<SUI>,
    total_loaned: u64,
    admin: address,
}

/// 单笔贷款
public struct Loan has key {
    id: UID,
    borrower: address,
    collateral_id: ID,    // 质押物 ObjectID
    collateral_value: u64, // 出借时评估的价值（SUI）
    loan_amount: u64,      // 实际借出金额
    interest_amount: u64,  // 应还利息
    repay_by_ms: u64,      // 还款截止时间
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

// ── 初始化借贷池 ──────────────────────────────────────────

public entry fun create_pool(ctx: &mut TxContext) {
    transfer::share_object(LendingPool {
        id: object::new(ctx),
        liquidity: balance::zero(),
        total_loaned: 0,
        admin: ctx.sender(),
    });
}

/// 出借方向池中注入流动性
public entry fun deposit_liquidity(
    pool: &mut LendingPool,
    coin: Coin<SUI>,
    _ctx: &TxContext,
) {
    balance::join(&mut pool.liquidity, coin::into_balance(coin));
}

// ── 借款（以 NFT 为抵押）────────────────────────────────

/// 由 Oracle/Admin 评估并发起贷款
/// （实际场景中，collateral_value 需要通过链下价格预言机确定）
public entry fun create_loan<T: key + store>(
    pool: &mut LendingPool,
    collateral: T,
    collateral_value_sui: u64,    // 价格预言机或 Admin 确认的估值
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

    // 将抵押物锁定在 Loan 对象中（动态字段）
    df::add(&mut loan.id, b"collateral", collateral);

    // 发放借款
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

// ── 还款（归还借款 + 利息，取回抵押物）──────────────────

public entry fun repay_loan<T: key + store>(
    pool: &mut LendingPool,
    loan: &mut Loan,
    mut repayment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(loan.borrower == ctx.sender(), ENotBorrower);
    assert!(loan.is_active, ELoanInactive);

    let total_due = loan.loan_amount + loan.interest_amount;
    assert!(coin::value(&repayment) >= total_due, EInsufficientRepayment);

    // 还款入池
    let repay_coin = repayment.split(total_due, ctx);
    balance::join(&mut pool.liquidity, coin::into_balance(repay_coin));
    pool.total_loaned = pool.total_loaned - loan.loan_amount;

    if coin::value(&repayment) > 0 {
        transfer::public_transfer(repayment, ctx.sender());
    } else { coin::destroy_zero(repayment); }

    // 取回抵押物
    let collateral: T = df::remove(&mut loan.id, b"collateral");
    transfer::public_transfer(collateral, ctx.sender());

    loan.is_active = false;

    event::emit(LoanRepaid {
        loan_id: object::id(loan),
        repaid: total_due,
    });
}

// ── 清算（到期未还，清算人取走抵押物）──────────────────

public entry fun liquidate<T: key + store>(
    pool: &mut LendingPool,
    loan: &mut Loan,
    mut liquidation_payment: Coin<SUI>, // 清算人支付 collateral_value * 95%
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(loan.is_active, ELoanInactive);
    assert!(clock.timestamp_ms() > loan.repay_by_ms, ENotYetExpired);

    // 清算人需支付抵押物估值的 95%（留 5% 作为奖励）
    let liquidation_price = loan.collateral_value * (10_000 - LIQUIDATION_BONUS_BPS) / 10_000;
    assert!(coin::value(&liquidation_payment) >= liquidation_price, EInsufficientPayment);

    let pay = liquidation_payment.split(liquidation_price, ctx);
    // 还款本金 + 利息入池，剩余归清算人作奖励
    balance::join(&mut pool.liquidity, coin::into_balance(pay));

    if coin::value(&liquidation_payment) > 0 {
        transfer::public_transfer(liquidation_payment, ctx.sender());
    } else { coin::destroy_zero(liquidation_payment); }

    // 清算人获得抵押物
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

## dApp 界面（借贷仪表盘）

```tsx
// LendingDashboard.tsx
import { useQuery } from '@tanstack/react-query'
import { useSuiClient } from '@mysten/dapp-kit'

const LENDING_PKG = "0x_LENDING_PACKAGE_"
const POOL_ID = "0x_POOL_ID_"

export function LendingDashboard() {
  const client = useSuiClient()

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
      <h1>🏦 物品质押借贷</h1>

      <div className="pool-stats">
        <div className="stat">
          <span>💧 可借流动性</span>
          <strong>{availableLiquidity.toFixed(2)} SUI</strong>
        </div>
        <div className="stat">
          <span>📤 已借出</span>
          <strong>{totalLoaned.toFixed(2)} SUI</strong>
        </div>
        <div className="stat">
          <span>📊 资金使用率</span>
          <strong>{utilization.toFixed(1)}%</strong>
        </div>
        <div className="stat">
          <span>💰 月息</span>
          <strong>3%</strong>
        </div>
      </div>

      <div className="loan-info">
        <h3>借款条件</h3>
        <ul>
          <li>贷款价值比（LTV）：60%</li>
          <li>月息：3%（固定）</li>
          <li>最长借期：30 天</li>
          <li>逾期清算：抵押物以估值 95% 被清算人收购</li>
        </ul>
      </div>
    </div>
  )
}
```

---

## 📚 关联文档
- [Chapter 12：动态字段](./chapter-12.md)
- [Chapter 14：经济系统](./chapter-14.md)
- [Chapter 15：跨合约组合](./chapter-15.md)
