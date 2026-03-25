module chapter_06::snippet_05;

public fun verify_owner_cap<T: key>(
    obj: &T,
    owner_cap: &OwnerCap<T>,
) {
    // authorized_object_id 确保这个 OwnerCap 只能用于对应的那个对象
    assert!(
        owner_cap.authorized_object_id == object::id(obj),
        EOwnerCapMismatch
    );
}
