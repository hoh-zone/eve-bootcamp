module chapter_07::snippet_03;

// T 必须同时具有 key 和 store abilities
public fun transfer_to_object<T: key + store, Container: key>(
    container: &mut Container,
    value: T,
) { ... }

// T 必须具有 copy 和 drop（临时值，不是资产）
public fun log_value<T: copy + drop>(value: T) { ... }
