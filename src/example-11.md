# 实战案例 11：物品租赁系统（出租而非出售）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 构建一个链上物品租赁市场——物品所有者出租而非出售装备，租用者在有效期内拥有使用权，到期后物品自动归还（或可赎回）。

---

> 状态：教学示例。正文解释核心业务流，完整目录以本地 `book/src/code/example-11/` 为准。

## 前置依赖

- 建议先读 [Chapter 7](./chapter-07.md)、[Chapter 8](./chapter-08.md)
- 需要本地 `sui` CLI 与 `pnpm`
- 需要可用的钱包与测试网络/本地链

## 对应代码目录

- [example-11](./code/example-11)
- [example-11/dapp](./code/example-11/dapp)

## 源码位置

- [Move.toml](./code/example-11/Move.toml)
- [equipment_rental.move](./code/example-11/sources/equipment_rental.move)
- [dapp/readme.md](./code/example-11/dapp/readme.md)

## 关键测试文件

- [tests/README.md](./code/example-11/tests/README.md)

## 推荐阅读顺序

1. 先看 `Move.toml`
2. 再读 [equipment_rental.move](./code/example-11/sources/equipment_rental.move)
3. 最后启动 [dapp/readme.md](./code/example-11/dapp/readme.md) 对照前端

## 最小调用链

`创建挂单 -> 用户租用 -> 合约铸造 RentalPass -> 到期或提前归还 -> 资金结算`

## 验证步骤

1. 进入 [example-11](./code/example-11) 运行 `sui move build`
2. 进入 [example-11/dapp](./code/example-11/dapp) 运行 `pnpm install && pnpm dev`
3. 验证挂单、租用、提前归还三条路径

## 常见报错

- 用事件直接当作“挂单列表”数据源，导致页面读到的是历史租用记录
- `listing_id` 与真实对象 ID 不一致
- 退款与剩余租期计算没有放在同一事务里

## 测试闭环

- 挂单创建：确认 `is_available == true`，且可被前端正确查询到
- 成功租用：确认租用者收到 `RentalPass`，出租者收到 70% 租金
- 提前归还：确认退款按剩余天数计算，剩余押金正确流向出租者
- 到期回收：确认未到期时回收失败，到期后回收成功

## 需求分析

**场景：** 高级飞船模块价格昂贵，多数玩家买不起，但可以租用：

- 出租者将模块锁入租赁合约，设置日租金和最长租期
- 租用者支付租金，获得临时**使用权凭证 NFT**（`RentalPass`）
- 使用权凭证携带到期时间戳，合约在使用时验证是否在有效期内
- 到期后，出租者可以收回模块（或续租）
- 若租用者提前归还，退还剩余天数的租金

---

## 第一部分：租赁合约

