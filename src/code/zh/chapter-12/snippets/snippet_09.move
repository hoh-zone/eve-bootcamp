module chapter_07::snippet_09;

use sui::event;

// 事件结构体：只需要 copy + drop
public struct GateJumped has copy, drop {
    gate_id: ID,
    character_id: ID,
    destination_gate_id: ID,
    timestamp_ms: u64,
    toll_paid: u64,
}

public struct ItemSold has copy, drop {
    storage_unit_id: ID,
    seller: address,
    buyer: address,
    item_type_id: u64,
    price: u64,
}

// 在函数中发射事件
public fun process_purchase(
    storage_unit: &mut StorageUnit,
    buyer: &Character,
    payment: Coin<SUI>,
    item_type_id: u64,
    ctx: &mut TxContext,
): Item {
    let price = coin::value(&payment);
    // ... 处理购买逻辑 ...

    // 发射事件（无 gas 消耗差异，发射是免费的索引记录）
    event::emit(ItemSold {
        storage_unit_id: object::id(storage_unit),
        seller: storage_unit.owner_address,
        buyer: ctx.sender(),
        item_type_id,
        price,
    });

    // ... 返回物品 ...
}
