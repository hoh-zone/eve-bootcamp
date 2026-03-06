module chapter_04::snippet_01;

public struct Character has key {
    id: UID,                        // 唯一对象 ID
    // 每个拥有的资产对应一个 OwnerCap
    // owner_caps 以 dynamic field 形式存储
}
