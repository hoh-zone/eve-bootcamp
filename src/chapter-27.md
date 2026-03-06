# 第27章：能量与燃料系统机制

> **学习目标**：深入理解 EVE Frontier 建筑运行的双层能源机制——Energy（电力容量）与 Fuel（燃料消耗），掌握 `world::energy` 和 `world::fuel` 模块的源码设计，并学会编写与这两个系统交互的 Builder 扩展。

---

> 状态：教学示例。正文中的能量/燃料模型用于帮助你读懂官方实现，字段和入口请以实际模块为准。

## 最小调用链

`Network Node 分配能量 -> 建筑检查 energy/fuel 条件 -> 业务模块消耗燃料 -> 建筑状态更新`

## 对应代码目录

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)

## 关键 Struct

| 类型 | 作用 | 阅读重点 |
|------|------|------|
| `EnergyConfig` | 不同装配类型的能量配置 | 看类型到能量需求的映射如何维护 |
| `EnergySource` | 网络节点的供能状态 | 看最大产能、当前产能、已预留能量三者关系 |
| `Fuel` 相关结构 | 建筑燃料存量与消耗状态 | 看燃料存量和时间费率如何绑定 |
| `FuelEfficiency` | 燃料类型与效率差异 | 看不同燃料如何影响续航和成本 |

## 关键入口函数

| 入口 | 作用 | 你要确认什么 |
|------|------|------|
| `available_energy` | 计算剩余可用能量 | 当前产能和已预留量是否同步更新 |
| 燃料消耗入口 | 业务执行时扣减 fuel | 扣 fuel 是否与业务动作绑在同一事务 |
| 建筑上线/离线路径 | 结合 energy + fuel 判断状态 | 是否同时满足两套条件 |

## 最容易误读的点

- `Energy` 更像容量/配额，不是“可以慢慢花掉的钱包余额”
- 只补 fuel 不补 energy，建筑仍然可能离线
- 状态判断必须和资源扣减放在同一事务，否则前端很容易读到过期状态

这章最重要的理解，不是记住几个字段名，而是区分**容量约束**和**消耗约束**。Energy 回答的是“这台建筑有没有资格挂在这张电网上运行”；Fuel 回答的是“它此刻还能维持多久”。前者更像并发配额，后者更像时间账本。把这两件事混成一个余额模型，Builder 在设计在线状态、预警逻辑和补给系统时很容易出错。

## 1. 为什么需要双层能源系统？

EVE Frontier 的建筑（SmartAssembly）需要同时管理两种不同性质的"资源"：

| 概念 | 对应模块 | 性质 | 类比 |
|------|---------|------|------|
| **Energy（能量）** | `world::energy` | 功率/容量，持续可用 | 电网容量（KW） |
| **Fuel（燃料）** | `world::fuel` | 消耗品，有存量 | 发电机的燃油（升） |

- 建筑联网（NetworkNode）会分配一定的 **能量容量** 给各个接入的建筑
- 建筑本身需要持续燃烧 **燃料** 来维持运行

从 Builder 视角看，这意味着很多“离线”其实有两种完全不同的根因：一种是没电网容量了，另一种是没燃料了。它们在玩家体验上都表现为“建筑不能用了”，但在产品动作上不一样。容量不足常常需要做网络拓扑、建筑接入顺序或升级决策；燃料不足更像补给、收费、代运营的问题。把这两个诊断面拆开，后面的告警和收费系统才会清晰。

---

## 2. Energy 模块

### 2.1 核心数据结构

```move
// world/sources/primitives/energy.move

pub struct EnergyConfig has key {
    id: UID,
    // type_id → 该装配类型所需能量数值
    assembly_energy: Table<u64, u64>,
}

pub struct EnergySource has store {
    max_energy_production: u64,      // 最大发电量（NetworkNode 的能量上限）
    current_energy_production: u64,  // 当前激活的发电量
    total_reserved_energy: u64,      // 已被各建筑预留的总能量
}
```

### 2.2 能量计算公式

```move
/// 可用能量 = 当前产能 - 已预留能量
pub fun available_energy(energy_source: &EnergySource): u64 {
    if (energy_source.current_energy_production > energy_source.total_reserved_energy) {
        energy_source.current_energy_production - energy_source.total_reserved_energy
    } else {
        0  // 不能为负
    }
}
```

### 2.3 能量预留与释放

当一个建筑（如 Gate 或 Turret）加入 NetworkNode 时：

```move
// 内部包函数（Builder 不直接调用）
pub(package) fun reserve(
    energy_source: &mut EnergySource,
    energy_source_id: ID,
    assembly_type_id: u64,           // 要接入的建筑类型
    energy_config: &EnergyConfig,    // 读取该类型所需能量数
    ctx: &TxContext,
) {
    let energy_required = energy_config.assembly_energy(assembly_type_id);
    assert!(energy_source.available_energy() >= energy_required, EInsufficientAvailableEnergy);

    energy_source.total_reserved_energy = energy_source.total_reserved_energy + energy_required;
    event::emit(EnergyReservedEvent { ... });
}
```

