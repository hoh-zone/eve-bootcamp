module ally_dao::governance;

use ally_dao::ally_token::ALLY_TOKEN;
use sui::coin::Coin;
use sui::object::{Self, UID};
use sui::clock::Clock;
use sui::transfer;
use sui::event;

public struct Proposal has key {
    id: UID,
    proposer: address,
    description: vector<u8>,
    vote_yes: u64,
    vote_no: u64,
    deadline_ms: u64,
    executed: bool,
}

/// 创建提案（需要持有最少 1000 ALLY Token）
public entry fun create_proposal(
    ally_coin: &Coin<ALLY_TOKEN>,
    description: vector<u8>,
    voting_duration_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 需要持有足够代币才能发起提案
    assert!(sui::coin::value(ally_coin) >= 1_000_000_000, EInsufficientToken); // 1000 ALLY

    let proposal = Proposal {
        id: object::new(ctx),
        proposer: ctx.sender(),
        description,
        vote_yes: 0,
        vote_no: 0,
        deadline_ms: clock.timestamp_ms() + voting_duration_ms,
        executed: false,
    };

    transfer::share_object(proposal);
}

/// 投票（用 ALLY Token 数量加权）
public entry fun vote(
    proposal: &mut Proposal,
    ally_coin: &Coin<ALLY_TOKEN>,
    support: bool,
    clock: &Clock,
    _ctx: &TxContext,
) {
    assert!(clock.timestamp_ms() < proposal.deadline_ms, EVotingEnded);

    let weight = sui::coin::value(ally_coin);
    if (support) {
        proposal.vote_yes = proposal.vote_yes + weight;
    } else {
        proposal.vote_no = proposal.vote_no + weight;
    };
}

const EInsufficientToken: u64 = 0;
const EVotingEnded: u64 = 1;
