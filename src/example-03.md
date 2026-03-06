# 实战案例 3：链上拍卖行（智能存储单元 + 荷兰式拍卖）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 将 Smart Storage Unit 改造为荷兰式拍卖（价格随时间递减），物品自动流转给出价者，完整实现拍卖合约 + 竞拍者 dApp + Owner 管理面板。

---

> 状态：已附合约、dApp 与 Move 测试文件。正文已经接近完整案例，适合作为“定价策略 + 前端倒计时”范例。

## 前置依赖

- 建议先读 [Chapter 7](./chapter-07.md)、[Chapter 8](./chapter-08.md)
- 需要本地 `sui` CLI 与 `pnpm`

## 对应代码目录

- [example-03](./code/example-03)
- [example-03/dapp](./code/example-03/dapp)

## 源码位置

- [Move.toml](./code/example-03/Move.toml)
- [auction.move](./code/example-03/sources/auction.move)
- [auction_tests.move](./code/example-03/sources/auction_tests.move)
- [dapp/readme.md](./code/example-03/dapp/readme.md)

## 关键测试文件

- [auction_tests.move](./code/example-03/sources/auction_tests.move)

## 推荐阅读顺序

1. 先看 `auction.move` 的价格递减公式
2. 再读 `auction_tests.move` 校验成交与时间边界
3. 最后启动 dApp 对照倒计时与价格展示

## 最小调用链

`Owner 创建拍卖 -> 时间递减价格 -> 买家支付当前价 -> 拍卖结算 -> 物品流转`

## 验证步骤

1. 在 [example-03](./code/example-03) 运行 `sui move build` 与 `sui move test`
2. 在 [example-03/dapp](./code/example-03/dapp) 运行 `pnpm install && pnpm dev`
3. 人工验证起拍价、最低价、成交后三类状态

## 常见报错

- 前端倒计时与链上当前价格计算不一致
- 最后一秒竞价没有重新读取当前价格

---

## 需求分析

**场景：** 你控制着一个存储着珍稀矿石的智能存储箱。相比固定价格，你希望通过荷兰式拍卖（价格从高到低递减）来最大化销售收益，并让价格发现更加透明：

- 🕐 拍卖开始时以 **5000 LUX** 起拍
- 📉 每 10 分钟降低 **500 LUX**
- 🏆 **最低价为 500 LUX**，价格不再下降
- ⚡ 任何时候有人支付当前价格，物品立即成交
- 📊 dApp 实时显示倒计时和当前价格

---

## 第一部分：Move 合约

### 目录结构

```
dutch-auction/
├── Move.toml
└── sources/
    ├── dutch_auction.move    # 荷兰拍卖逻辑
    └── auction_manager.move  # 拍卖管理（创建/结束）
```

### 核心合约：`dutch_auction.move`

