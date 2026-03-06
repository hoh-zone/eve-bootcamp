# 第26章：位置证明协议深度剖析

> **学习目标**：掌握 `world::location` 模块的核心设计——位置哈希、BCS 反序列化、LocationProof 验证，以及在 Builder 扩展中要求玩家"必须在场"的完整实现。

---

> 状态：教学示例。位置证明的消息组织和签名流程会因业务而变，本章重点是解释协议结构和验证边界。

## 最小调用链

`游戏服务器观测位置 -> 生成 LocationProof -> 玩家提交 proof -> 合约反序列化并验证 -> 放行/拒绝业务动作`

## 对应代码目录

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)

## 关键 Struct

| 类型 | 作用 | 阅读重点 |
|------|------|------|
| `Location` | 链上位置哈希容器 | 看链上只保存 hash，不保存明文坐标 |
| `LocationProofMessage` | 服务器签名的位置证明消息体 | 看玩家、源对象、目标对象、距离、deadline 是否全部绑定 |
| `LocationProof` | 链上提交的证明载体 | 看 bytes、签名和消息体如何组合 |

## 关键入口函数

| 入口 | 作用 | 你要确认什么 |
|------|------|------|
| `verify_proximity` | 校验“玩家是否在目标附近” | 是否同时校验签名、目标对象、距离阈值、时间窗 |
| BCS 反序列化路径 | 从 bytes 还原 proof | 字段顺序和链下编码是否完全一致 |
| 业务模块包装入口 | 把 proximity proof 接进 Gate / Turret / Storage | proof 是否绑定具体业务对象而不是通用复用 |

## 最容易误读的点

- 位置证明不是只证明“我在场”，而是证明“我在某个对象附近、在某个时间窗内”
- 只校验距离不校验目标对象，proof 就可能被串用到别的业务入口
- BCS 一旦字段顺序不一致，问题通常不在密码学，而在编码

位置证明最好按协议层来理解，而不是按“一个签名对象”来理解。它至少有 4 层含义：谁在场、相对谁在场、在多长时间窗内有效、这份证明还绑定了哪些业务上下文。真正安全的 Builder 设计，不会只拿 `distance` 一个字段做判断，而是会把 `player_address`、`target_structure_id`、`target_location_hash`、`deadline_ms` 甚至 `data` 里的业务标识一起绑定成一份不可拆分的陈述。

## 1. 位置系统的核心问题

EVE Frontier 的链上合约面临一个根本性挑战：**如何验证一个玩家（飞船）目前位于某个空间位置附近？**

链上合约无法访问游戏世界的实时位置数据。EVE Frontier 的解决方案是**位置证明（LocationProof）**：

```
游戏服务器观测到"玩家 A 在建筑 B 旁边（距离 < 1000m）"
    ↓
服务器将这一"观测事实"签名成一个 LocationProof
    ↓
玩家 A 把这个 proof 提交到链上合约
    ↓
合约验证签名、位置哈希、过期时间后执行业务逻辑
```

---

## 2. LocationProof 数据结构

```move
// world/sources/primitives/location.move

/// 位置哈希（32字节，包含 x/y/z 坐标的混合哈希）
public struct Location has store {
    location_hash: vector<u8>,  // 32 bytes
}

/// 服务器签名的位置证明消息体
public struct LocationProofMessage has copy, drop {
    server_address: address,          // 签名者（服务器地址）
    player_address: address,          // 被证明的玩家钱包地址
    source_structure_id: ID,          // 玩家当前所在结构的 ID
    source_location_hash: vector<u8>, // 玩家所在位置的哈希
    target_structure_id: ID,          // 目标建筑的 ID
    target_location_hash: vector<u8>, // 目标所在位置的哈希  
    distance: u64,                    // 两者之间的距离（游戏单位）
    data: vector<u8>,                 // 存储额外的业务数据
    deadline_ms: u64,                 // 证明的过期时间（毫秒）
}

/// 完整的位置证明（消息体 + 签名）
public struct LocationProof has drop {
    message: LocationProofMessage,
    signature: vector<u8>,
}
```

这里最值得注意的字段其实是 `data`。它的存在不是为了“多塞点备注”，而是为了给不同业务留出扩展绑定位。比如宝箱系统可以把 chest 类型或开启轮次写进去，市场系统可以把 market_id 或订单上下文写进去。这样一份 proof 就不会只是“我在某地”，而是“我在某地，并且这份证明是给某个具体业务入口使用的”。如果放弃这层绑定，proof 很容易在多个入口间被串用。

