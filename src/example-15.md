# 实战案例 15：去中心化物品保险

> ⏱ 预计练习时间：2 小时
>
> **目标：** 构建链上物品保险协议——玩家购买 PvP 战损险，若物品在游戏中被摧毁则通过服务器证明（AdminACL）自动赔付，理赔资金来自保险池。

---

> 状态：教学示例。正文强调理赔流程与资金池设计，完整目录以 `book/src/code/example-15/` 为准。

## 前置依赖

- 建议先读 [Chapter 11](./chapter-11.md)、[Chapter 25](./chapter-25.md)
- 需要本地 `sui` CLI 与 `pnpm`
- 需要理解 `AdminACL` 与链下证明流

## 对应代码目录

- [example-15](./code/example-15)
- [example-15/dapp](./code/example-15/dapp)

## 源码位置

- [Move.toml](./code/example-15/Move.toml)
- [pvp_shield.move](./code/example-15/sources/pvp_shield.move)
- [dapp/readme.md](./code/example-15/dapp/readme.md)

## 关键测试文件

- [tests/README.md](./code/example-15/tests/README.md)

## 推荐阅读顺序

1. 先看 `Move.toml`
2. 再读 [pvp_shield.move](./code/example-15/sources/pvp_shield.move)
3. 最后启动 dApp 验证报价和投保交互

## 最小调用链

`用户购买保单 -> 服务器出具战损证明 -> 合约验证保单与签名 -> 保险池赔付`

## 验证步骤

1. 在 [example-15](./code/example-15) 运行 `sui move build`
2. 在 [example-15/dapp](./code/example-15/dapp) 运行 `pnpm install && pnpm dev`
3. 验证投保、有效期内理赔、过期理赔失败

## 常见报错

- 理赔证明没有绑定具体保单或物品 ID
- 赔付比例和保费计算单位不一致
- 前端只展示保额，没有同步显示赔付上限与保费来源

## 测试闭环

- 投保成功：确认 `claims_pool` / `reserve` 的 70/30 分账正确
- 有效期内理赔：确认赔付金额等于 `coverage_amount`
- 过期拒赔：确认过期保单无法再次发起理赔
- 理赔池不足：确认不会发生负余额或重复扣款

## 需求分析

**场景：** 玩家带着价值 500 SUI 的稀有护盾出征 PvP。他花 15 SUI 购买 30 天物品险，若战斗中护盾被摧毁：

1. 游戏服务器记录死亡事件
2. 玩家提交理赔申请 + 服务器签名（AdminACL 验证）
3. 合约验证保单有效期内，自动赔付（赔付率 80%）

---

## 合约

```move
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
```

---

## dApp（购买与理赔）

```tsx
// InsuranceApp.tsx
import { useState } from 'react'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const INS_PKG = "0x_INSURANCE_PACKAGE_"
const POOL_ID = "0x_POOL_ID_"

export function InsuranceApp() {
  const dAppKit = useDAppKit()
  const [value, setValue] = useState(500) // 保额（SUI）
  const [days, setDays] = useState(30)
  const [status, setStatus] = useState('')

  // 保费计算
  const premium = (value * 0.03 * days / 30).toFixed(2)
  const coverage = (value * 0.8).toFixed(2)

  const purchase = async () => {
    const tx = new Transaction()
    const premiumMist = BigInt(Math.ceil(Number(premium) * 1e9))
    const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(premiumMist)])
    tx.moveCall({
      target: `${INS_PKG}::pvp_shield::purchase_policy`,
      arguments: [
        tx.object(POOL_ID),
        tx.pure.id('0x_ITEM_OBJECT_ID_'),
        tx.pure.u64(value * 1e9),
        tx.pure.u64(days),
        payment,
        tx.object('0x6'),
      ],
    })
    try {
      setStatus('⏳ 购买保险...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('✅ 保单已生效！PolicyNFT 已发送到钱包')
    } catch (e: any) { setStatus(`❌ ${e.message}`) }
  }

  return (
    <div className="insurance-app">
      <h1>🛡 PvP 物品战损险</h1>
      <div className="config-section">
        <label>保额（SUI）</label>
        <input type="range" min={100} max={5000} step={50}
          value={value} onChange={e => setValue(Number(e.target.value))} />
        <span>{value} SUI</span>

        <label>保险天数</label>
        {[7, 14, 30, 60, 90].map(d => (
          <button key={d} className={days === d ? 'selected' : ''} onClick={() => setDays(d)}>
            {d} 天
          </button>
        ))}
      </div>

      <div className="summary-card">
        <div className="summary-row">
          <span>📋 保额</span><strong>{value} SUI</strong>
        </div>
        <div className="summary-row">
          <span>💰 最高赔付</span><strong>{coverage} SUI</strong>
        </div>
        <div className="summary-row">
          <span>🏷 保费</span><strong>{premium} SUI</strong>
        </div>
        <div className="summary-row">
          <span>📅 有效期</span><strong>{days} 天</strong>
        </div>
      </div>

      <button className="purchase-btn" onClick={purchase}>
        购买保险（{premium} SUI）
      </button>
      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 📚 关联文档
- [Chapter 11：赞助交易与 AdminACL 验证](./chapter-11.md)
- [Chapter 8：经济系统与资金池](./chapter-08.md)
