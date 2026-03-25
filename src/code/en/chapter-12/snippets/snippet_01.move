module chapter_07::snippet_01;

// T 是类型参数，类似其他语言的 <T>
public struct Box<T: store> has key, store {
    id: UID,
    value: T,
}

// 泛型函数
public fun wrap<T: store>(value: T, ctx: &mut TxContext): Box<T> {
    Box { id: object::new(ctx), value }
}

public fun unwrap<T: store>(box: Box<T>): T {
    let Box { id, value } = box;
    id.delete();
    value
}