```move
module dutch_auction::auction;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::object::{Self, UID, ID};
use sui::event;
use sui::transfer;

/// SSU 扩展 Witness
public struct AuctionAuth has drop {}

/// 拍卖状态
public struct DutchAuction has key {
    id: UID,
    storage_unit_id: ID,        // 绑定的存储箱
    item_type_id: u64,          // 拍卖的物品类型
    start_price: u64,           // 起始价（MIST）
    end_price: u64,             // 最低价
    start_time_ms: u64,         // 拍卖开始时间
    price_drop_interval_ms: u64, // 每次降价间隔（毫秒）
    price_drop_amount: u64,     // 每次降价幅度
    is_active: bool,            // 是否仍在进行
    proceeds: Balance<SUI>,     // 拍卖收益
    owner: address,             // 拍卖创建者
}

/// 事件
public struct AuctionCreated has copy, drop {
    auction_id: ID,
    item_type_id: u64,
    start_price: u64,
    end_price: u64,
}

public struct AuctionSettled has copy, drop {
    auction_id: ID,
    winner: address,
    final_price: u64,
    item_type_id: u64,
}

// ── 计算当前价格 ─────────────────────────────────────────

public fun current_price(auction: &DutchAuction, clock: &Clock): u64 {
    if !auction.is_active {
        return auction.end_price
    }

    let elapsed_ms = clock.timestamp_ms() - auction.start_time_ms;
    let drops = elapsed_ms / auction.price_drop_interval_ms;
    let total_drop = drops * auction.price_drop_amount;

    if total_drop >= auction.start_price - auction.end_price {
        auction.end_price  // 已降到最低价
    } else {
        auction.start_price - total_drop
    }
}

/// 计算下次降价的剩余时间（毫秒）
public fun ms_until_next_drop(auction: &DutchAuction, clock: &Clock): u64 {
    let elapsed = clock.timestamp_ms() - auction.start_time_ms;
    let interval = auction.price_drop_interval_ms;
    let next_drop_at = (elapsed / interval + 1) * interval;
    next_drop_at - elapsed
}

// ── 创建拍卖 ─────────────────────────────────────────────

public entry fun create_auction(
    storage_unit: &StorageUnit,
    item_type_id: u64,
    start_price: u64,
    end_price: u64,
    price_drop_interval_ms: u64,
    price_drop_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(start_price > end_price, EInvalidPricing);
    assert!(price_drop_amount > 0, EInvalidDropAmount);
    assert!(price_drop_interval_ms >= 60_000, EIntervalTooShort); // 最小1分钟

    let auction = DutchAuction {
        id: object::new(ctx),
        storage_unit_id: object::id(storage_unit),
        item_type_id,
        start_price,
        end_price,
        start_time_ms: clock.timestamp_ms(),
        price_drop_interval_ms,
        price_drop_amount,
        is_active: true,
        proceeds: balance::zero(),
        owner: ctx.sender(),
    };

    event::emit(AuctionCreated {
        auction_id: object::id(&auction),
        item_type_id,
        start_price,
        end_price,
    });

    transfer::share_object(auction);
}

// ── 竞拍：支付当前价格获得物品 ──────────────────────────

public entry fun buy_now(
    auction: &mut DutchAuction,
    storage_unit: &mut StorageUnit,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Item {
    assert!(auction.is_active, EAuctionEnded);

    let price = current_price(auction, clock);
    assert!(coin::value(&payment) >= price, EInsufficientPayment);

    // 退还多付的部分
    let change_amount = coin::value(&payment) - price;
    if change_amount > 0 {
        let change = payment.split(change_amount, ctx);
        transfer::public_transfer(change, ctx.sender());
    }

    // 收入进入拍卖金库
    balance::join(&mut auction.proceeds, coin::into_balance(payment));
    auction.is_active = false;

    event::emit(AuctionSettled {
        auction_id: object::id(auction),
        winner: ctx.sender(),
        final_price: price,
        item_type_id: auction.item_type_id,
    });

    // 从 SSU 取出物品
    storage_unit::withdraw_item(
        storage_unit,
        character,
        AuctionAuth {},
        auction.item_type_id,
        ctx,
    )
}

// ── Owner：提取拍卖收益 ──────────────────────────────────

public entry fun withdraw_proceeds(
    auction: &mut DutchAuction,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == auction.owner, ENotOwner);
    assert!(!auction.is_active, EAuctionStillActive);

    let amount = balance::value(&auction.proceeds);
    let coin = coin::take(&mut auction.proceeds, amount, ctx);
    transfer::public_transfer(coin, ctx.sender());
}

// ── Owner：取消拍卖 ──────────────────────────────────────

public entry fun cancel_auction(
    auction: &mut DutchAuction,
    storage_unit: &mut StorageUnit,
    character: &Character,
    ctx: &mut TxContext,
): Item {
    assert!(ctx.sender() == auction.owner, ENotOwner);
    assert!(auction.is_active, EAuctionAlreadyEnded);

    auction.is_active = false;

    // 将物品取回给 Owner
    storage_unit::withdraw_item(
        storage_unit, character, AuctionAuth {}, auction.item_type_id, ctx,
    )
}

// 错误码
const EInvalidPricing: u64 = 0;
const EInvalidDropAmount: u64 = 1;
const EIntervalTooShort: u64 = 2;
const EAuctionEnded: u64 = 3;
const EInsufficientPayment: u64 = 4;
const EAuctionStillActive: u64 = 5;
const EAuctionAlreadyEnded: u64 = 6;
const ENotOwner: u64 = 7;
```

