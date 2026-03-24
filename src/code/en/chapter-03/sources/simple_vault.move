module my_extension::simple_vault;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::tx_context::TxContext;

// Our Witness type
public struct VaultAuth has drop {}

/// Anyone can deposit items (open deposits)
public fun deposit_item(
    storage_unit: &mut StorageUnit,
    character: &Character,
    item: Item,
    ctx: &mut TxContext,
) {
    // Use VaultAuth{} aswitness，prove this call is a legitimately bound extension
    storage_unit::deposit_item(
        storage_unit,
        character,
        item,
        VaultAuth {},
        ctx,
    )
}

/// Only characters with a specific Badge (NFT) can withdraw items
public fun withdraw_item_with_badge(
    storage_unit: &mut StorageUnit,
    character: &Character,
    _badge: &MemberBadge,  // 必须持有成员勋章才能调用
    type_id: u64,
    ctx: &mut TxContext,
): Item {
    storage_unit::withdraw_item(
        storage_unit,
        character,
        VaultAuth {},
        type_id,
        ctx,
    )
}
