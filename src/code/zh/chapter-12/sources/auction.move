module my_auction::auction;

use sui::object::{Self, UID, ID};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::dynamic_field as df;
use sui::event;
use sui::transfer;

// ── 常量 ──────────────────────────────────────────────────

const STATUS_OPEN: u8 = 0;
const STATUS_ENDED: u8 = 1;
const STATUS_CANCELLED: u8 = 2;

const EAuctionNotOpen: u64 = 0;
const EAuctionEnded: u64 = 1;
const EBidTooLow: u64 = 2;
const ENotSeller: u64 = 3;
const EAuctionStillOpen: u64 = 4;

// ── 数据结构 ───────────────────────────────────────────────

/// 竞价历史记录（动态字段存储，避免大对象）
public struct BidRecord has store, drop {
    bidder: address,
    amount: u64,
    timestamp_ms: u64,
}

/// 拍卖对象（使用 SUI token 竞拍）
public struct Auction has key {
    id: UID,
    seller: address,
    status: u8,
    min_bid: u64,
    current_bid: u64,
    current_winner: Option<address>,
    end_time_ms: u64,
    bid_history_count: u64,
    escrowed_bids: Balance<SUI>, // 所有竞价款暂存于此
}

/// 竞价事件
public struct BidPlaced has copy, drop {
    auction_id: ID,
    bidder: address,
    amount: u64,
    timestamp_ms: u64,
}

/// 拍卖결束事件
public struct AuctionEnded has copy, drop {
    auction_id: ID,
    winner: Option<address>,
    final_bid: u64,
}

// ── 创建拍卖 ──────────────────────────────────────────────

public fun create_auction(
    min_bid: u64,
    duration_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let auction = Auction {
        id: object::new(ctx),
        seller: ctx.sender(),
        status: STATUS_OPEN,
        min_bid,
        current_bid: min_bid,
        current_winner: option::none(),
        end_time_ms: clock.timestamp_ms() + duration_ms,
        bid_history_count: 0,
        escrowed_bids: balance::zero(),
    };
    transfer::share_object(auction);
}

// ── 竞价 ──────────────────────────────────────────────────

public fun place_bid(
    auction: &mut Auction,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let bid_amount = coin::value(&payment);
    let now = clock.timestamp_ms();

    assert!(auction.status == STATUS_OPEN, EAuctionNotOpen);
    assert!(now < auction.end_time_ms, EAuctionEnded);
    assert!(bid_amount > auction.current_bid, EBidTooLow);

    // 将竞价款存入托管
    balance::join(&mut auction.escrowed_bids, coin::into_balance(payment));

    // 更新当前最高价
    auction.current_bid = bid_amount;
    auction.current_winner = option::some(ctx.sender());

    // 记录竞价历史（动态字段）
    let bid_key = auction.bid_history_count;
    auction.bid_history_count = bid_key + 1;
    df::add(&mut auction.id, bid_key, BidRecord {
        bidder: ctx.sender(),
        amount: bid_amount,
        timestamp_ms: now,
    });

    event::emit(BidPlaced {
        auction_id: object::id(auction),
        bidder: ctx.sender(),
        amount: bid_amount,
        timestamp_ms: now,
    });
}

// ── 结束拍卖 ──────────────────────────────────────────────

public fun end_auction(
    auction: &mut Auction,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(auction.status == STATUS_OPEN, EAuctionNotOpen);
    assert!(clock.timestamp_ms() >= auction.end_time_ms, EAuctionStillOpen);

    auction.status = STATUS_ENDED;
    let final_bid = auction.current_bid;
    let winner = auction.current_winner;

    // 将竞价款转给卖家
    let proceeds = balance::withdraw_all(&mut auction.escrowed_bids);
    if (balance::value(&proceeds) > 0) {
        transfer::public_transfer(coin::from_balance(proceeds, ctx), auction.seller);
    } else {
        balance::destroy_zero(proceeds);
    };

    event::emit(AuctionEnded {
        auction_id: object::id(auction),
        winner,
        final_bid,
    });
}

// ── 取消拍卖（无人出价时卖家可取消）────────────────────

public fun cancel_auction(
    auction: &mut Auction,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == auction.seller, ENotSeller);
    assert!(auction.status == STATUS_OPEN, EAuctionNotOpen);
    assert!(option::is_none(&auction.current_winner), EBidTooLow); // 已有人出价则不能取消

    auction.status = STATUS_CANCELLED;
}
