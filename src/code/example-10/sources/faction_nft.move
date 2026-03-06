module war_game::faction_nft;

use sui::object::{Self, UID};
use sui::transfer;
use std::string::{Self, String, utf8};

public struct FACTION_NFT has drop {}

/// 势力枚举
const FACTION_ALPHA: u8 = 0;
const FACTION_BETA: u8 = 1;

/// 势力 NFT（入盟证明）
public struct FactionNFT has key, store {
    id: UID,
    faction: u8,                // 0 = Alpha, 1 = Beta
    member_since_ms: u64,
    name: String,
}

public struct WarAdminCap has key, store { id: UID }

public entry fun enlist(
    _admin: &WarAdminCap,
    faction: u8,
    member_name: vector<u8>,
    recipient: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(faction == FACTION_ALPHA || faction == FACTION_BETA, EInvalidFaction);
    let nft = FactionNFT {
        id: object::new(ctx),
        faction,
        member_since_ms: clock.timestamp_ms(),
        name: utf8(member_name),
    };
    transfer::public_transfer(nft, recipient);
}

public fun get_faction(nft: &FactionNFT): u8 { nft.faction }
public fun is_alpha(nft: &FactionNFT): bool { nft.faction == FACTION_ALPHA }
public fun is_beta(nft: &FactionNFT): bool { nft.faction == FACTION_BETA }

const EInvalidFaction: u64 = 0;
