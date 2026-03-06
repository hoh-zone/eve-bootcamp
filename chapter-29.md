# 第29章：炮塔 AI 扩展开发

> **学习目标**：深入理解 `world::turret` 模块的目标优先级系统，掌握通过 Extension 模式自定义炮塔 AI 行为的完整实现方法。

---

## 1. 炮塔（Turret）是什么？

Smart Turret 是 EVE Frontier 中一种可编程空间建筑，可以对进入其范围的飞船自动开火。

**两个关键行为触发点**：

| 触发器 | 说明 |
|--------|------|
| `InProximity` | 飞船进入炮塔范围 |
| `Aggression` | 飞船开始/停止攻击己方建筑 |

默认行为：攻击所有进入范围的飞船。

**Builder 扩展的能力**：自定义目标优先级排序——决定炮塔优先攻击哪些目标。

---

## 2. TargetCandidate 数据结构

当游戏引擎需要决定炮塔该打谁时，它构造一批 `TargetCandidate` 并传入扩展函数：

```move
// world/sources/assemblies/turret.move

pub struct TargetCandidate has copy, drop, store {
    item_id: u64,           // 目标的 in-game ID（飞船/NPC）
    type_id: u64,           // 目标类型
    group_id: u64,          // 目标所属组（0=NPC）
    character_id: u32,      // 飞行员的角色 ID（NPC 为 0）
    character_tribe: u32,   // 飞行员部族（NPC 为 0）
    hp_ratio: u64,          // 剩余生命值百分比（0-100）
    shield_ratio: u64,      // 剩余护盾百分比（0-100）
    armor_ratio: u64,       // 剩余装甲百分比（0-100）
    is_aggressor: bool,     // 是否正在攻击建筑
    priority_weight: u64,   // 优先级权重（越大越优先）
    behaviour_change: BehaviourChangeReason,  // 触发这次更新的原因
}
```

### 触发原因枚举

```move
pub enum BehaviourChangeReason has copy, drop, store {
    UNSPECIFIED,
    ENTERED,         // 飞船进入炮塔范围
    STARTED_ATTACK,  // 飞船开始攻击
    STOPPED_ATTACK,  // 飞船停止攻击
}
```

**重要设计**：每次调用，每个目标候选人只有**一个**最相关的原因（游戏引擎选最重要的那个）。

---

## 3. 返回格式：ReturnTargetPriorityList

扩展函数最终must返回一个优先级列表：

```move
pub struct ReturnTargetPriorityList has copy, drop, store {
    target_item_id: u64,     // 目标的 in-game ID
    priority_weight: u64,    // 自定义优先级分数（越大越优先）
}
```

炮塔攻击的是列表中 `priority_weight` 最高的目标（相同权重时打第一个）。

---

## 4. 默认优先级规则（内置逻辑）

当 Builder 未配置扩展时，炮塔使用以下默认规则：

```move
// 默认权重增量常量
const STARTED_ATTACK_WEIGHT_INCREMENT: u64 = 10000;  // 主动攻击者 +10000
const ENTERED_WEIGHT_INCREMENT: u64 = 1000;           // 进入范围者 +1000

// world::turret::get_target_priority_list（默认版本）
pub fun get_target_priority_list(
    turret: &Turret,
    candidates: vector<TargetCandidate>,
): vector<ReturnTargetPriorityList> {
    effective_weight_and_excluded(candidates)
}

fun effective_weight_and_excluded(
    candidates: vector<TargetCandidate>,
): vector<ReturnTargetPriorityList> {
    let mut result = vector::empty();
    candidates.do!(|candidate| {
        let weight = match (candidate.behaviour_change) {
            BehaviourChangeReason::STARTED_ATTACK => {
                candidate.priority_weight + STARTED_ATTACK_WEIGHT_INCREMENT
            },
            BehaviourChangeReason::ENTERED => {
                candidate.priority_weight + ENTERED_WEIGHT_INCREMENT
            },
            _ => candidate.priority_weight,
        };

        // 使用 0 表示"排除该目标不攻击"，其他值表示优先级
        if (weight > 0) {
            result.push_back(ReturnTargetPriorityList {
                target_item_id: candidate.item_id,
                priority_weight: weight,
            });
        }
    });
    result
}
```

**默认策略**：主动攻击者 > 进入范围者 > 其他。

---

## 5. Extension 机制：TypeName 指向扩展包

```move
pub struct Turret has key {
    id: UID,
    // ...
    extension: Option<TypeName>,  // 保存了 Builder 扩展包的类型名称
}
```

当游戏引擎需要决定目标优先级时：

1. 读取 `turret.extension`
2. 如果是 `None`：调用 `world::turret::get_target_priority_list`（默认逻辑）
3. 如果是 `Some(TypeName)`：解析包 ID → 调用该包的 `get_target_priority_list` 函数

---

