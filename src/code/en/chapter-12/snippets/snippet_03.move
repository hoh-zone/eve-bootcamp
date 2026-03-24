module chapter_07::snippet_03;

// T Must同时具有 key and store abilities
public fun transfer_to_object<T: key + store, Container: key>(
    container: &mut Container,
    value: T,
) { ... }

// T Must具有 copy and drop（临时值，不是资产）
public fun log_value<T: copy + drop>(value: T) { ... }
