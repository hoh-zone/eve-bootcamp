module chapter_14::snippet_07;

// 飞船装备 NFT（被飞船objecthold）
public struct Equipment has key, store {
    id: UID,
    name: String,
    stat_bonus: u64,
}

public struct Ship has key {
    id: UID,
    // Equipment 被嵌入 Ship object中（object拥有object）
    equipped_items: vector<Equipment>,
}

// 为飞船装备item
public fun equip(
    ship: &mut Ship,
    equipment: Equipment,  // Equipment 从玩家钱包移入 Ship
    ctx: &TxContext,
) {
    vector::push_back(&mut ship.equipped_items, equipment);
}
