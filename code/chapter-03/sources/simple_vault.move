module my_extension::simple_vault;

use world::storage_unit::{Self, StorageUnit};
use world::character::Character;
use world::inventory::Item;
use sui::tx_context::TxContext;

// 我们的 Witness 类型
public struct VaultAuth has drop {}

/// 任何人都可以存入物品（开放存款）
public entry fun deposit_item(
    storage_unit: &mut StorageUnit,
    character: &Character,
    item: Item,
    ctx: &mut TxContext,
) {
    // 使用 VaultAuth{} 作为见证，证明这个调用是合法绑定的扩展
    storage_unit::deposit_item(
        storage_unit,
        character,
        item,
        VaultAuth {},
        ctx,
    )
}

/// 只有拥有特定 Badge（NFT）的角色才能取出物品
public entry fun withdraw_item_with_badge(
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
