# 实战案例 13：订阅制通行证（月付无限跳跃）

> **目标：** 建立订阅制通行证系统——玩家每月支付固定 SUI，获得在你联盟星门网络中无限跳跃的权利，无需每次单独购票。

---

> 状态：教学示例。正文聚焦订阅模型，完整目录以 `book/src/code/example-13/` 为准。

## 对应代码目录

- [example-13](./code/example-13)
- [example-13/dapp](./code/example-13/dapp)

## 最小调用链

`选择套餐 -> 支付订阅费 -> 铸造/更新 GatePassNFT -> 星门校验 pass 是否有效`

## 需求分析

**场景：** 你的联盟控制 5 个星门，希望建立月度会员制：

- **月票**：30 SUI/月，所有星门无限跳跃
- **季票**：80 SUI/季度，有折扣
- 过期后需续费，否则降级为按次付费
- 订阅 NFT 可转让（玩家可以二手交易）

---

## 合约

```move
module subscription::gate_pass;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::String;

// ── 常量 ──────────────────────────────────────────────────

const MONTH_MS: u64 = 30 * 24 * 60 * 60 * 1000;

/// 套餐类型
const PLAN_MONTHLY: u8 = 0;
const PLAN_QUARTERLY: u8 = 1;

// ── 数据结构 ───────────────────────────────────────────────

/// 订阅管理器（共享对象）
public struct SubscriptionManager has key {
    id: UID,
    monthly_price: u64,     // 月套餐价格（MIST）
    quarterly_price: u64,   // 季度套餐价格
    revenue: Balance<SUI>,
    admin: address,
    total_subscribers: u64,
}

/// 订阅 NFT（可转让，持有即有权限）
public struct GatePassNFT has key, store {
    id: UID,
    plan: u8,
    valid_until_ms: u64,
    subscriber: address,  // 原始订阅者
    serial_number: u64,
}

// ── 事件 ──────────────────────────────────────────────────

public struct PassPurchased has copy, drop {
    pass_id: ID,
    buyer: address,
    plan: u8,
    valid_until_ms: u64,
}

public struct PassRenewed has copy, drop {
    pass_id: ID,
    new_expiry_ms: u64,
}

// ── 初始化 ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::share_object(SubscriptionManager {
        id: object::new(ctx),
        monthly_price: 30_000_000_000,   // 30 SUI
        quarterly_price: 80_000_000_000, // 80 SUI（比3个月便宜10 SUI）
        revenue: balance::zero(),
        admin: ctx.sender(),
        total_subscribers: 0,
    });
}

// ── 购买订阅 ──────────────────────────────────────────────

public entry fun purchase_pass(
    mgr: &mut SubscriptionManager,
    plan: u8,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (price, duration_ms) = if plan == PLAN_MONTHLY {
        (mgr.monthly_price, MONTH_MS)
    } else if plan == PLAN_QUARTERLY {
        (mgr.quarterly_price, 3 * MONTH_MS)
    } else abort EInvalidPlan;

    assert!(coin::value(&payment) >= price, EInsufficientPayment);

    let pay = payment.split(price, ctx);
    balance::join(&mut mgr.revenue, coin::into_balance(pay));

    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else { coin::destroy_zero(payment); }

    mgr.total_subscribers = mgr.total_subscribers + 1;
    let valid_until_ms = clock.timestamp_ms() + duration_ms;

    let pass = GatePassNFT {
        id: object::new(ctx),
        plan,
        valid_until_ms,
        subscriber: ctx.sender(),
        serial_number: mgr.total_subscribers,
    };
    let pass_id = object::id(&pass);

    transfer::public_transfer(pass, ctx.sender());

    event::emit(PassPurchased {
        pass_id,
        buyer: ctx.sender(),
        plan,
        valid_until_ms,
    });
}

/// 续费（延长已有 Pass 的有效期）
public entry fun renew_pass(
    mgr: &mut SubscriptionManager,
    pass: &mut GatePassNFT,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (price, duration_ms) = if pass.plan == PLAN_MONTHLY {
        (mgr.monthly_price, MONTH_MS)
    } else {
        (mgr.quarterly_price, 3 * MONTH_MS)
    };

    assert!(coin::value(&payment) >= price, EInsufficientPayment);

    let pay = payment.split(price, ctx);
    balance::join(&mut mgr.revenue, coin::into_balance(pay));
    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else { coin::destroy_zero(payment); }

    // 如果已过期从现在起算，否则在原到期时间上叠加
    let base = if pass.valid_until_ms < clock.timestamp_ms() {
        clock.timestamp_ms()
    } else { pass.valid_until_ms };

    pass.valid_until_ms = base + duration_ms;

    event::emit(PassRenewed {
        pass_id: object::id(pass),
        new_expiry_ms: pass.valid_until_ms,
    });
}

/// 星门扩展：验证 Pass 有效性
public fun is_pass_valid(pass: &GatePassNFT, clock: &Clock): bool {
    clock.timestamp_ms() <= pass.valid_until_ms
}

/// 星门跳跃（持有有效 Pass 无限跳）
public entry fun subscriber_jump(
    gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    pass: &GatePassNFT,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(is_pass_valid(pass, clock), EPassExpired);
    gate::issue_jump_permit(
        gate, dest_gate, character, SubscriberAuth {},
        clock.timestamp_ms() + 30 * 60 * 1000, ctx,
    );
}

public struct SubscriberAuth has drop {}

/// 管理员提款
public entry fun withdraw_revenue(
    mgr: &mut SubscriptionManager,
    amount: u64,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == mgr.admin, ENotAdmin);
    let coin = coin::take(&mut mgr.revenue, amount, ctx);
    transfer::public_transfer(coin, mgr.admin);
}

const EInvalidPlan: u64 = 0;
const EInsufficientPayment: u64 = 1;
const EPassExpired: u64 = 2;
const ENotAdmin: u64 = 3;
```

