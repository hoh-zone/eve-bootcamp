module chapter_07::snippet_05;

use sui::dynamic_field as df;
use sui::dynamic_object_field as dof;

// 添加动态字段（值不是对象类型）
df::add(&mut inventory.id, b"fuel_amount", 1000u64);

// 读取动态字段
let fuel: &u64 = df::borrow(&inventory.id, b"fuel_amount");
let fuel_mut: &mut u64 = df::borrow_mut(&mut inventory.id, b"fuel_amount");

// 检查是否存在
let exists = df::exists_(&inventory.id, b"fuel_amount");

// 移除动态字段
let old_value: u64 = df::remove(&mut inventory.id, b"fuel_amount");

// 动态对象字段（值本身是一个对象，有独立 ObjectID）
dof::add(&mut storage.id, item_type_id, item_object);
let item = dof::borrow<u64, Item>(&storage.id, item_type_id);
let item = dof::remove<u64, Item>(&mut storage.id, item_type_id);