---

## 第二部分：单元测试

```move
#[test_only]
module dutch_auction::auction_tests;

use dutch_auction::auction;
use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;

#[test]
fun test_price_decreases_over_time() {
    let mut scenario = test_scenario::begin(@0xOwner);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 设置0时刻
    clock.set_for_testing(0);

    // 创建伪造拍卖对象测试价格计算
    let auction = auction::create_test_auction(
        5000,   // start_price
        500,    // end_price
        600_000, // 10分钟 (ms)
        500,    // 每次降 500
        &clock,
        scenario.ctx(),
    );

    // 时刻 0：价格应为 5000
    assert!(auction::current_price(&auction, &clock) == 5000, 0);

    // 经过 10 分钟：价格应为 4500
    clock.set_for_testing(600_000);
    assert!(auction::current_price(&auction, &clock) == 4500, 0);

    // 经过 90 分钟（降价9次 × 500 = 4500，但最低 500）：价格应为 500
    clock.set_for_testing(5_400_000);
    assert!(auction::current_price(&auction, &clock) == 500, 0);

    clock.destroy_for_testing();
    auction.destroy_test_auction();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = auction::EInsufficientPayment)]
fun test_underpayment_fails() {
    // ...测试支付不足时的失败路径
}
```

---

## 第三部分：竞拍者 dApp