```move
module rental::equipment_rental;

use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::String;

// ── 常量 ──────────────────────────────────────────────────

const DAY_MS: u64 = 86_400_000;

// ── 数据结构 ───────────────────────────────────────────────

/// 租赁挂单（锁定物品）
public struct RentalListing has key {
    id: UID,
    item_id: ID,              // 被租赁的物品对象 ID
    item_name: String,
    owner: address,
    daily_rate_sui: u64,      // 每天租金（MIST）
    max_days: u64,            // 最长租期
    deposited_balance: Balance<SUI>, // 出租者预存的保证金（可选）
    is_available: bool,
    current_renter: option::Option<address>,
    lease_expires_ms: u64,
}

/// 租用凭证 NFT（租用者持有）
public struct RentalPass has key, store {
    id: UID,
    listing_id: ID,
    item_name: String,
    renter: address,
    expires_ms: u64,
    prepaid_days: u64,
    refundable_balance: Balance<SUI>, // 可退还余额（提前归还用）
}

// ── 事件 ──────────────────────────────────────────────────

public struct ItemRented has copy, drop {
    listing_id: ID,
    renter: address,
    days: u64,
    total_paid: u64,
    expires_ms: u64,
}

public struct ItemReturned has copy, drop {
    listing_id: ID,
    renter: address,
    early: bool,
    refund_amount: u64,
}

// ── 出租者操作 ────────────────────────────────────────────

/// 创建租赁挂单
public entry fun create_listing(
    item_name: vector<u8>,
    tracked_item_id: ID,       // 物品的 Object ID（合约追踪，实际物品在 SSU 中）
    daily_rate_sui: u64,
    max_days: u64,
    ctx: &mut TxContext,
) {
    let listing = RentalListing {
        id: object::new(ctx),
        item_id: tracked_item_id,
        item_name: std::string::utf8(item_name),
        owner: ctx.sender(),
        daily_rate_sui,
        max_days,
        deposited_balance: balance::zero(),
        is_available: true,
        current_renter: option::none(),
        lease_expires_ms: 0,
    };
    transfer::share_object(listing);
}

/// 下架（只有在物品未出租时才能撤回）
public entry fun delist(
    listing: &mut RentalListing,
    ctx: &TxContext,
) {
    assert!(listing.owner == ctx.sender(), ENotOwner);
    assert!(listing.is_available, EItemCurrentlyRented);
    listing.is_available = false;
}

// ── 租用者操作 ────────────────────────────────────────────

/// 租用物品
public entry fun rent_item(
    listing: &mut RentalListing,
    days: u64,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(listing.is_available, ENotAvailable);
    assert!(days >= 1 && days <= listing.max_days, EInvalidDays);

    let total_cost = listing.daily_rate_sui * days;
    assert!(coin::value(&payment) >= total_cost, EInsufficientPayment);

    let expires_ms = clock.timestamp_ms() + days * DAY_MS;

    // 扣除租金
    let rent_payment = payment.split(total_cost, ctx);
    // 给出租者发送 70%，剩余 30% 作为押金锁在 RentalPass 中（提前归还时退还）
    let owner_share = rent_payment.split(total_cost * 70 / 100, ctx);
    transfer::public_transfer(owner_share, listing.owner);

    // 更新挂单状态
    listing.is_available = false;
    listing.current_renter = option::some(ctx.sender());
    listing.lease_expires_ms = expires_ms;

    // 发放 RentalPass NFT
    let pass = RentalPass {
        id: object::new(ctx),
        listing_id: object::id(listing),
        item_name: listing.item_name,
        renter: ctx.sender(),
        expires_ms,
        prepaid_days: days,
        refundable_balance: coin::into_balance(rent_payment), // 剩余 30%
    };

    // 退找零
    if coin::value(&payment) > 0 {
        transfer::public_transfer(payment, ctx.sender());
    } else { coin::destroy_zero(payment); }

    transfer::public_transfer(pass, ctx.sender());

    event::emit(ItemRented {
        listing_id: object::id(listing),
        renter: ctx.sender(),
        days,
        total_paid: total_cost,
        expires_ms,
    });
}

/// 使用物品时验证租赁是否有效
public fun verify_rental(
    pass: &RentalPass,
    listing_id: ID,
    clock: &Clock,
): bool {
    pass.listing_id == listing_id
        && clock.timestamp_ms() <= pass.expires_ms
}

/// 提前归还（退押金）
public entry fun return_early(
    listing: &mut RentalListing,
    mut pass: RentalPass,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(pass.listing_id == object::id(listing), EWrongListing);
    assert!(pass.renter == ctx.sender(), ENotRenter);
    assert!(clock.timestamp_ms() < pass.expires_ms, EAlreadyExpired);

    // 计算剩余天数应退款
    let remaining_ms = pass.expires_ms - clock.timestamp_ms();
    let remaining_days = remaining_ms / DAY_MS;
    let refund = if remaining_days > 0 {
        balance::value(&pass.refundable_balance) * remaining_days / pass.prepaid_days
    } else { 0 };

    // 退款
    if refund > 0 {
        let refund_coin = coin::take(&mut pass.refundable_balance, refund, ctx);
        transfer::public_transfer(refund_coin, ctx.sender());
    };

    // 销毁剩余押金给出租者
    let remaining_bal = balance::withdraw_all(&mut pass.refundable_balance);
    if balance::value(&remaining_bal) > 0 {
        transfer::public_transfer(coin::from_balance(remaining_bal, ctx), listing.owner);
    } else { balance::destroy_zero(remaining_bal); }

    // 归还 listing 可用性
    listing.is_available = true;
    listing.current_renter = option::none();

    let RentalPass { id, refundable_balance, .. } = pass;
    balance::destroy_zero(refundable_balance);
    id.delete();

    event::emit(ItemReturned {
        listing_id: object::id(listing),
        renter: ctx.sender(),
        early: true,
        refund_amount: refund,
    });
}

/// 租期到期后，出租者收回控制权
public entry fun reclaim_after_expiry(
    listing: &mut RentalListing,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(listing.owner == ctx.sender(), ENotOwner);
    assert!(!listing.is_available, EAlreadyAvailable);
    assert!(clock.timestamp_ms() > listing.lease_expires_ms, ELeaseNotExpired);

    listing.is_available = true;
    listing.current_renter = option::none();
}

// ── 错误码 ────────────────────────────────────────────────
const ENotOwner: u64 = 0;
const EItemCurrentlyRented: u64 = 1;
const ENotAvailable: u64 = 2;
const EInvalidDays: u64 = 3;
const EInsufficientPayment: u64 = 4;
const EWrongListing: u64 = 5;
const ENotRenter: u64 = 6;
const EAlreadyExpired: u64 = 7;
const EAlreadyAvailable: u64 = 8;
const ELeaseNotExpired: u64 = 9;
```

