# Chapter 14：NFT 设计与元数据管理

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握 Sui 的 NFT 标准（Display），设计可进化的动态 NFT，以及在 EVE Frontier 生态中应用 NFT 作为权限凭证、成就徽章和游戏资产。

---

> 状态：设计进阶章节。正文以 NFT 标准、动态元数据和 Collection 模式为主。

## 前置依赖

- 建议先读 [Chapter 3](./chapter-03.md)
- 建议先读 [Chapter 7](./chapter-07.md)

## 源码位置

- [book/src/code/chapter-14](./code/chapter-14)

## 关键测试文件

- 当前目录以 `space_badge.move`、`evolving_ship.move` 等示例为主。

## 推荐阅读顺序

1. 先读 Display 与元数据模型
2. 再打开 [book/src/code/chapter-14](./code/chapter-14)
3. 最后结合 [Example 6](./example-06.md) 与 [Example 13](./example-13.md)

## 验证步骤

1. 能区分静态 NFT、动态 NFT 和权限 NFT 的不同设计
2. 能定位元数据更新责任在链上还是链下
3. 能理解 Collection/Badge 两层结构

## 常见报错

- 把所有展示字段都固化上链，导致后续演进成本很高

---

## 14.1 Sui 的 NFT 模型

在 Sui 上，NFT 就是一个带有 `key` ability 的唯一对象。没有特殊的 "NFT 合约"——任何带有唯一 ObjectID 的对象都天然是 NFT：

```move
// 最简单的 NFT
public struct Badge has key, store {
    id: UID,
    name: vector<u8>,
    description: vector<u8>,
    image_url: vector<u8>,
}
```

**与 ERC-721 的对比：**

| 特性 | ERC-721 | Sui NFT |
|------|---------|---------|
| ID | `tokenId` 整数 | `ObjectID`（全局唯一地址） |
| 存储 | 合约的 mapping | 独立对象 |
| 转移 | 调用合约方法 | 原生 transfer |
| 组合 | 难以嵌套 | 对象可以拥有对象 |

---

## 14.2 Sui Display 标准：让 NFT 在各处正确显示

`Display` 对象告诉钱包、市场如何显示你的 NFT：

```move
module my_nft::space_badge;

use sui::display;
use sui::package;
use std::string::utf8;

// 一次性见证（创建 Publisher）
public struct SPACE_BADGE has drop {}

public struct SpaceBadge has key, store {
    id: UID,
    name: String,
    tier: u8,           // 1=铜牌, 2=银牌, 3=金牌
    earned_at_ms: u64,
    image_url: String,
}

fun init(witness: SPACE_BADGE, ctx: &mut TxContext) {
    // 1. 用 OTW 创建 Publisher（证明这个包的作者身份）
    let publisher = package::claim(witness, ctx);

    // 2. 创建 Display（定义如何展示 SpaceBadge）
    let mut display = display::new_with_fields<SpaceBadge>(
        &publisher,
        // 字段名   // 模板值（{field_name} 会被实际字段值替换）
        vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"image_url"),
            utf8(b"project_url"),
        ],
        vector[
            utf8(b"{name}"),                                          // NFT 名称
            utf8(b"EVE Frontier Builder Badge - Tier {tier}"),        // 描述
            utf8(b"{image_url}"),                                     // 图片 URL
            utf8(b"https://evefrontier.com"),                         // 项目链接
        ],
        ctx,
    );

    // 3. 提交 Display（冻结版本，使其对外可见）
    display::update_version(&mut display);

    // 4. 转移（Publisher 给部署者，Display 共享或冻结）
    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_freeze_object(display);
}
```

---

## 14.3 动态 NFT：会进化的元数据

EVE Frontier 的游戏状态实时变化，你的 NFT 元数据也可以随之变化：

```move
module my_nft::evolving_ship;

/// 可进化的飞船 NFT
public struct EvolvingShip has key, store {
    id: UID,
    name: String,
    hull_class: u8,        // 0=护卫舰, 1=巡洋舰, 2=战列舰
    combat_score: u64,     // 战斗积分（随战斗增加）
    kills: u64,            // 击杀数
    image_url: String,     // 根据 hull_class 变化
}

/// 记录战斗结果（由炮塔合约调用）
public entry fun record_kill(
    ship: &mut EvolvingShip,
    ctx: &TxContext,
) {
    ship.kills = ship.kills + 1;
    ship.combat_score = ship.combat_score + 100;

    // 升级飞船等级（进化）
    if ship.combat_score >= 10_000 && ship.hull_class < 2 {
        ship.hull_class = ship.hull_class + 1;
        // 更新图片 URL（指向更高级别的资产）
        ship.image_url = get_image_url(ship.hull_class);
    }
}

fun get_image_url(class: u8): String {
    let base = b"https://assets.evefrontier.com/ships/";
    let suffix = if class == 0 { b"frigate.png" }
                 else if class == 1 { b"cruiser.png" }
                 else { b"battleship.png" };
    // 拼接 URL（Move 中字符串操作用 sui::string）
    let mut url = std::string::utf8(base);
    url.append(std::string::utf8(suffix));
    url
}
```