```tsx
// src/AuctionApp.tsx
import { useState, useEffect, useCallback } from 'react'
import { useConnection, getObjectWithJson } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

const DUTCH_PACKAGE = "0x_DUTCH_PACKAGE_"
const AUCTION_ID = "0x_AUCTION_ID_"
const STORAGE_UNIT_ID = "0x..."
const CHARACTER_ID = "0x..."
const CLOCK_OBJECT_ID = "0x6"

interface AuctionState {
  start_price: string
  end_price: string
  start_time_ms: string
  price_drop_interval_ms: string
  price_drop_amount: string
  is_active: boolean
  item_type_id: string
}

function calculateCurrentPrice(state: AuctionState): number {
  if (!state.is_active) return Number(state.end_price)

  const now = Date.now()
  const elapsed = now - Number(state.start_time_ms)
  const drops = Math.floor(elapsed / Number(state.price_drop_interval_ms))
  const totalDrop = drops * Number(state.price_drop_amount)
  const maxDrop = Number(state.start_price) - Number(state.end_price)

  if (totalDrop >= maxDrop) return Number(state.end_price)
  return Number(state.start_price) - totalDrop
}

function msUntilNextDrop(state: AuctionState): number {
  const now = Date.now()
  const elapsed = now - Number(state.start_time_ms)
  const interval = Number(state.price_drop_interval_ms)
  return interval - (elapsed % interval)
}

export function AuctionApp() {
  const { isConnected, handleConnect } = useConnection()
  const dAppKit = useDAppKit()
  const [auctionState, setAuctionState] = useState<AuctionState | null>(null)
  const [currentPrice, setCurrentPrice] = useState(0)
  const [countdown, setCountdown] = useState(0)
  const [status, setStatus] = useState('')
  const [isBuying, setIsBuying] = useState(false)

  // 加载拍卖状态
  const loadAuction = useCallback(async () => {
    const obj = await getObjectWithJson(AUCTION_ID)
    if (obj?.content?.dataType === 'moveObject') {
      const fields = obj.content.fields as AuctionState
      setAuctionState(fields)
    }
  }, [])

  useEffect(() => {
    loadAuction()
  }, [loadAuction])

  // 每秒更新价格倒计时
  useEffect(() => {
    if (!auctionState) return
    const timer = setInterval(() => {
      setCurrentPrice(calculateCurrentPrice(auctionState))
      setCountdown(msUntilNextDrop(auctionState))
    }, 1000)
    return () => clearInterval(timer)
  }, [auctionState])

  const handleBuyNow = async () => {
    if (!isConnected) { setStatus('请先连接钱包'); return }
    setIsBuying(true)
    setStatus('⏳ 提交交易...')

    try {
      const tx = new Transaction()
      const [paymentCoin] = tx.splitCoins(tx.gas, [
        tx.pure.u64(currentPrice + 1_000) // 略多于当前价，防止最后一秒涨价
      ])

      tx.moveCall({
        target: `${DUTCH_PACKAGE}::auction::buy_now`,
        arguments: [
          tx.object(AUCTION_ID),
          tx.object(STORAGE_UNIT_ID),
          tx.object(CHARACTER_ID),
          paymentCoin,
          tx.object(CLOCK_OBJECT_ID),
        ],
      })

      const result = await dAppKit.signAndExecuteTransaction({ transaction: tx })
      setStatus(`🏆 竞拍成功！Tx: ${result.digest.slice(0, 12)}...`)
      await loadAuction()
    } catch (e: any) {
      setStatus(`❌ ${e.message}`)
    } finally {
      setIsBuying(false)
    }
  }

  const countdownSec = Math.ceil(countdown / 1000)
  const priceInSui = (currentPrice / 1e9).toFixed(2)
  const nextPriceSui = (
    Math.max(Number(auctionState?.end_price ?? 0), currentPrice - Number(auctionState?.price_drop_amount ?? 0)) / 1e9
  ).toFixed(2)

  return (
    <div className="auction-app">
      <header>
        <h1>🔨 荷兰式拍卖行</h1>
        {!isConnected
          ? <button onClick={handleConnect}>连接钱包</button>
          : <span className="connected">✅ 已连接</span>
        }
      </header>

      {auctionState ? (
        <div className="auction-board">
          <div className="current-price">
            <span className="label">当前价格</span>
            <span className="price">{priceInSui} SUI</span>
          </div>

          <div className="countdown">
            <span className="label">⏳ {countdownSec} 秒后降为</span>
            <span className="next-price">{nextPriceSui} SUI</span>
          </div>

          <div className="info-row">
            <span>起拍价：{(Number(auctionState.start_price) / 1e9).toFixed(2)} SUI</span>
            <span>最低价：{(Number(auctionState.end_price) / 1e9).toFixed(2)} SUI</span>
          </div>

          {auctionState.is_active ? (
            <button
              className="buy-btn"
              onClick={handleBuyNow}
              disabled={isBuying || !isConnected}
            >
              {isBuying ? '⏳ 购买中...' : `💰 立即购买 ${priceInSui} SUI`}
            </button>
          ) : (
            <div className="sold-banner">🎉 已售出</div>
          )}

          {status && <p className="tx-status">{status}</p>}
        </div>
      ) : (
        <div>加载拍卖信息...</div>
      )}
    </div>
  )
}
```

---

## 🎯 完整回顾

```
合约层
├── create_auction() → 创建共享 DutchAuction 对象
├── current_price()  → 根据时间计算当前价格（纯计算，不修改状态）
├── buy_now()        → 支付 → 收益入金库 → SSU 取出物品 → 发事件
├── cancel_auction() → Owner 取消，物品归还
└── withdraw_proceeds() → Owner 提取拍卖收益

dApp 层
├── 每秒重新计算价格（纯前端，不消耗 Gas）
├── 倒计时显示下次降价时间
└── 一键购买，自动附上当前价格
```

---

## 🔧 扩展练习

1. 支持批量拍卖：同时拍卖多种物品，每种独立倒计时
2. 预约购买：玩家设定目标价格，自动在达到时触发购买（链下监听 + 定时提交）
3. 历史成交记录：监听 `AuctionSettled` 事件展示近期成交数据

---

## 📚 关联文档

- [Chapter 7：事件系统](./chapter-07.md#74-事件系统events)
- [Chapter 8：定价策略](./chapter-08.md#84-动态定价策略)
- [Smart Storage Unit](https://github.com/evefrontier/builder-documentation/blob/main/smart-assemblies/storage-unit/README.md)
