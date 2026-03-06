# Chapter 15：位置与临近性系统

> ⏱ 预计学习时间：2 小时
>
> **目标：** 理解 EVE Frontier 的链上位置隐私设计，掌握如何利用临近性系统构建地理化游戏逻辑，以及未来 ZK 证明方向。

---

> 状态：教学示例章节。正文以位置隐私、服务器证明和未来 ZK 方向为主。

## 前置依赖

- 建议先读 [Chapter 11](./chapter-11.md)
- 建议先读 [Chapter 13](./chapter-13.md)

## 源码位置

- [book/src/code/chapter-15](./code/chapter-15)

## 关键测试文件

- 当前目录以位置相关片段为主；协议验收请结合本章新增的消息体和失败场景。

## 推荐阅读顺序

1. 先读位置哈希与服务器签名模式
2. 再打开 [book/src/code/chapter-15](./code/chapter-15) 对照片段
3. 最后结合本章协议闭环和 [Chapter 25](./chapter-25.md)

## 验证步骤

1. 能描述位置证明从客户端到链上的完整消息流
2. 能列出至少三个失败场景及其防御方式
3. 能判断何时需要服务器证明、何时可以迁移到 ZK

## 常见报错

- 只在链上校验赞助者地址，不校验具体 payload、时间窗和对象绑定

---

## 15.1 空间游戏的链上挑战

一个传统MMORPG游戏中，位置信息由游戏服务器统一管理。在链上，这带来两个矛盾：

1. **透明性**：链上数据任何人可查；若坐标明文存储，所有玩家隐藏基地的位置立即暴露
2. **信任性**：如果位置由客户端上报，玩家可以造假（"我就在你旁边！"）

EVE Frontier 的解决方案：**哈希位置 + 信任游戏服务器签名**。

---

## 15.2 哈希位置：保护坐标隐私

链上存储的不是明文坐标，而是 **哈希值**：

```
存储：hash(x, y, salt) → chain.location_hash
查询：任何人只能看到哈希，无法反推坐标
验证：玩家向服务器证明"我知道这个哈希对应的坐标"
```

```move
// location.move（简化版）
public struct Location has store {
    location_hash: vector<u8>,  // 坐标的哈希，而不是明文坐标
}

/// 更新位置（需要游戏服务器签名授权）
public fun update_location(
    assembly: &mut Assembly,
    new_location_hash: vector<u8>,
    admin_acl: &AdminACL,  // 必须由授权服务器作为赞助者
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    assembly.location.location_hash = new_location_hash;
}
```

---

## 15.3 临近性验证：服务器签名模式

当需要验证"A 在 B 附近"时（如取物品、跳跃），当前采用**服务器签名**：

```
① 玩家向游戏服务器请求："证明我在星门 0x...附近"
② 服务器查询玩家的实际游戏坐标
③ 服务器验证玩家确实在星门附近（<20km）
④ 服务器用私钥签名"玩家A在星门B附近"的声明
⑤ 玩家将这个签名附在交易中提交
⑥ 链上合约验证签名来自授权服务器（AdminACL）
```

```move
// 星门链接时的距离验证
public fun link_gates(
    gate_a: &mut Gate,
    gate_b: &mut Gate,
    owner_cap_a: &OwnerCap<Gate>,
    distance_proof: vector<u8>,  // 服务器签名的"两门距离 > 20km"证明
    admin_acl: &AdminACL,
    ctx: &TxContext,
) {
    // 验证服务器签名（简化；实际实现验证 ed25519 签名）
    verify_sponsor(admin_acl, ctx);
    // ...
}
```

### 15.3.1 建议的最小证明消息体

不要把“附近证明”做成一个只有服务器自己看得懂的黑盒字节串。最小可落地的 payload 至少要绑定以下字段：

```json
{
  "proof_type": "assembly_proximity",
  "player": "0xPLAYER",
  "assembly_id": "0xASSEMBLY",
  "location_hash": "0xHASH",
  "max_distance_m": 20000,
  "issued_at_ms": 1735689600000,
  "expires_at_ms": 1735689660000,
  "nonce": "4d2f1c..."
}
```