---

## dApp

```tsx
// PassShop.tsx
import { useState } from 'react'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const SUB_PKG = "0x_SUBSCRIPTION_PACKAGE_"
const MGR_ID = "0x_MANAGER_ID_"

const PLANS = [
  { id: 0, name: '月套餐', price: 30, duration: '30 天', badge: '标准' },
  { id: 1, name: '季套餐', price: 80, duration: '90 天', badge: '省 10 SUI', popular: true },
]

export function PassShop() {
  const dAppKit = useDAppKit()
  const [status, setStatus] = useState('')

  const purchase = async (plan: number, priceInSUI: number) => {
    const tx = new Transaction()
    const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(priceInSUI * 1e9)])
    tx.moveCall({
      target: `${SUB_PKG}::gate_pass::purchase_pass`,
      arguments: [tx.object(MGR_ID), tx.pure.u8(plan), payment, tx.object('0x6')],
    })
    try {
      setStatus('⏳ 购买中...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('✅ 订阅成功！GatePassNFT 已发送到你的钱包')
    } catch (e: any) { setStatus(`❌ ${e.message}`) }
  }

  return (
    <div className="pass-shop">
      <h1>🎫 星门订阅通行证</h1>
      <p>持有有效期内的通行证，在本联盟所有星门无限跳跃</p>
      <div className="plan-grid">
        {PLANS.map(plan => (
          <div key={plan.id} className={`plan-card ${plan.popular ? 'popular' : ''}`}>
            {plan.popular && <div className="popular-badge">推荐</div>}
            <h3>{plan.name}</h3>
            <div className="plan-price">
              <span className="price">{plan.price}</span>
              <span className="unit">SUI</span>
            </div>
            <div className="plan-duration">有效期 {plan.duration}</div>
            <div className="plan-badge">{plan.badge}</div>
            <button className="buy-btn" onClick={() => purchase(plan.id, plan.price)}>
              购买  {plan.name}
            </button>
          </div>
        ))}
      </div>
      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 📚 关联文档
- [Chapter 13：NFT 设计与 TransferPolicy](./chapter-13.md)
- [Example 2：星门收费站](./example-02.md)