---

## 第二部分：租赁市场 dApp

```tsx
// src/RentalMarket.tsx
import { useState } from 'react'
import { useSuiClient } from '@mysten/dapp-kit'
import { useQuery } from '@tanstack/react-query'
import { Transaction } from '@mysten/sui/transactions'
import { useDAppKit } from '@mysten/dapp-kit-react'

const RENTAL_PKG = "0x_RENTAL_PACKAGE_"

interface Listing {
  id: string
  item_name: string
  owner: string
  daily_rate_sui: string
  max_days: string
  is_available: boolean
  lease_expires_ms: string
}

function DaysLeftBadge({ expireMs }: { expireMs: number }) {
  const remaining = Math.max(0, expireMs - Date.now())
  const days = Math.ceil(remaining / 86400000)
  if (days === 0) return <span className="badge badge--expired">已到期</span>
  return <span className="badge badge--active">剩余 {days} 天</span>
}

export function RentalMarket() {
  const client = useSuiClient()
  const dAppKit = useDAppKit()
  const [rentDays, setRentDays] = useState(1)
  const [status, setStatus] = useState('')

  const { data: listings } = useQuery({
    queryKey: ['rental-listings'],
    queryFn: async () => {
      // 教学示例：直接读取当前挂单对象。
      // 真实项目里建议通过 indexer 维护“可租挂单”视图，而不是从租用事件反推列表。
      const objects = await client.getOwnedObjects({
        owner: '0x_RENTAL_REGISTRY_OWNER_',
        filter: { StructType: `${RENTAL_PKG}::equipment_rental::RentalListing` },
        options: { showContent: true },
      })
      return objects.data.map(obj => (obj.data?.content as any)?.fields).filter(Boolean) as Listing[]
    },
  })

  const handleRent = async (listingId: string, dailyRate: number) => {
    const tx = new Transaction()
    const totalCost = BigInt(dailyRate * rentDays)
    const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(totalCost)])

    tx.moveCall({
      target: `${RENTAL_PKG}::equipment_rental::rent_item`,
      arguments: [
        tx.object(listingId),
        tx.pure.u64(rentDays),
        payment,
        tx.object('0x6'),
      ],
    })

    try {
      setStatus('⏳ 提交租赁交易...')
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus('✅ 租赁成功！RentalPass 已发送到你的钱包')
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    }
  }

  return (
    <div className="rental-market">
      <h1>🔧 装备租赁市场</h1>
      <p className="subtitle">租而不买，灵活使用高端装备</p>

      <div className="rent-days-selector">
        <label>租期：</label>
        {[1, 3, 7, 14, 30].map(d => (
          <button
            key={d}
            className={rentDays === d ? 'selected' : ''}
            onClick={() => setRentDays(d)}
          >
            {d} 天
          </button>
        ))}
      </div>

      <div className="listings-grid">
        {listings?.map(listing => (
          <div key={listing.id} className="listing-card">
            <h3>{listing.item_name}</h3>
            <div className="listing-meta">
              <span>💰 {Number(listing.daily_rate_sui) / 1e9} SUI/天</span>
              <span>📅 最长 {listing.max_days} 天</span>
            </div>
            <div className="listing-cost">
              租 {rentDays} 天共：<strong>{Number(listing.daily_rate_sui) * rentDays / 1e9} SUI</strong>
            </div>
            {listing.is_available ? (
              <button
                className="rent-btn"
                onClick={() => handleRent(listing.id, Number(listing.daily_rate_sui))}
              >
                🤝 立即租用
              </button>
            ) : (
              <DaysLeftBadge expireMs={Number(listing.lease_expires_ms)} />
            )}
          </div>
        ))}
      </div>

      {status && <p className="status">{status}</p>}
    </div>
  )
}
```

---

## 🎯 关键设计亮点

| 机制 | 实现方式 |
|------|---------|
| 时效控制 | `RentalPass.expires_ms` + `clock.timestamp_ms()` 实时验证 |
| 押金管理 | 30% 租金锁在 `RentalPass.refundable_balance` |
| 提前归还 | 按剩余天数比例退款，其余归出租者 |
| 到期回收 | `reclaim_after_expiry()` 由出租者在到期后调用 |
| 防双租 | `is_available` 标志保证同时只有一个租用者 |

## 📚 关联文档
- [Chapter 7：动态字段与余额管理](./chapter-07.md)
- [Chapter 8：经济系统设计](./chapter-08.md)