每个字段的职责：

- `player`：防止别的玩家复用证明
- `assembly_id`：防止把 A 星门的证明拿去调用 B 星门
- `location_hash`：把链上当前位置状态绑定进证明
- `issued_at_ms` / `expires_at_ms`：限制重放窗口
- `nonce`：防止同一窗口内多次重放

### 15.3.2 服务端签名与链上校验的最小闭环

链下服务至少要做两件事：先验证真实坐标关系，再对明确的 payload 签名。

```ts
type ProximityProofPayload = {
  proofType: "assembly_proximity";
  player: string;
  assemblyId: string;
  locationHash: string;
  maxDistanceM: number;
  issuedAtMs: number;
  expiresAtMs: number;
  nonce: string;
};

async function issueProximityProof(input: {
  player: string;
  assemblyId: string;
  expectedHash: string;
}) {
  const location = await getPlayerLocationFromGameServer(input.player);
  const assembly = await getAssemblyLocation(input.assemblyId);

  assert(hash(location) === input.expectedHash);
  assert(distance(location, assembly) <= 20_000);

  const payload: ProximityProofPayload = {
    proofType: "assembly_proximity",
    player: input.player,
    assemblyId: input.assemblyId,
    locationHash: input.expectedHash,
    maxDistanceM: 20_000,
    issuedAtMs: Date.now(),
    expiresAtMs: Date.now() + 60_000,
    nonce: crypto.randomUUID(),
  };

  return signPayload(payload);
}
```

链上侧至少要校验四层：

```move
// 简化伪代码：真实实现应把 payload 反序列化后逐字段比对
public fun verify_proximity_proof(
    assembly_id: ID,
    expected_player: address,
    expected_hash: vector<u8>,
    proof_bytes: vector<u8>,
    admin_acl: &AdminACL,
    clock: &Clock,
    ctx: &TxContext,
) {
    verify_sponsor(admin_acl, ctx);

    let payload = decode_proximity_payload(proof_bytes);
    assert!(payload.assembly_id == assembly_id, EWrongAssembly);
    assert!(payload.player == expected_player, EWrongPlayer);
    assert!(payload.location_hash == expected_hash, EWrongLocationHash);
    assert!(clock.timestamp_ms() <= payload.expires_at_ms, EProofExpired);
    assert!(check_and_consume_nonce(payload.nonce), EReplay);
}
```

这里真正重要的是：`verify_sponsor(admin_acl, ctx)` 只证明“这笔交易来自授权服务端”，还不够证明“这条位置声明本身是针对当前对象、当前玩家、当前时间窗的”。

---

## 15.4 围绕位置系统的策略设计

即使位置是哈希的，Builder 仍然可以设计许多地理化逻辑：

### 策略一：位置锁定（资产绑定地点）

```move
// 资产只在特定位置哈希处有效
public entry fun claim_resource(
    claim: &mut ResourceClaim,
    claimant_location_hash: vector<u8>,  // 服务器证明的位置
    admin_acl: &AdminACL,
    ctx: &mut TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    // 验证玩家位置哈希与资源点匹配
    assert!(
        claimant_location_hash == claim.required_location_hash,
        EWrongLocation,
    );
    // 发放资源
}
```

### 策略二：基地范围控制

```move
public struct BaseZone has key {
    id: UID,
    center_hash: vector<u8>,   // 基地中心位置哈希
    owner: address,
    zone_nft_ids: vector<ID>,  // 在这个区域内的友方 NFT 列表
}

// 授权组件只对在基地范围内的玩家开放
public entry fun base_service(
    zone: &BaseZone,
    service: &mut StorageUnit,
    player_in_zone_proof: vector<u8>,  // 服务器证明"玩家在基地范围内"
    admin_acl: &AdminACL,
    ctx: &mut TxContext,
) {
    verify_sponsor(admin_acl, ctx);
    // ...提供服务
}
```

### 策略三：移动路径追踪（链外 + 链上结合）

