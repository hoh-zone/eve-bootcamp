# Chapter 13：NFT 设计与元数据管理

> **目标：** 掌握 Sui 的 NFT 标准（Display），设计可进化的动态 NFT，以及在 EVE Frontier 生态中应用 NFT 作为权限凭证、成就徽章和游戏资产。

---

> 状态：设计进阶章节。正文以 NFT 标准、动态元数据和 Collection 模式为主。

##  13.1 Sui 的 NFT 模型

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

最重要的理解不是“NFT 能显示图片”，而是：

> NFT 在 Sui 里首先是一个对象，其次才是一个收藏品或展示品。

这意味着你可以很自然地把 NFT 用在三类不同场景：

- **纯展示型**
  勋章、纪念品、成就证明
- **权限型**
  通行证、会员卡、白名单凭证
- **功能型**
  可升级飞船、装备、订阅权、租赁凭证

这三类 NFT 的设计重点完全不同。

### 设计 NFT 前先问四个问题

1. 它主要是展示品、权限卡，还是可操作资产？
2. 它是否允许转让？
3. 它的元数据是否会变化？
4. 前端和市场应不应该把它当“可交易商品”看待？

只要这四个问题没答清，后面的 `Display`、`Collection`、`TransferPolicy` 都很容易做偏。

---

##  13.2 Sui Display 标准：让 NFT 在各处正确显示

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

### `Display` 真正解决的是什么？

它解决的是“链上对象字段”到“钱包和市场展示内容”之间的解释层问题。

如果没有这层：

- 钱包只能看到生硬字段
- 市场很难统一显示名称、描述、图片
- 同一类 NFT 在不同前端里会表现不一致

所以 `Display` 不是装饰，而是 NFT 产品体验的一部分。

### 设计 Display 时最容易犯的错

#### 1. 把所有展示语义都塞进链上字段

不是所有展示文案都要做成可变链上字段。有些稳定说明更适合放在模板里，有些动态状态才适合放字段里。

#### 2. 过度依赖外部图片 URL

如果图片资源路径不稳定，NFT 本体还在，但用户看到的体验会崩。

#### 3. 字段命名和前端理解脱节

如果链上字段叫得过于内部化，前端和钱包层就很难稳定解释。

---

##  13.3 动态 NFT：会进化的元数据

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

### 动态 NFT 适合什么，不适合什么？

适合：

- 成长型资产
- 会被状态影响价值的物品
- 游戏内战绩、成就、熟练度映射

不一定适合：

- 强调静态稀缺叙事的收藏品
- 二级市场非常依赖固定元数据的资产

因为一旦元数据可变，你就默认引入了新的产品问题：

- 谁能改？
- 改动是否可审计？
- 玩家买入时到底买的是当前状态，还是未来可能变化的状态？

### 动态元数据设计的关键边界

- **状态变化是否链上可追溯**
  最好有事件记录
- **改动权限是否明确**
  不是任何模块都能乱改
- **前端是否能正确反映变化**
  否则链上变了，用户界面还停在旧图

---

##  13.4 集合（Collection）模式

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

Collection 的价值，不只是“把一批 NFT 归个类”，而是让系列化管理变得清晰：

- 总量控制
- 编号追踪
- 官方系列身份
- 前端聚合展示

### Collection 最适合解决哪些问题？

- 某一系列是否已经售罄
- 第几号资产属于哪一系列
- 一个 badge 是否来自官方那套发行体系

如果没有 collection 这一层，你后面做：

- 系列页
- 稀有度统计
- 官方认证

都会变得更难。

---

##  13.5 NFT 作为访问控制凭证

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

这是 EVE Builder 里 NFT 最实用的一类用法，因为它把“权限”做成了玩家真的能持有和理解的对象。

### 为什么权限 NFT 往往比地址白名单更好？

因为它更灵活，也更产品化：

- 可以转让
- 可以回收
- 可以有等级
- 可以有到期时间
- 前端可以直观展示

但也要小心一件事：

> 只要它能转让，权限也会跟着流动。

所以你必须先决定，这张权限 NFT 到底应该是：

- 可转让的市场资产
- 还是不可转让的身份凭证

---

##  13.6 NFT 转让策略

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

### 转让策略本质上是在定义“这个 NFT 的社会属性”

- **自由转让**
  更像商品
- **受限转让**
  更像带规则的许可
- **不可转让**
  更像身份或成就

这不是技术细节，而是产品定位。

如果你的 NFT 是：

- 会员资格
- 实名凭证
- 联盟内部身份卡

那默认自由转让往往不是好主意。

---

##  13.7 将 NFT 嵌入 EVE Frontier 资产（对象拥有对象）

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

对象拥有对象这套设计，对游戏资产尤其自然，因为它允许你表达：

- 一艘船拥有多件装备
- 一个角色拥有一套证件
- 一个容器里放着多个特殊资产

### 什么时候该把 NFT 独立存在，什么时候该嵌进去？

适合独立存在：

- 需要单独交易
- 需要单独展示
- 需要单独授权或转让

适合嵌进别的对象：

- 主要作为某个大对象的组成部分
- 不需要频繁单独流转
- 更强调组合后的整体状态

这背后其实是在平衡“可流通性”和“组合表达力”。

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
