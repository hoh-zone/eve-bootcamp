module chapter_07::snippet_08;

use sui::vec_map::{Self, VecMap};

// VecMap 存储在对象字段中（不是动态字段），适合小数据集
public struct Config has key {
    id: UID,
    toll_settings: VecMap<u64, u64>,  // zone_id -> toll_amount
}

// 操作
vec_map::insert(&mut config.toll_settings, zone_id, amount);
let amount = vec_map::get(&config.toll_settings, &zone_id);
vec_map::remove(&mut config.toll_settings, &zone_id);
