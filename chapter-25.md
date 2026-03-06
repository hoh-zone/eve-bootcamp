# 第25章：链下签名 × 链上验证

> **学习目标**：深入理解 `world::sig_verify` 模块的 Ed25519 签名验证机制，掌握"游戏服务器签名 → Move 合约验证"这一 EVE Frontier 的核心安全模式。

---

## 1. 为什么需要链下签名？

EVE Frontier 的一个根本性挑战：**链上合约无法访问游戏世界的实时状态**。

| 信息 | 来源 | 合约可直接读取？ |
|------|------|----------|
| 玩家的舰船位置坐标 | 游戏服务器实时计算 | ❌ |
| 某玩家是否在某建筑附近 | 游戏物理引擎 | ❌ |
| 今天的 PvP 击杀结果 | 游戏战斗服务器 | ❌ |
| 链上对象的状态 | Sui 状态树 | ✅ |

**解决方案**：游戏服务器在链下将这些"事实"签名成一个消息，玩家把这个签名提交给合约，合约验证签名的真实性。

---

## 2. Ed25519 签名格式

Sui 使用标准的 Ed25519 + 个人消息签名格式。

### 签名的组成

```
signature (97 bytes total):
┌─────────┬───────────────────┬──────────────────┐
│  flag   │    raw_sig        │   public_key     │
│ 1 byte  │    64 bytes       │   32 bytes       │
│ (0x00)  │  (Ed25519 sig)    │  (Ed25519 PK)    │
└─────────┴───────────────────┴──────────────────┘
```

### 常量定义（来自源码）

```move
const ED25519_FLAG: u8 = 0x00;   // Ed25519 scheme 标识符
const ED25519_SIG_LEN: u64 = 64; // 签名长度
const ED25519_PK_LEN: u64 = 32;  // 公钥长度
```

---

## 3. 源码精读：`sig_verify.move`

### 3.1 从公钥派生 Sui 地址

```move
pub fun derive_address_from_public_key(public_key: vector<u8>): address {
    assert!(public_key.length() == ED25519_PK_LEN, EInvalidPublicKeyLen);

    // Sui 地址 = Blake2b256(flag_byte || public_key)
    let mut concatenated: vector<u8> = vector::singleton(ED25519_FLAG);
    concatenated.append(public_key);

    sui::address::from_bytes(hash::blake2b256(&concatenated))
}
```

**公式**：`sui_address = Blake2b256(0x00 || ed25519_public_key)`

这意味着如果你知道游戏服务器的 Ed25519 公钥，你就能预知它的 Sui 地址。

### 3.2 PersonalMessage Intent 前缀

```move
// x"030000" 是三个字节：
// 0x03 = IntentScope::PersonalMessage
// 0x00 = IntentVersion::V0
// 0x00 = AppId::Sui
let mut message_with_intent = x"030000";
message_with_intent.append(message);
let digest = hash::blake2b256(&message_with_intent);
```

> ⚠️ **重要细节**：消息是**直接附加**的（不经过 BCS 序列化），这与 Sui 钱包签名的默认行为不同。原因是游戏服务器的 Go/TypeScript 端使用 `SignPersonalMessage` 的方式直接操作字节。

### 3.3 完整验证流程

```move
pub fun verify_signature(
    message: vector<u8>,
    signature: vector<u8>,
    expected_address: address,
): bool {
    let len = signature.length();
    assert!(len >= 1, EInvalidLen);

    // 1. 从第一个字节提取 scheme flag
    let flag = signature[0];

    // 2. Move 2024 match 语法（类似 Rust）
    let (sig_len, pk_len) = match (flag) {
        ED25519_FLAG => (ED25519_SIG_LEN, ED25519_PK_LEN),
        _ => abort EUnsupportedScheme,
    };

    assert!(len == 1 + sig_len + pk_len, EInvalidLen);

    // 3. 切分签名字节
    let raw_sig = extract_bytes(&signature, 1, 1 + sig_len);
    let raw_public_key = extract_bytes(&signature, 1 + sig_len, len);

    // 4. 构造带 intent 前缀的消息摘要
    let mut message_with_intent = x"030000";
    message_with_intent.append(message);
    let digest = hash::blake2b256(&message_with_intent);

    // 5. 验证公钥对应的 Sui 地址
    let sig_address = derive_address_from_public_key(raw_public_key);
    if (sig_address != expected_address) {
        return false
    };

    // 6. 验证 Ed25519 签名
    match (flag) {
        ED25519_FLAG => {
            ed25519::ed25519_verify(&raw_sig, &raw_public_key, &digest)
        },
        _ => abort EUnsupportedScheme,
    }
}
```

