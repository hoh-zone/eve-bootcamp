module competition::weekly_race;

use sui::table::{Self, Table};
use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use sui::transfer;
use std::string::utf8;

// ── 常量 ──────────────────────────────────────────────────

const WEEK_DURATION_MS: u64 = 7 * 24 * 60 * 60 * 1000; // 7 天

// ── 数据结构 ───────────────────────────────────────────────

/// 竞赛（每周创建一个新的）
public struct Race has key {
    id: UID,
    season: u64,              // 第几届
    start_time_ms: u64,
    end_time_ms: u64,
    scores: Table<address, u64>,  // 玩家地址 → 积分
    top3: vector<address>,        // 前三名（结算后填充）
    is_settled: bool,
    prize_pool_sui: Balance<SUI>,
    admin: address,
}

/// 奖杯 NFT
public struct TrophyNFT has key, store {
    id: UID,
    season: u64,
    rank: u8,      // 1, 2, 3
    score: u64,
    winner: address,
    image_url: String,
}

public struct RaceAdminCap has key, store { id: UID }

// ── 事件 ──────────────────────────────────────────────────

public struct ScoreUpdated has copy, drop {
    race_id: ID,
    player: address,
    new_score: u64,
}

public struct RaceSettled has copy, drop {
    race_id: ID,
    season: u64,
    winner: address,
    second: address,
    third: address,
}

// ── 初始化 ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::transfer(RaceAdminCap { id: object::new(ctx) }, ctx.sender());
}

/// 创建新一届竞赛
public entry fun create_race(
    _cap: &RaceAdminCap,
    season: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let start = clock.timestamp_ms();
    let race = Race {
        id: object::new(ctx),
        season,
        start_time_ms: start,
        end_time_ms: start + WEEK_DURATION_MS,
        scores: table::new(ctx),
        top3: vector::empty(),
        is_settled: false,
        prize_pool_sui: balance::zero(),
        admin: ctx.sender(),
    };
    transfer::share_object(race);
}

/// 充值奖池
public entry fun fund_prize_pool(
    race: &mut Race,
    _cap: &RaceAdminCap,
    coin: Coin<SUI>,
) {
    balance::join(&mut race.prize_pool_sui, coin::into_balance(coin));
}

// ── 积分上报（由赛事服务器或炮塔/星门扩展调用） ────────────

public entry fun report_score(
    race: &mut Race,
    player: address,
    score_delta: u64,    // 本次增加的积分
    clock: &Clock,
    admin_acl: &AdminACL, // 需要游戏服务器签名
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);         // 验证是授权服务器
    assert!(!race.is_settled, ERaceEnded);
    assert!(clock.timestamp_ms() <= race.end_time_ms, ERaceEnded);

    if !table::contains(&race.scores, player) {
        table::add(&mut race.scores, player, 0u64);
    };

    let score = table::borrow_mut(&mut race.scores, player);
    *score = *score + score_delta;

    event::emit(ScoreUpdated {
        race_id: object::id(race),
        player,
        new_score: *score,
    });
}

// ── 结算（需要链下算出前三名后传入）────────────────────────

public entry fun settle_race(
    race: &mut Race,
    _cap: &RaceAdminCap,
    first: address,
    second: address,
    third: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(!race.is_settled, EAlreadySettled);
    assert!(clock.timestamp_ms() >= race.end_time_ms, ERaceNotEnded);

    // 验证链上积分（防止传入假排名）
    let s1 = *table::borrow(&race.scores, first);
    let s2 = *table::borrow(&race.scores, second);
    let s3 = *table::borrow(&race.scores, third);
    assert!(s1 >= s2 && s2 >= s3, EInvalidRanking);

    race.is_settled = true;
    race.top3 = vector[first, second, third];

    // 分发奖池：50% 给第一，30% 给第二，20% 给第三
    let total = balance::value(&race.prize_pool_sui);
    let prize1 = coin::take(&mut race.prize_pool_sui, total * 50 / 100, ctx);
    let prize2 = coin::take(&mut race.prize_pool_sui, total * 30 / 100, ctx);
    let prize3 = coin::take(&mut race.prize_pool_sui, balance::value(&race.prize_pool_sui), ctx);

    transfer::public_transfer(prize1, first);
    transfer::public_transfer(prize2, second);
    transfer::public_transfer(prize3, third);

    // 铸造奖杯 NFT
    mint_trophy(race.season, 1, s1, first, ctx);
    mint_trophy(race.season, 2, s2, second, ctx);
    mint_trophy(race.season, 3, s3, third, ctx);

    event::emit(RaceSettled {
        race_id: object::id(race),
        season: race.season,
        winner: first, second, third,
    });
}

fun mint_trophy(
    season: u64,
    rank: u8,
    score: u64,
    winner: address,
    ctx: &mut TxContext,
) {
    let (name, image_url) = match(rank) {
        1 => (b"Champion Trophy", b"https://assets.example.com/trophies/gold.png"),
        2 => (b"Elite Trophy", b"https://assets.example.com/trophies/silver.png"),
        _ => (b"Contender Trophy", b"https://assets.example.com/trophies/bronze.png"),
    };

    let trophy = TrophyNFT {
        id: object::new(ctx),
        season,
        rank,
        score,
        winner,
        image_url: utf8(image_url),
    };

    transfer::public_transfer(trophy, winner);
}

const ERaceEnded: u64 = 0;
const EAlreadySettled: u64 = 1;
const ERaceNotEnded: u64 = 2;
const EInvalidRanking: u64 = 3;