**Display 模板自动更新**：由于 Display 用 `{hull_class}` 和 `{image_url}` 等字段的当前值渲染，当字段变化时，NFT 在钱包中的显示也会立即更新。

---

## 14.4 集合（Collection）模式

```move
module my_nft::badge_collection;

/// 勋章系列集合（元对象，描述这个 NFT 系列）
public struct BadgeCollection has key {
    id: UID,
    name: String,
    total_supply: u64,
    minted_count: u64,
    admin: address,
}

/// 单个勋章
public struct AllianceBadge has key, store {
    id: UID,
    collection_id: ID,      // 归属于哪个集合
    serial_number: u64,     // 系列编号（第几个铸造的）
    tier: u8,
    attributes: vector<NFTAttribute>,
}

public struct NFTAttribute has store, copy, drop {
    trait_type: String,
    value: String,
}

/// 铸造勋章（追踪编号和总量）
public entry fun mint_badge(
    collection: &mut BadgeCollection,
    recipient: address,
    tier: u8,
    attributes: vector<NFTAttribute>,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == collection.admin, ENotAdmin);
    assert!(collection.minted_count < collection.total_supply, ESoldOut);

    collection.minted_count = collection.minted_count + 1;

    let badge = AllianceBadge {
        id: object::new(ctx),
        collection_id: object::id(collection),
        serial_number: collection.minted_count,
        tier,
        attributes,
    };

    transfer::public_transfer(badge, recipient);
}
```

---

## 14.5 NFT 作为访问控制凭证

在 EVE Frontier 中，NFT 是最天然的权限载体：

```move
// 使用 NFT 检查权限的方式
public entry fun enter_restricted_zone(
    gate: &Gate,
    character: &Character,
    badge: &AllianceBadge,   // 持有勋章才能调用
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 验证勋章等级（需要金牌才能进入）
    assert!(badge.tier >= 3, EInsufficientBadgeTier);
    // 验证勋章属于正确集合（防止伪造）
    assert!(badge.collection_id == OFFICIAL_COLLECTION_ID, EWrongCollection);
    // ...
}
```

---

## 14.6 NFT 转让策略

Sui 支持灵活的 NFT 转让政策：

```move
// 默认：任何人都可以转让（public_transfer）
transfer::public_transfer(badge, recipient);

// 锁仓：NFT 只能由特定合约转移（通过 TransferPolicy）
use sui::transfer_policy;

// 在包初始化时建立 TransferPolicy（限制转让条件）
fun init(witness: SPACE_BADGE, ctx: &mut TxContext) {
    let publisher = package::claim(witness, ctx);
    let (policy, policy_cap) = transfer_policy::new<SpaceBadge>(&publisher, ctx);

    // 添加自定义规则（如需支付版税）
    // royalty_rule::add(&mut policy, &policy_cap, 200, 0); // 2% 版税

    transfer::public_share_object(policy);
    transfer::public_transfer(policy_cap, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}
```

---

## 14.7 将 NFT 嵌入 EVE Frontier 资产（对象拥有对象）

```move
// 飞船装备 NFT（被飞船对象持有）
public struct Equipment has key, store {
    id: UID,
    name: String,
    stat_bonus: u64,
}

public struct Ship has key {
    id: UID,
    // Equipment 被嵌入 Ship 对象中（对象拥有对象）
    equipped_items: vector<Equipment>,
}

// 为飞船装备物品
public entry fun equip(
    ship: &mut Ship,
    equipment: Equipment,  // Equipment 从玩家钱包移入 Ship
    ctx: &TxContext,
) {
    vector::push_back(&mut ship.equipped_items, equipment);
}
```

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| Sui NFT 本质 | 带 `key` 的唯一对象，ObjectID 即 NFT ID |
| Display 标准 | `display::new_with_fields()` 定义钱包显示模板 |
| 动态 NFT | 字段可变 + Display 模板引用字段 → 自动同步显示 |
| Collection 模式 | MetaObject 追踪总量和编号 |
| NFT 作为权限 | 传入 NFT 引用做权限检查，比地址白名单更灵活 |
| TransferPolicy | 控制 NFT 二级市场转让规则（如版税） |

## 📚 延伸阅读

- [Sui Display 标准](https://docs.sui.io/standards/display)
- [Sui NFT 指南](https://docs.sui.io/guides/developer/nft)
- [Move Book：对象拥有对象](https://move-book.com/object/ownership.html)
