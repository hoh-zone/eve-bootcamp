module chapter_20::snippet_02;

use sui::random::{Self, Random};

public entry fun open_loot_box(
    loot_box: &mut LootBox,
    random: &Random,   // Sui 系统提供的随机数对象
    ctx: &mut TxContext,
): Item {
    let mut rng = random::new_generator(random, ctx);
    let roll = rng.generate_u64() % 100;  // 0-99 均匀分布

    let item_tier = if roll < 60 { 1 }   // 60% 普通
                    else if roll < 90 { 2 } // 30% 稀有
                    else { 3 };             // 10% 史诗

    mint_item(item_tier, ctx)
}