---

## 3. verify_proximity 函数完整解析

```move
pub fun verify_proximity(
    location: &Location,           // 目标建筑的链上位置对象
    proof: LocationProof,          // 玩家提交的证明
    server_registry: &ServerAddressRegistry, // 授权服务器白名单
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let LocationProof { message, signature } = proof;

    // ① 验证消息字段的合法性
    validate_proof_message(&message, location, server_registry, ctx.sender());

    // ② 将消息结构体序列化为字节（BCS 格式）
    let message_bytes = bcs::to_bytes(&message);

    // ③ 验证 deadline 未过期
    assert!(is_deadline_valid(message.deadline_ms, clock), EDeadlineExpired);

    // ④ 调用 sig_verify 验证 Ed25519 签名
    assert!(
        sig_verify::verify_signature(
            message_bytes,
            signature,
            message.server_address,
        ),
        ESignatureVerificationFailed,
    )
}
```

### validate_proof_message 内部验证

```move
fun validate_proof_message(
    message: &LocationProofMessage,
    expected_location: &Location,
    server_registry: &ServerAddressRegistry,
    sender: address,
) {
    // 1. 服务器地址在白名单中
    assert!(
        access::is_authorized_server_address(server_registry, message.server_address),
        EUnauthorizedServer,
    );

    // 2. 消息中的玩家地址与调用者一致（防止别人用你的证明）
    assert!(message.player_address == sender, EUnverifiedSender);

    // 3. 目标位置哈希与链上 Location 对象匹配
    assert!(
        message.target_location_hash == expected_location.location_hash,
        EInvalidLocationHash,
    );
}
```

**三重验证**保障安全：
1. ✅ 签名来自授权服务器
2. ✅ 证明是为当前调用者颁发的（防抢跑）
3. ✅ 目标位置与链上对象的位置一致（防篡改）

这三重验证解决的是最基本的身份与目标绑定，但 Builder 自己往往还要补第四重验证：**业务绑定**。例如“开这个门”和“开那个宝箱”即使都在同一坐标附近，也不应该共享同一份 proof。最稳妥的做法是让 `data` 或目标对象字段能唯一指向本次业务入口，而不是只依赖空间接近这一件事。

---

## 4. BCS 反序列化：从字节还原 LocationProof

当玩家通过 SDK 提交 `proof_bytes`（原始字节）而非结构体时，合约需要手动反序列化：

```move
pub fun verify_proximity_proof_from_bytes(
    server_registry: &ServerAddressRegistry,
    location: &Location,
    proof_bytes: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 手动 BCS 反序列化
    let (message, signature) = unpack_proof(proof_bytes);
    // ...（之后与 verify_proximity 相同）
}
```

### unpack_proof 的 BCS 手工反序列化

```move
fun unpack_proof(proof_bytes: vector<u8>): (LocationProofMessage, vector<u8>) {
    let mut bcs_data = bcs::new(proof_bytes);

    // 按 BCS 字段顺序逐字段 "peel"（剥取）
    let server_address = bcs_data.peel_address();
    let player_address = bcs_data.peel_address();

    // ID 类型通过 address 还原
    let source_structure_id = object::id_from_address(bcs_data.peel_address());

    // vector<u8> 类型用 peel_vec! 宏
    let source_location_hash = bcs_data.peel_vec!(|bcs| bcs.peel_u8());

    let target_structure_id = object::id_from_address(bcs_data.peel_address());
    let target_location_hash = bcs_data.peel_vec!(|bcs| bcs.peel_u8());
    let distance = bcs_data.peel_u64();
    let data = bcs_data.peel_vec!(|bcs| bcs.peel_u8());
    let deadline_ms = bcs_data.peel_u64();
    let signature = bcs_data.peel_vec!(|bcs| bcs.peel_u8());

    let message = LocationProofMessage {
        server_address, player_address, source_structure_id,
        source_location_hash, target_structure_id, target_location_hash,
        distance, data, deadline_ms,
    };
    (message, signature)
}
```

> **`peel_vec!` 宏**：Move 2024 中处理 BCS 编码的 `vector<u8>` 的标准写法，等价于先读长度，再逐字节读取。

---

## 5. 距离验证

除了"是否在附近"，还支持"两个结构之间的距离是否满足要求"：

