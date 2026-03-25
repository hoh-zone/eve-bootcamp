module chapter_07::snippet_07;

use sui::table::{Self, Table};

public struct Registry has key {
    id: UID,
    members: Table<address, MemberInfo>,
}

// 添加
table::add(&mut registry.members, member_addr, MemberInfo { ... });

// 查询
let info = table::borrow(&registry.members, member_addr);
let info_mut = table::borrow_mut(&mut registry.members, member_addr);

// 存在检查
let is_member = table::contains(&registry.members, member_addr);

// 移除
let old_info = table::remove(&mut registry.members, member_addr);

// 长度
let count = table::length(&registry.members);
