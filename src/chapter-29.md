# 第29章：炮塔 AI 扩展开发

> **学习目标**：深入理解 `world::turret` 模块的目标优先级系统，掌握通过 Extension 模式自定义炮塔 AI 行为的完整实现方法。

---

> 状态：教学示例。正文关注优先级模型和扩展切入点，具体字段仍应以官方 `turret` 模块源码为准。

## 最小调用链

`飞船进入范围/触发 aggression -> turret 模块收集候选目标 -> 扩展规则排序 -> 执行攻击决策`

## 对应代码目录

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)
- [world-contracts/contracts/extension_examples](https://github.com/evefrontier/world-contracts/tree/main/contracts/extension_examples)

## 关键 Struct

| 类型 | 作用 | 阅读重点 |
|------|------|------|
| `TargetCandidate` | 炮塔决策输入候选集 | 看哪些字段参与过滤、哪些字段参与排序 |
| `ReturnTargetPriorityList` | 扩展返回的优先级结果 | 看扩展到底返回“排序建议”还是“直接开火命令” |
| `BehaviourChangeReason` | 触发本次重算的原因 | 看 AI 刷新来自进入范围、攻击行为还是状态变化 |
| `OnlineReceipt` | 炮塔在线状态相关凭证 | 看扩展逻辑是否依赖在线前置条件 |

## 关键入口函数

| 入口 | 作用 | 你要确认什么 |
|------|------|------|
| 炮塔候选集计算路径 | 收集可攻击目标 | 过滤条件是否先于排序 |
| 扩展优先级入口 | 自定义 AI 排序规则 | 返回值是否符合 World 侧预期 |
| 授权与上线入口 | 挂接扩展到炮塔 | 扩展是否真的被启用且状态同步 |

## 最容易误读的点

- 炮塔 AI 的扩展点通常是“排序”，不是绕过内核直接接管开火
- 只改优先级不改过滤条件，炮塔仍可能攻击不该攻击的目标
- 候选目标字段来自游戏事件和内核状态，不应凭前端或链下缓存臆造

这一章要先分清两件事：**谁有资格成为候选目标**，以及**候选目标之间谁排第一**。前者是过滤问题，决定目标是否进入候选集；后者是排序问题，决定先打谁。大多数 Builder AI 扩展真正能安全影响的是后者，而不是完全推翻前者。这样设计的目的是把“世界规则”与“局部策略”拆开，避免一个扩展包直接把炮塔变成任何它想要的武器。

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

这说明 `BehaviourChangeReason` 更像一次决策重算的上下文提示，而不是完整战斗历史。它告诉扩展“为什么这次要重算优先级”，却不保证把过去所有事件都带进来。因此 Builder 在写 AI 时，不要假设单次调用里能看到完整仇恨链或完整战斗日志；如果真的需要长期记忆，应该额外设计自己的配置或统计对象。

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

换句话说，扩展返回的是**建议顺序**，不是“立即执行某个攻击动作”的命令式接口。这个差别很关键。命令式接口意味着扩展可以越权控制底层武器行为，而优先级接口只让扩展在内核已经允许的候选集上表达偏好，整体安全边界会稳很多。

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

生产环境里更容易出问题的地方通常不是 AI 数学公式本身，而是“扩展到底有没有真的挂上去”。也就是说，Builder 排查顺序应该先查授权是否成功、炮塔是否在线、配置对象是否可读、TypeName 是否匹配，再去查权重算法。否则很容易把一个授权链问题误判成 AI 逻辑问题。

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