### 3.4 字节提取辅助函数

```move
// Move 2024 的 vector::tabulate! 宏：简洁地创建切片
fun extract_bytes(source: &vector<u8>, start: u64, end: u64): vector<u8> {
    vector::tabulate!(end - start, |i| source[start + i])
}
```

---

## 4. 端到端流程

```
游戏服务器（Go/Node.js）
    │
    ├─ 构造消息：message = bcs_encode(LocationProofMessage)
    ├─ 添加 intent 前缀：msg_with_intent = 0x030000 + message
    ├─ 计算摘要：digest = blake2b256(msg_with_intent)
    └─ 签名：signature = ed25519_sign(server_private_key, digest)
                          ↓
玩家调用合约（Sui PTB）
    │
    └─ verify_signature(message, flag+sig+pk, server_address)
                          ↓
Move 合约
    ├─ 重建摘要（相同算法）
    ├─ 从 signature 中提取 public_key
    ├─ 验证 address(public_key) == server_address（防伪造）
    └─ ed25519_verify(sig, pk, digest) → true/false
```

---

## 5. 如何在 Builder 合约中使用？

### 5.1 基础用法：验证服务器颁发的许可

```move
module my_extension::server_permit;

use world::sig_verify;
use world::access::ServerAddressRegistry;
use std::bcs;

public struct PermitMessage has copy, drop {
    player: address,
    action_type: u8,     // 1=通行证, 2=物品奖励
    item_id: u64,
    deadline_ms: u64,
}

public fun redeem_server_permit(
    server_registry: &ServerAddressRegistry,
    message_bytes: vector<u8>,
    signature: vector<u8>,
    ctx: &mut TxContext,
) {
    // 1. 反序列化消息（假设服务器用 BCS 序列化）
    let msg = bcs::from_bytes<PermitMessage>(message_bytes);

    // 2. 验证 deadline
    // （实际需传入 Clock，此处简化）

    // 3. 验证签名来自授权服务器
    // 从 registry 中取出服务器地址
    let server_addr = get_server_address(server_registry);
    assert!(
        sig_verify::verify_signature(message_bytes, signature, server_addr),
        EInvalidSignature,
    );

    // 4. 执行业务逻辑
    assert!(msg.player == ctx.sender(), EPlayerMismatch);
    // ...发放物品、积分等
}
```

### 5.2 实战：Location Proof 验证（预览 Ch.26 内容）

`location.move` 中的 `verify_proximity` 就是 `sig_verify` 的典型应用：

```move
// world/sources/primitives/location.move
pub fun verify_proximity(
    location: &Location,
    proof: LocationProof,
    server_registry: &ServerAddressRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let LocationProof { message, signature } = proof;

    // Step 1: 验证消息字段（位置哈希、发送者地址等）
    validate_proof_message(&message, location, server_registry, ctx.sender());

    // Step 2: 对消息做 BCS 编码
    let message_bytes = bcs::to_bytes(&message);

    // Step 3: 验证 deadline 未过期
    assert!(is_deadline_valid(message.deadline_ms, clock), EDeadlineExpired);

    // Step 4: 调用 sig_verify 验证签名！
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

---

## 6. 从 TypeScript 到链上：完整示例

### 服务器端签名（TypeScript/Node.js）

```typescript
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { blake2b } from '@noble/hashes/blake2b';

