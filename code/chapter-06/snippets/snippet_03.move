module chapter_06::snippet_03;

// Character 模块提供的接口
public fun borrow_owner_cap<T: key>(
    character: &mut Character,
    owner_cap_ticket: Receiving<OwnerCap<T>>,  // 使用 Receiving 模式
    ctx: &TxContext,
): (OwnerCap<T>, ReturnOwnerCapReceipt)        // 返回 Cap + 热土豆收据

public fun return_owner_cap<T: key>(
    character: &Character,
    owner_cap: OwnerCap<T>,
    receipt: ReturnOwnerCapReceipt,             // 必须消耗收据
)