### 2.4 EnergyConfig 的配置（仅管理员）

```move
pub fun set_energy_config(
    energy_config: &mut EnergyConfig,
    admin_acl: &AdminACL,
    assembly_type_id: u64,
    energy_required: u64,            // 该类型建筑运行需要多少能量
) {
    admin_acl.verify_sponsor(ctx);
    if (energy_config.assembly_energy.contains(assembly_type_id)) {
        *energy_config.assembly_energy.borrow_mut(assembly_type_id) = energy_required;
    } else {
        energy_config.assembly_energy.add(assembly_type_id, energy_required);
    };
}
```

---

## 3. Fuel 模块（重点：时间费率计算）

### 3.1 核心数据结构

```move
// world/sources/primitives/fuel.move

pub struct FuelConfig has key {
    id: UID,
    // fuel_type_id → 效率倍数（BPS，10000 = 100%）
    fuel_efficiency: Table<u64, u64>,
}

public struct Fuel has store {
    type_id: Option<u64>,           // 当前填充的燃料类型
    quantity: u64,                  // 剩余燃料数量
    max_capacity: u64,              // 燃料槽最大容量
    burn_rate_in_ms: u64,           // 基础燃烧速率（ms/单位）
    is_burning: bool,               // 是否正在燃烧
    burn_start_time: u64,           // 最近一次开始燃烧的时间戳
    previous_cycle_elapsed_time: u64, // 上一次周期的剩余时间（防止精度丢失）
    last_updated: u64,              // 最后更新时间
}
```

### 3.2 燃烧周期计算（精读）

这是 Fuel 模块最复杂的部分：

```move
fun calculate_units_to_consume(
    fuel: &Fuel,
    fuel_config: &FuelConfig,
    current_time_ms: u64,
): (u64, u64) {           // 返回：(消耗单位数, 剩余毫秒数)

    if (!fuel.is_burning || fuel.burn_start_time == 0) {
        return (0, 0)
    };

    // 1. 从 FuelConfig 读取该燃料类型的效率
    let fuel_type_id = *option::borrow(&fuel.type_id);
    let fuel_efficiency = fuel_config.fuel_efficiency.borrow(fuel_type_id);

    // 2. 实际消耗速率 = 基础速率 × 效率系数
    let actual_consumption_rate_ms =
        (fuel.burn_rate_in_ms * fuel_efficiency) / PERCENTAGE_DIVISOR;
    //  例如：burn_rate=3600000ms(1hr/单位), efficiency=5000(50%)
    //  实际每单位 = 3600000 * 5000 / 10000 = 1800000ms（30分钟）

    // 3. 计算经过的总时间（含上一周期剩余时间）
    let elapsed_ms = if (current_time_ms > fuel.burn_start_time) {
        current_time_ms - fuel.burn_start_time
    } else { 0 };

    // 保留上一周期的"零头"时间，避免精度丢失
    let total_elapsed_ms = elapsed_ms + fuel.previous_cycle_elapsed_time;

    // 4. 整除得到消耗单位数
    let units_to_consume = total_elapsed_ms / actual_consumption_rate_ms;
    // 5. 取余得到下一周期的起始时间
    let remaining_elapsed_ms = total_elapsed_ms % actual_consumption_rate_ms;

    (units_to_consume, remaining_elapsed_ms)
}
```

**为什么需要 `previous_cycle_elapsed_time`？**

```

这段设计体现的是“链上定时计费”常见的一个难点：你没法像游戏服务器那样每秒 tick 一次，只能在离散交易里结算已经流逝的时间。所以 `previous_cycle_elapsed_time` 实际是在保存上次结算没能整除掉的那部分时间尾差。如果没有它，系统每次结算都会向下取整，长期下来会系统性少扣燃料，经济模型就会被慢慢掏空。
时间轴示例（burn_rate = 1小时/单位）：
│───────────────────────────────────────────────────│
0              60min          90min         120min

第一次 update(90min时)：
  elapsed = 90min
  units = 90min / 60min = 1 单位消耗
  remaining = 90min % 60min = 30min  ← 保存到 previous_cycle_elapsed_time

第二次 update(120min时)：
  elapsed = 30min（从上次 burn_start_time 算）
  total = 30min + 30min(previous) = 60min
  units = 60min / 60min = 1 单位消耗
  remaining = 0
```

### 3.3 update 函数：批量结算