const serverKeypair = Ed25519Keypair.fromSecretKey(SERVER_PRIVATE_KEY);

// 构造消息（与 Move 中 BCS 格式一致）
const message = {
    server_address: serverKeypair.getPublicKey().toSuiAddress(),
    player_address: playerAddress,
    // ...其他字段
};

// 序列化（BCS）
const messageBytes = bcs.serialize(PermitMessage, message);

// 添加 PersonalMessage intent 前缀
const intentPrefix = new Uint8Array([0x03, 0x00, 0x00]);
const msgWithIntent = new Uint8Array([...intentPrefix, ...messageBytes]);

// 计算 Blake2b-256 摘要
const digest = blake2b(msgWithIntent, { dkLen: 32 });

// 用服务器私钥签名
const rawSig = serverKeypair.signData(digest); // 64 bytes

// 构建完整签名：flag (1) + sig (64) + pubkey (32) = 97 bytes
const pubKey = serverKeypair.getPublicKey().toRawBytes(); // 32 bytes
const fullSignature = new Uint8Array([0x00, ...rawSig, ...pubKey]);
```

### 玩家提交到链上（TypeScript/PTB）

```typescript
const tx = new Transaction();
tx.moveCall({
    target: `${PACKAGE_ID}::my_extension::redeem_server_permit`,
    arguments: [
        tx.object(SERVER_REGISTRY_ID),
        tx.pure(bcs.vector(bcs.u8()).serialize(Array.from(messageBytes))),
        tx.pure(bcs.vector(bcs.u8()).serialize(Array.from(fullSignature))),
    ],
});
await client.signAndExecuteTransaction({ signer: playerKeypair, transaction: tx });
```

---

## 7. Match 语法：Move 2024 的新特性

`sig_verify.move` 大量使用了 Move 2024 的 `match` 表达式：

```move
// Move 2024 match（类似 Rust）
let (sig_len, pk_len) = match (flag) {
    ED25519_FLAG => (ED25519_SIG_LEN, ED25519_PK_LEN),
    _ => abort EUnsupportedScheme,
};
```

对比旧写法：
```move
// Move 旧写法
let sig_len: u64;
let pk_len: u64;
if (flag == ED25519_FLAG) {
    sig_len = ED25519_SIG_LEN;
    pk_len = ED25519_PK_LEN;
} else {
    abort EUnsupportedScheme
};
```

---

## 8. 安全性注意事项

| 风险 | 防护机制 |
|------|---------|
| 伪造签名 | Ed25519 密码学保障 |
| 重放攻击（同一个证明被反复提交） | `deadline_ms` 过期时间 + 一次性验证标记 |
| 错误服务器签名 | `derive_address_from_public_key` 验证地址匹配 |
| 未注册服务器 | `ServerAddressRegistry` 白名单过滤 |

---

## 9. 实战练习

1. **签名验证工具**：用 TypeScript 实现一个"签名生成器"，用测试密钥为玩家生成通行许可证签名
2. **单次使用凭证**：设计一个合约，接收服务器签发的"单次使用 item"，验证后在链上标记为"已使用"防止重放
3. **多服务器支持**：阅读 `ServerAddressRegistry` 的设计，思考如何支持多个游戏服务器节点签名同一个凭证

---

## 本章小结

| 概念 | 要点 |
|------|------|
| Ed25519 签名格式 | `flag(1) + sig(64) + pubkey(32)` = 97 字节 |
| PersonalMessage intent | `0x030000` 前缀 + 消息，Blake2b256 摘要 |
| 地址验证 | `Blake2b256(0x00 || pubkey)` = Sui 地址 |
| Match 语法 | Move 2024 新特性，替代 if/else 分支 |
| `tabulate!` 宏 | 简洁的字节切片操作 |

> 下一章：**位置证明协议** —— LocationProof 的 BCS 序列化、临近性验证，以及如何在建筑合约中要求玩家"必须在场"。
