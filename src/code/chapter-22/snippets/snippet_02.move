module chapter_22::snippet_02;

let (_receipt) = character::borrow_owner_cap(...); // 暂时忽略
// 更好的做法：确认归还
character::return_owner_cap(own_cap, receipt);
