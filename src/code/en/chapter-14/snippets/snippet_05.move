module chapter_08::snippet_05;

public fun calculate_price(
    base_price: u64,
    buyer: address,
    member_registry: &Table<address, MemberTier>,
): u64 {
    if table::contains(member_registry, buyer) {
        let tier = table::borrow(member_registry, buyer);
        match (tier) {
            MemberTier::Gold => base_price * 80 / 100,   // 8折
            MemberTier::Silver => base_price * 90 / 100, // 9折
            _ => base_price,
        }
    } else {
        base_price
    }
}
