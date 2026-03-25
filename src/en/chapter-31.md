# Chapter 31: Turret AI Extension Development

> **Learning Objective**: Deeply understand the target priority system in `world::turret` module, master complete implementation methods for customizing turret AI behavior through Extension pattern.

---

> Status: Teaching example. Text focuses on priority model and extension entry points; specific fields should still refer to official `turret` module source code.

## Minimal Call Chain

`Ship enters range/triggers aggression -> turret module collects candidate targets -> extension rules sort -> execute attack decision`

## Corresponding Code Directory

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)
- [world-contracts/contracts/extension_examples](https://github.com/evefrontier/world-contracts/tree/main/contracts/extension_examples)

## Key Structs

| Type | Purpose | Reading Focus |
|------|------|------|
| `TargetCandidate` | Turret decision input candidate set | Which fields participate in filtering, which fields participate in sorting |
| `ReturnTargetPriorityList` | Extension-returned priority result | Does extension return "sort suggestion" or "direct fire command" |
| `BehaviourChangeReason` | Reason triggering this recalculation | Does AI refresh come from entering range, attack behavior, or state change |
| `OnlineReceipt` | Turret online status related credential | Whether extension logic depends on online prerequisite condition |

## Key Entry Functions

| Entry | Purpose | What to Confirm |
|------|------|------|
| Turret candidate set calculation path | Collect attackable targets | Whether filter conditions come before sorting |
| Extension priority entry | Custom AI sorting rules | Whether return value meets World side expectations |
| Authorization and online entry | Hook extension to turret | Whether extension is truly enabled and state synced |

## Most Easily Misunderstood Points

- Turret AI extension point is usually "sorting," not bypassing kernel to directly take over firing
- Only changing priority without changing filter conditions, turret may still attack wrong targets
- Candidate target fields come from game events and kernel state, shouldn't fabricate based on frontend or off-chain cache

This chapter first needs to distinguish two things: **who qualifies to be a candidate target**, and **among candidate targets who ranks first**. Former is a filtering problem, determining whether target enters candidate set; latter is a sorting problem, determining who to shoot first. Most Builder AI extensions can safely influence the latter, not completely overturn the former. This design separates "world rules" from "local strategies," preventing one extension package from directly turning turret into any weapon it wants.

## 1. What is a Turret?

Smart Turret is a programmable space building in EVE Frontier that can automatically fire at ships entering its range.

**Two key behavior trigger points**:

| Trigger | Description |
|--------|------|
| `InProximity` | Ship enters turret range |
| `Aggression` | Ship starts/stops attacking own buildings |

Default behavior: Attack all ships entering range.

**Builder extension capability**: Customize target priority sorting — determine which targets turret attacks first.

---

## 2. TargetCandidate Data Structure

When game engine needs to decide who turret should shoot, it constructs a batch of `TargetCandidate` and passes into extension function:

```move
// world/sources/assemblies/turret.move

pub struct TargetCandidate has copy, drop, store {
    item_id: u64,           // Target's in-game ID (ship/NPC)
    type_id: u64,           // Target type
    group_id: u64,          // Target's group (0=NPC)
    character_id: u32,      // Pilot's character ID (NPC is 0)
    character_tribe: u32,   // Pilot tribe (NPC is 0)
    hp_ratio: u64,          // Remaining health percentage (0-100)
    shield_ratio: u64,      // Remaining shield percentage (0-100)
    armor_ratio: u64,       // Remaining armor percentage (0-100)
    is_aggressor: bool,     // Whether attacking building
    priority_weight: u64,   // Priority weight (larger is higher priority)
    behaviour_change: BehaviourChangeReason,  // Reason triggering this update
}
```

### Trigger Reason Enum

```move
pub enum BehaviourChangeReason has copy, drop, store {
    UNSPECIFIED,
    ENTERED,         // Ship entered turret range
    STARTED_ATTACK,  // Ship started attacking
    STOPPED_ATTACK,  // Ship stopped attacking
}
```

**Important Design**: Each call, each target candidate has only **one** most relevant reason (game engine chooses most important one).

This shows `BehaviourChangeReason` is more like a context hint for decision recalculation, not complete combat history. It tells extension "why priority needs recalculation this time," but doesn't guarantee bringing all past events. Therefore when writing AI, Builders shouldn't assume single call can see complete hate chain or complete combat log; if really need long-term memory, should additionally design own config or statistics objects.

---

## 3. Return Format: ReturnTargetPriorityList

Extension function must ultimately return a priority list:

```move
pub struct ReturnTargetPriorityList has copy, drop, store {
    target_item_id: u64,     // Target's in-game ID
    priority_weight: u64,    // Custom priority score (larger is higher priority)
}
```

Turret attacks target with highest `priority_weight` in list (ties attack first one).

In other words, extension returns **suggested order**, not an imperative interface for "immediately execute some attack action." This difference is critical. Imperative interface means extension can overstep authority to control underlying weapon behavior, while priority interface only lets extension express preference on candidate set kernel already allowed, overall security boundary much more stable.

---

## 4. Default Priority Rules (Built-in Logic)

When Builder hasn't configured extension, turret uses following default rules:

```move
// Default weight increment constants
const STARTED_ATTACK_WEIGHT_INCREMENT: u64 = 10000;  // Active attacker +10000
const ENTERED_WEIGHT_INCREMENT: u64 = 1000;           // Entered range +1000

// world::turret::get_target_priority_list (default version)
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

        // 0 means "exclude this target from attack," other values represent priority
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

**Default Strategy**: Active attackers > Entered range > Others.

---

## 5. Extension Mechanism: TypeName Points to Extension Package

```move
pub struct Turret has key {
    id: UID,
    // ...
    extension: Option<TypeName>,  // Stores Builder extension package's type name
}
```

When game engine needs to determine target priority:

1. Read `turret.extension`
2. If `None`: Call `world::turret::get_target_priority_list` (default logic)
3. If `Some(TypeName)`: Parse package ID → Call that package's `get_target_priority_list` function

---

## 6. Developing Custom Turret AI

### Scenario: Only Attack Alliance Adult Player Ships (Protect Newbies)

```move
module my_turret::ai;

use world::turret::{Turret, TargetCandidate, ReturnTargetPriorityList};
use sui::dynamic_field as df;

/// Config: Newbie protection threshold (don't attack below this group_id)
public struct AiConfig has key {
    id: UID,
    protected_tribe_ids: vector<u32>,  // Protected tribes (like newbie tribes)
    prefer_aggressors: bool,           // Whether to prioritize active attackers
}

/// This is standard entry function name game engine will call (fixed signature)
public fun get_target_priority_list(
    turret: &Turret,
    candidates: vector<TargetCandidate>,
    ai_config: &AiConfig,             // Builder's config object
): vector<ReturnTargetPriorityList> {

    let mut result = vector::empty<ReturnTargetPriorityList>();

    candidates.do!(|candidate| {
        // Rule 1: Protected tribe → Skip (weight 0 = exclude)
        if (vector::contains(&ai_config.protected_tribe_ids, &candidate.character_tribe)) {
            return  // Don't add to result list = don't attack
        };

        // Rule 2: Calculate priority weight
        let mut weight: u64 = 1000;  // Base weight

        // Prioritize active attackers
        if (candidate.is_aggressor && ai_config.prefer_aggressors) {
            weight = weight + 50000;
        };

        // Lower HP higher priority (finishing blow strategy)
        let hp_score = (100 - candidate.hp_ratio) * 100;
        weight = weight + hp_score;

        // Additional weight when shield broken
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

### Strategy Comparison: Multiple AI Modes

```
Default AI:
  Active attacker (+10000) > Entered range (+1000)

Finishing Blow AI (lowest HP priority):
  is_aggressor bonus + (100-hp_ratio)*100 + shield_broken bonus

Elite Guard AI (protect allies):
  Same tribe ships weight=0 + Enemy tribe sorted by hp_ratio

Anti-PvE AI (prioritize NPCs):
  character_id==0 (NPC) → Super high weight + Players → Low weight
```

---

## 7. Authorizing Extension to Turret

Builder needs to first register extension's TypeName to turret:

```move
// Call function provided by world contract, register custom AI type to turret
// (Requires OwnerCap<Turret>)
turret::authorize_extension<my_turret::ai::AiType>(
    turret,
    owner_cap,
    ctx,
);
```

Afterwards game engine will call that extension package's `get_target_priority_list` when needing decisions.

In production environments, problems more often arise not from AI math formulas themselves, but from "whether extension actually hooked up." That is, Builder troubleshooting order should first check whether authorization succeeded, whether turret online, whether config object readable, whether TypeName matches, then check weight algorithm. Otherwise easy to misdiagnose an authorization chain problem as AI logic problem.

---

## 8. Advanced: Dynamic AI Parameter Configuration

```move
/// Allow turret AI to dynamically update config (no need to redeploy contract)
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

## 9. State Handling: OnlineReceipt

```move
/// Proof of turret being online
pub struct OnlineReceipt {
    turret_id: ID,
}
```

Turret needs to first confirm turret online before executing certain operations. `OnlineReceipt` is one-time credential for passing "confirmed online" proof in function chain, avoiding repeated checks.

---

## 10. Practice Exercises

1. **Basic AI**: Implement "focus newbie protection" AI — prioritize ships with `hp_ratio > 80` (almost full health, clearly veterans), set weight to 0 for `hp_ratio < 30` (possibly newbies)
2. **Alliance Guardian AI**: Read alliance member list, assign high priority to non-member ships, weight 0 for member ships
3. **Leaderboard AI**: Record number of each ship type shot down by turret, automatically adjust strategy weekly (types shot down more have lower priority — because those players learned to avoid)

---

## Chapter Summary

| Concept | Key Points |
|------|------|
| `TargetCandidate` | Complete combat information of target candidate |
| `BehaviourChangeReason` | ENTERED / STARTED_ATTACK / STOPPED_ATTACK |
| `ReturnTargetPriorityList` | Return format: `item_id + priority_weight` (0=exclude) |
| `extension: Option<TypeName>` | Turret stores extension package's type name, engine dynamically calls |
| Default weights | STARTED_ATTACK +10000, ENTERED +1000 |

> Next Chapter: **KillMail System Deep Dive** — Understanding EVE Frontier's complete architecture for on-chain combat death records, from source code structure to interaction with Builder extensions.
