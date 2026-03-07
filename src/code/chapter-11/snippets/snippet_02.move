module chapter_06::snippet_02;

public struct OwnerCap<phantom T> has key {
    id: UID,
    authorized_object_id: ID,  // 只对这一个具体对象有效
}