```move
pub fun verify_distance(
    location: &Location,
    server_registry: &ServerAddressRegistry,
    proof_bytes: vector<u8>,
    max_distance: u64,           // Builder 设定的最大距离阈值
    ctx: &mut TxContext,
) {
    let (message, signature) = unpack_proof(proof_bytes);
    validate_proof_message(&message, location, server_registry, ctx.sender());
    let message_bytes = bcs::to_bytes(&message);

    // 验证距离不超过 Builder 设定的阈值
    assert!(message.distance <= max_distance, EOutOfRange);

    assert!(
        sig_verify::verify_signature(message_bytes, signature, message.server_address),
        ESignatureVerificationFailed,
    )
}
```

### 同位置验证（无需签名）

```move
/// 验证两个临时库存在同一位置（用于 EVE 太空 P2P 交易）
pub fun verify_same_location(location_a_hash: vector<u8>, location_b_hash: vector<u8>) {
    assert!(location_a_hash == location_b_hash, ENotInProximity);
}
```

---

## 6. Builder 实战：空间限定交易市场

```move
module my_market::space_market;

use world::location::{Self, Location, LocationProof};
use world::access::ServerAddressRegistry;
use sui::clock::Clock;

/// 只有在市场附近的玩家才能购买
pub fun buy_item(
    market: &mut Market,
    market_location: &Location,          // 市场的链上位置对象
    proximity_proof: LocationProof,       // 玩家提交的位置证明
    server_registry: &ServerAddressRegistry,
    payment: Coin<SUI>,
    item_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 验证玩家在市场附近（核心守卫）
    location::verify_proximity(
        market_location,
        proximity_proof,
        server_registry,
        clock,
        ctx,
    );

    // 后续业务逻辑
    // ...
}
```

---

## 7. Builder 实战：位置锁定宝箱

```move
module my_treasure::chest;

use world::location::{Self, Location};
use world::access::ServerAddressRegistry;

/// 只有到达宝箱位置才能打开
pub fun open_chest(
    chest: &mut TreasureChest,
    chest_location: &Location,
    proximity_proof_bytes: vector<u8>,
    server_registry: &ServerAddressRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 使用 bytes 接口（服务器直接传字节，无需在 PTB 中构造结构体）
    location::verify_proximity_proof_from_bytes(
        server_registry,
        chest_location,
        proximity_proof_bytes,
        clock,
        ctx,
    );

    // 开箱！
    let loot = chest.claim_loot(ctx);
    transfer::public_transfer(loot, ctx.sender());
}
```

---

## 8. 位置证明的过期机制

```move
fun is_deadline_valid(deadline_ms: u64, clock: &Clock): bool {
    let current_time_ms = clock.timestamp_ms();
    deadline_ms > current_time_ms
}
```

游戏服务器通常为位置证明设置 **30 秒到 5 分钟**的有效期。过期后，玩家需要重新从服务器申请新的证明。

**设计建议**：
- 一次性行为（如开宝箱）：设置 30 秒有效期
- 持续性行为（如采矿会话）：设置 5 分钟有效期，定期刷新

过期时间本质上是在平衡两件事：安全窗口和交互成本。窗口太长，proof 被截获或被玩家延后使用的风险上升；窗口太短，又会让网络抖动、钱包确认延迟、赞助交易排队变成大量误伤。Builder 设计时不要只问“理论上多短最安全”，还要看真实交易路径里从服务器签名到链上落地通常要多久。

---

## 9. 测试时的特殊处理

由于测试环境无法运行真实的游戏服务器签名，world-contracts 提供了无 deadline 验证的测试版本：

```move
#[test_only]
pub fun verify_proximity_without_deadline(
    server_registry: &ServerAddressRegistry,
    location: &Location,
    proof: LocationProof,
    ctx: &mut TxContext,
): bool {
    let LocationProof { message, signature } = proof;
    validate_proof_message(&message, location, server_registry, ctx.sender());
    let message_bytes = bcs::to_bytes(&message);
    sig_verify::verify_signature(message_bytes, signature, message.server_address)
}
```

在测试中可以预先生成一个固定的"永不过期"签名，绕过时间检查。

---

## 本章小结

| 概念 | 要点 |
|------|------|
| `Location` | 32 字节哈希，由游戏服务器维护 |
| `LocationProof` | 消息体 + Ed25519 签名，有效期有限 |
| 三重验证 | 服务器白名单 + 玩家地址匹配 + 位置哈希匹配 |
| `verify_distance` | 支持两建筑间距离的上限验证 |
| BCS peel 手工反序列化 | 字段顺序必须与结构体定义一致 |

> 下一章：**能量与燃料系统** —— 深入理解 EVE Frontier 建筑运行所需的双层能源机制，以及燃料消耗率的精确计算逻辑。
