module war_game::mining_depot;

use war_game::faction_nft::{Self, FactionNFT};
use war_game::war_token::WAR_TOKEN;
use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use sui::coin::{Self, TreasuryCap};
use sui::clock::Clock;
use sui::object::{Self, UID};
use sui::event;

public struct MiningAuth has drop {}

/// 矿区状态
public struct MiningDepot has key {
    id: UID,
    resource_count: u64,       // 当前可采数量
    last_refresh_ms: u64,      // 上次刷新时间
    refresh_amount: u64,       // 每次刷新补充量
    refresh_interval_ms: u64,  // 刷新间隔
    alpha_total_mined: u64,
    beta_total_mined: u64,
}

public struct ResourceMined has copy, drop {
    miner: address,
    faction: u8,
    amount: u64,
    faction_total: u64,
}

/// 采矿（同时检查势力 NFT 并发放 WAR Token 奖励）
public entry fun mine(
    depot: &mut MiningDepot,
    storage_unit: &mut StorageUnit,
    character: &Character,
    faction_nft: &FactionNFT,       // 需要势力认证
    war_treasury: &mut TreasuryCap<WAR_TOKEN>,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 自动刷新资源
    maybe_refresh(depot, clock);

    assert!(amount > 0 && amount <= depot.resource_count, EInsufficientResource);

    depot.resource_count = depot.resource_count - amount;

    // 根据势力更新统计
    let faction = faction_nft::get_faction(faction_nft);
    if faction == 0 {
        depot.alpha_total_mined = depot.alpha_total_mined + amount;
    } else {
        depot.beta_total_mined = depot.beta_total_mined + amount;
    };

    // 取出资源（从 SSU）
    // storage_unit::withdraw_batch(storage_unit, character, MiningAuth {}, RESOURCE_TYPE_ID, amount, ctx)

    // 发放 WAR Token 奖励（每单位资源 = 10 WAR）
    let war_reward = amount * 10_000_000; // 10 WAR per unit，6 decimals
    let war_coin = sui::coin::mint(war_treasury, war_reward, ctx);
    sui::transfer::public_transfer(war_coin, ctx.sender());

    event::emit(ResourceMined {
        miner: ctx.sender(),
        faction,
        amount,
        faction_total: if faction == 0 { depot.alpha_total_mined } else { depot.beta_total_mined },
    });
}

fun maybe_refresh(depot: &mut MiningDepot, clock: &Clock) {
    let now = clock.timestamp_ms();
    if now >= depot.last_refresh_ms + depot.refresh_interval_ms {
        depot.resource_count = depot.resource_count + depot.refresh_amount;
        depot.last_refresh_ms = now;
    }
}

const EInsufficientResource: u64 = 0;