```move
/// 游戏服务器定期调用此函数，结算燃料消耗
pub(package) fun update(
    fuel: &mut Fuel,
    assembly_id: ID,
    assembly_key: TenantItemId,
    fuel_config: &FuelConfig,
    clock: &Clock,
) {
    // 未燃烧 → 直接返回
    if (!fuel.is_burning || fuel.burn_start_time == 0) { return };

    let current_time_ms = clock.timestamp_ms();
    if (fuel.last_updated == current_time_ms) { return }; // 同一区块内幂等

    let (units_to_consume, remaining_elapsed_ms) =
        calculate_units_to_consume(fuel, fuel_config, current_time_ms);

    if (fuel.quantity >= units_to_consume) {
        // 有足够燃料：正常消耗
        consume_fuel_units(fuel, ..., units_to_consume, remaining_elapsed_ms, current_time_ms);
        fuel.last_updated = current_time_ms;
    } else {
        // 燃料耗尽：自动停止燃烧
        stop_burning(fuel, assembly_id, assembly_key, fuel_config, clock);
    }
}
```

### 3.4 一个已知 Bug（源码注释）

```move
pub(package) fun start_burning(fuel: &mut Fuel, ...) {
    // ...
    if (fuel.quantity != 0) {
        // todo : fix bug: consider previous cycle elapsed time
        fuel.quantity = fuel.quantity - 1; // Consume 1 unit to start the clock
    };
```

启动燃烧时直接扣 1 单位，但没有考虑 `previous_cycle_elapsed_time` 可能导致这个单位被重复计算。这是源码中明确注释的已知 Bug。学习要点：即使是生产合约也会有 Bug，读源码时要批判性思考。

---

## 4. Builder 如何感知燃料状态？

Builder 扩展通常**不直接操作** Fuel 对象（它是 `pub(package)` 内部字段），但可以通过建筑的状态间接判断：

```move
use world::assemblies::gate::{Self, Gate};
use world::status;

/// 检查 Gate 是否在线（间接反映燃料状态）
pub fun is_gate_operational(gate: &Gate): bool {
    gate.status().is_online()
}
```

当燃料耗尽时，游戏服务器会调用 `stop_burning`，然后建筑的 `Status` 会变为 `Offline`，Builder 合约通过 `Status` 感知：

```move
// 只有在线建筑才能处理跳跃请求
assert!(source_gate.status.is_online(), ENotOnline);
```

这也是一个很重要的边界：World 内核把燃料细节藏在包内，不是为了限制 Builder，而是为了避免扩展直接篡改底层计费状态。Builder 更适合围绕“是否在线”“剩余补给是否足够”“是否需要提醒/收费/捐赠”来做产品层逻辑，而不是自己发明另一套 fuel 账本。

---

## 5. Energy vs Fuel 的状态流转

```
Fuel 状态机：
   EMPTY
     │ deposit_fuel()
     ▼
   LOADED
     │ start_burning()
     ▼
   BURNING ──── update() ────► 燃料充足继续 BURNING
     │                          │
     │                          ▼ 燃料耗尽
     │                        OFFLINE（建筑下线）
     │ stop_burning()
     ▼
   STOPPED（保留 previous_cycle_elapsed_time）

Energy 状态机（更简单）：
   OFF
     │ start_energy_production()
     ▼
   ON（持续提供 max_energy_production 的容量）
     │ stop_energy_production()
     ▼
   OFF
```

---

## 6. FuelEfficiency 设计：支持多种燃料类型

```move
pub struct FuelConfig has key {
    id: UID,
    fuel_efficiency: Table<u64, u64>,  // fuel_type_id → efficiency_bps
}
```

不同类型的燃料（不同 `type_id`）有不同的效率：

| fuel_type_id | 燃料名称 | efficiency_bps | 说明 |
|---|---|---|---|
| 1001 | 标准燃料 | 10000 (100%) | 基准效率 |
| 1002 | 高效燃料 | 15000 (150%) | 燃烧更久 |
| 1003 | 普通燃料棒 | 8000 (80%) | 便宜但低效 |

效率越高，同等燃料量能维持建筑运行越长时间。Builder 可以在扩展中要求玩家使用特定类型燃料。

---

## 7. 实战练习

1. **燃料计算器**：给定 `burn_rate_in_ms = 3600000`，`fuel_efficiency = 7500`，剩余 `quantity = 10`，计算还能运行多少小时
2. **燃料预警合约**：写一个 Builder 扩展，当 Gate 的燃料剩余量不足 5 单位时，自动向物主发送一个链上事件提醒
3. **燃料捐献系统**：设计一个共享 `FuelDonationPool`，允许任意玩家向建筑捐赠燃料

---

## 本章小结

| 概念 | 要点 |
|------|------|
| `EnergySource` | 功率容量系统，预留/释放模式 |
| `Fuel` | 消耗品系统，基于时间的燃烧周期 |
| `previous_cycle_elapsed_time` | 防止时间取整导致的精度损失 |
| `fuel_efficiency` | 不同燃料类型的效率倍数（BPS） |
| 已知 Bug | `start_burning` 的 1 单位扣除未考虑前序剩余时间 |

> 下一章：**Extension 模式实战** —— 用官方 `extension_examples` 的两个真实示例，掌握 Builder 扩展的标准开发流程。
