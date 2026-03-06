module war_game::faction_gate;

use war_game::faction_nft::{Self, FactionNFT};
use world::gate::{Self, Gate};
use world::character::Character;
use sui::clock::Clock;
use sui::tx_context::TxContext;

public struct AlphaGateAuth has drop {}
public struct BetaGateAuth has drop {}

/// Alpha 联盟星门：只允许 Alpha 成员通过
public entry fun alpha_gate_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    faction_nft: &FactionNFT,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction_nft::is_alpha(faction_nft), EWrongFaction);
    gate::issue_jump_permit(
        source_gate, dest_gate, character, AlphaGateAuth {},
        clock.timestamp_ms() + 30 * 60 * 1000, ctx,
    );
}

/// Beta 联盟星门
public entry fun beta_gate_jump(
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    faction_nft: &FactionNFT,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction_nft::is_beta(faction_nft), EWrongFaction);
    gate::issue_jump_permit(
        source_gate, dest_gate, character, BetaGateAuth {},
        clock.timestamp_ms() + 30 * 60 * 1000, ctx,
    );
}

const EWrongFaction: u64 = 0;