## 6. 开发自定义炮塔 AI

### 场景：只攻击联盟成年后的玩家飞船（保护新手）

```move
module my_turret::ai;

use world::turret::{Turret, TargetCandidate, ReturnTargetPriorityList};
use sui::dynamic_field as df;

/// 配置：新手保护阈值（低于此 group_id 的不攻击）
public struct AiConfig has key {
    id: UID,
    protected_tribe_ids: vector<u32>,  // 受保护的部族（如新手部族）
    prefer_aggressors: bool,           // 是否优先攻击主动攻击者
}

/// 这是游戏引擎会调用的标准入口函数名（固定签名）
public fun get_target_priority_list(
    turret: &Turret,
    candidates: vector<TargetCandidate>,
    ai_config: &AiConfig,             // Builder 的配置对象
): vector<ReturnTargetPriorityList> {

    let mut result = vector::empty<ReturnTargetPriorityList>();

    candidates.do!(|candidate| {
        // 规则1：受保护部族 → 跳过（权重 0 = 排除）
        if (vector::contains(&ai_config.protected_tribe_ids, &candidate.character_tribe)) {
            return  // 不加入结果列表 = 不攻击
        };

        // 规则2：计算优先级权重
        let mut weight: u64 = 1000;  // 基础权重

        // 主动攻击者优先
        if (candidate.is_aggressor && ai_config.prefer_aggressors) {
            weight = weight + 50000;
        };

        // 血量越低优先级越高（补刀策略）
        let hp_score = (100 - candidate.hp_ratio) * 100;
        weight = weight + hp_score;

        // 护盾破碎时附加权重
        if (candidate.shield_ratio == 0) {
            weight = weight + 5000;
        };

        result.push_back(ReturnTargetPriorityList {
            target_item_id: candidate.item_id,
            priority_weight: weight,
        });
    });

    result
}
```

### 策略对比：多种 AI 模式

```
默认 AI：
  主动攻击者 (+10000) > 进入范围 (+1000)

补刀 AI（血最低优先）：
  is_aggressor bonus + (100-hp_ratio)*100 + shield_broken bonus

精英护卫 AI（保护己方）：
  同族飞船权重=0 + 敌族根据 hp_ratio 排序

反 PvE AI（优先 NPC）：
  character_id==0 (NPC) → 超高权重 + 玩家 → 低权重
```

---

## 7. 授权扩展到炮塔

Builder 需要先将扩展的 TypeName 注册到炮塔：

```move
// 调用 world 合约提供的函数，将自定义 AI 类型注册到炮塔
// （需要 OwnerCap<Turret>）
turret::authorize_extension<my_turret::ai::AiType>(
    turret,
    owner_cap,
    ctx,
);
```

之后游戏引擎就会在需要决策时调用该扩展包的 `get_target_priority_list`。

---

## 8. 高级：动态配置 AI 参数

```move
/// 让炮塔 AI 可以动态更新配置（不需要重新部署合约）
pub fun update_protection_list(
    ai_config: &mut AiConfig,
    admin: address,
    new_protected_tribes: vector<u32>,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == admin, 0);
    ai_config.protected_tribe_ids = new_protected_tribes;
}
```

---

## 9. 状态处理：OnlineReceipt

```move
/// 炮塔在线的证明
pub struct OnlineReceipt {
    turret_id: ID,
}
```

炮塔在执行某些操作前需要先确认炮塔在线。`OnlineReceipt` 是一次性凭证，用于在函数链中传递"已确认在线"的证明，避免重复检查。

---

## 10. 实战练习

1. **基础 AI**：实现一个"专注新手保护"AI——对 `hp_ratio > 80` 的飞船（几乎满血，明显是老鸟）优先攻击，对 `hp_ratio < 30` 的（可能是新手）权重设为 0
2. **联盟守护 AI**：读取一个联盟成员列表，对非成员的飞船分配高优先级，对成员飞船权重为 0
3. **排行榜 AI**：记录被炮塔击落的各飞船类型数量，每周自动调整策略（击落越多的类型优先级越低——因为该类型玩家已经学会回避了）

---

## 本章小结

| 概念 | 要点 |
|------|------|
| `TargetCandidate` | 目标候选人的完整战斗信息 |
| `BehaviourChangeReason` | ENTERED / STARTED_ATTACK / STOPPED_ATTACK |
| `ReturnTargetPriorityList` | 返回格式：`item_id + priority_weight`（0=排除） |
| `extension: Option<TypeName>` | 炮塔保存扩展包的类型名称，引擎动态调用 |
| 默认权重 | STARTED_ATTACK +10000, ENTERED +1000 |

> 下一章：**访问控制系统完整解析** —— 深入理解 `world::access` 的 OwnerCap / GovernorCap / AdminACL / Receiving 模式，掌握 EVE Frontier 权限架构的核心设计。
