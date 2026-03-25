module chapter_03::snippet_06;

public struct NetworkNode has key, store {
    id: UID,
}

public struct Assembly has key, store {
    id: UID,
}

// 没有任何 ability = 热土豆，必须在本次 tx 中处理掉
public struct NetworkCheckReceipt {}

public fun check_network(_node: &NetworkNode): NetworkCheckReceipt {
    // 执行检查...
    NetworkCheckReceipt {}  // 返回热土豆
}

public fun complete_action(
    _assembly: &mut Assembly,
    receipt: NetworkCheckReceipt,  // 必须传入，保证检查被执行过
) {
    let NetworkCheckReceipt {} = receipt; // 消耗热土豆
    // 正式执行操作
}