```typescript
// 链下：监听玩家位置更新事件
client.subscribeEvent({
  filter: { MoveEventType: `${WORLD_PKG}::location::LocationUpdated` },
  onMessage: (event) => {
    const { assembly_id, new_hash } = event.parsedJson as any;
    // 更新本地路径记录
    locationHistory.push({ assembly_id, hash: new_hash, time: Date.now() });
  },
});

// 链上：只存储哈希，链下解析路径
```

---

## 15.5 未来方向：零知识证明取代服务器信任

官方文档提到，**未来计划用 ZK 证明**替代当前的服务器签名：

```
现在：
  玩家 → 服务器（你在哪里？）→ 服务器签名 → 链上验证签名

未来（ZK）：
  玩家 → 本地计算 ZK 证明（"我知道满足这个哈希的坐标，且 < 20km"）
         → 链上 ZK 验证器（无需服务器参与）
```

**ZK 证明的优势**：
- 完全去中心化，不依赖服务器诚实性
- 玩家可以证明"我在这里"而不暴露具体坐标
- 理论上可以证明任意复杂的空间关系

**实际开发建议**：
- 当前阶段，与服务器集成时就把 payload 结构、时间窗、nonce 和对象绑定设计清楚（见 Chapter 11）
- `AdminACL.verify_sponsor()` 只能当“来源验证”的一层，不能替代 payload 校验
- 未来 ZK 上线后，尽量只替换“证明机制”，不要重写上层业务状态机

### 15.5.1 失败场景与防御清单

| 失败场景 | 典型原因 | 最小防御 |
|------|------|------|
| 重放证明 | payload 没有 `nonce` 或过期时间 | 加 `nonce` + 短有效期 + 链上消费 |
| 错对象复用 | 证明没有绑定 `assembly_id` | payload 强绑定目标对象 |
| 错人复用 | 证明没有绑定 `player` | payload 强绑定调用者地址 |
| 旧位置复用 | 没有绑定 `location_hash` | 把当前链上哈希写入 payload |
| 服务端时钟偏差 | 过期判断不一致 | 用链上 `Clock` 做最终裁决 |

---

## 15.6 在 dApp 中展示位置信息

```tsx
// 位置信息对 Builder 不直接可读（哈希），但可以展示游戏内坐标
// （通过与游戏服务器 API 对接解密）

interface AssemblyDisplayInfo {
  id: string
  name: string
  systemName: string    // 星系名称（从服务器API获取）
  constellation: string // 星座
  region: string        // 区域
  onlineStatus: string
}

async function getAssemblyDisplayInfo(assemblyId: string): Promise<AssemblyDisplayInfo> {
  // 1. 从链上读取哈希化位置
  const obj = await suiClient.getObject({
    id: assemblyId,
    options: { showContent: true },
  });
  const locationHash = (obj.data?.content as any)?.fields?.location?.fields?.location_hash;

  // 2. 通过游戏服务器 API，用哈希查询星系名称
  const geoRes = await fetch(`${GAME_API}/location?hash=${locationHash}`);
  const geoInfo = await geoRes.json();

  return {
    id: assemblyId,
    name: (obj.data?.content as any)?.fields?.name,
    systemName: geoInfo.system_name,
    constellation: geoInfo.constellation,
    region: geoInfo.region,
    onlineStatus: (obj.data?.content as any)?.fields?.status,
  };
}
```

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 哈希位置 | 坐标哈希化存储，防止隐私泄露 |
| 临近性验证 | 当前：服务器签名 → 未来：ZK 证明 |
| AdminACL 作用 | `verify_sponsor()` 验证服务器的赞助地址 |
| Builder 机会 | 位置锁定、基地范围、轨迹分析 |
| ZK 展望 | 无需服务器信任的完全去中心化空间证明 |

## 📚 延伸阅读

- [EVE World Explainer - Privacy](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/eve-frontier-world-explainer.md#privacy-location-obfuscation)
- [Sui ZK Login（相关 ZK 技术背景）](https://docs.sui.io/concepts/cryptography/zklogin)
- [Constraints 文档](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
