# Chapter 29: Energy and Fuel System Mechanics

> **Learning Objective**: Deeply understand EVE Frontier's dual-layer energy mechanism for building operations — Energy (power capacity) and Fuel (fuel consumption), master the source code design of `world::energy` and `world::fuel` modules, and learn to write Builder extensions that interact with these two systems.

---

> Status: Teaching example. The energy/fuel models in the text help you understand official implementations; refer to actual modules for fields and entries when implementing.

## Minimal Call Chain

`Network Node allocates energy -> Building checks energy/fuel conditions -> Business module consumes fuel -> Building state updates`

## Corresponding Code Directory

- [world-contracts/contracts/world](https://github.com/evefrontier/world-contracts/tree/main/contracts/world)

## Key Structs

| Type | Purpose | Reading Focus |
|------|------|------|
| `EnergyConfig` | Energy configuration for different assembly types | How type-to-energy requirement mapping is maintained |
| `EnergySource` | Network node's power supply state | Relationship between max output, current output, reserved energy |
| `Fuel` related structures | Building fuel inventory and consumption state | How fuel inventory and time rate are bound |
| `FuelEfficiency` | Fuel type and efficiency differences | How different fuels affect runtime and cost |

## Key Entry Functions

| Entry | Purpose | What to Confirm |
|------|------|------|
| `available_energy` | Calculate remaining available energy | Whether current output and reserved amount are updated synchronously |
| Fuel consumption entry | Deduct fuel when business executes | Whether fuel deduction is bound in same transaction as business action |
| Building online/offline path | Judge state combining energy + fuel | Whether both condition sets are satisfied |

## Most Easily Misunderstood Points

- `Energy` is more like capacity/quota, not "wallet balance that can be slowly spent"
- Only replenishing fuel without replenishing energy can still cause building to go offline
- State judgment must be in same transaction as resource deduction, otherwise frontend easily reads stale state

The most important understanding in this chapter isn't memorizing field names, but distinguishing **capacity constraint** and **consumption constraint**. Energy answers "does this building have the right to run on this power grid"; Fuel answers "how long can it maintain right now". The former is more like concurrency quota, the latter more like time ledger. Mixing these two into one balance model makes Builders prone to errors when designing online status, warning logic, and supply systems.

## 1. Why a Dual-Layer Energy System?

EVE Frontier's buildings (SmartAssembly) need to manage two different types of "resources" simultaneously:

| Concept | Corresponding Module | Nature | Analogy |
|------|---------|------|------|
| **Energy** | `world::energy` | Power/capacity, continuously available | Grid capacity (KW) |
| **Fuel** | `world::fuel` | Consumable, has inventory | Generator's fuel oil (liters) |

- Building networking (NetworkNode) allocates certain **energy capacity** to each connected building
- Buildings themselves need to continuously burn **fuel** to maintain operation

From a Builder perspective, this means many "offline" cases actually have two completely different root causes: one is no grid capacity, another is no fuel. They both manifest to player experience as "building can't be used," but product actions are different. Capacity shortage often requires network topology, building connection order, or upgrade decisions; fuel shortage is more like supply, charging, agency operation problems. Separating these two diagnostic surfaces makes subsequent warning and charging systems clearer.

---

## 2. Energy Module

###  2.1 Core Data Structure

```move
// world/sources/primitives/energy.move

pub struct EnergyConfig has key {
    id: UID,
    // type_id → energy value required for this assembly type
    assembly_energy: Table<u64, u64>,
}

pub struct EnergySource has store {
    max_energy_production: u64,      // Max power generation (NetworkNode's energy ceiling)
    current_energy_production: u64,  // Currently activated power generation
    total_reserved_energy: u64,      // Total energy reserved by buildings
}
```

###  2.2 Energy Calculation Formula

```move
/// Available energy = current production - reserved energy
pub fun available_energy(energy_source: &EnergySource): u64 {
    if (energy_source.current_energy_production > energy_source.total_reserved_energy) {
        energy_source.current_energy_production - energy_source.total_reserved_energy
    } else {
        0  // Cannot be negative
    }
}
```

###  2.3 Energy Reservation and Release

When a building (like Gate or Turret) joins NetworkNode:

```move
// Internal package function (Builder doesn't call directly)
pub(package) fun reserve(
    energy_source: &mut EnergySource,
    energy_source_id: ID,
    assembly_type_id: u64,           // Building type to connect
    energy_config: &EnergyConfig,    // Read energy required for this type
    ctx: &TxContext,
) {
    let energy_required = energy_config.assembly_energy(assembly_type_id);
    assert!(energy_source.available_energy() >= energy_required, EInsufficientAvailableEnergy);

    energy_source.total_reserved_energy = energy_source.total_reserved_energy + energy_required;
    event::emit(EnergyReservedEvent { ... });
}
```

###  2.4 EnergyConfig Configuration (Admin Only)

```move
pub fun set_energy_config(
    energy_config: &mut EnergyConfig,
    admin_acl: &AdminACL,
    assembly_type_id: u64,
    energy_required: u64,            // How much energy this building type requires
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

## 3. Fuel Module (Focus: Time Rate Calculation)

###  3.1 Core Data Structure

```move
// world/sources/primitives/fuel.move

pub struct FuelConfig has key {
    id: UID,
    // fuel_type_id → efficiency multiplier (BPS, 10000 = 100%)
    fuel_efficiency: Table<u64, u64>,
}

public struct Fuel has store {
    type_id: Option<u64>,           // Currently filled fuel type
    quantity: u64,                  // Remaining fuel quantity
    max_capacity: u64,              // Fuel tank maximum capacity
    burn_rate_in_ms: u64,           // Base burn rate (ms/unit)
    is_burning: bool,               // Whether currently burning
    burn_start_time: u64,           // Last burn start timestamp
    previous_cycle_elapsed_time: u64, // Previous cycle's remaining time (prevent precision loss)
    last_updated: u64,              // Last update time
}
```

###  3.2 Burn Cycle Calculation (Deep Dive)

This is the most complex part of the Fuel module:

```move
fun calculate_units_to_consume(
    fuel: &Fuel,
    fuel_config: &FuelConfig,
    current_time_ms: u64,
): (u64, u64) {           // Returns: (consumed units, remaining milliseconds)

    if (!fuel.is_burning || fuel.burn_start_time == 0) {
        return (0, 0)
    };

    // 1. Read efficiency for this fuel type from FuelConfig
    let fuel_type_id = *option::borrow(&fuel.type_id);
    let fuel_efficiency = fuel_config.fuel_efficiency.borrow(fuel_type_id);

    // 2. Actual consumption rate = base rate × efficiency coefficient
    let actual_consumption_rate_ms =
        (fuel.burn_rate_in_ms * fuel_efficiency) / PERCENTAGE_DIVISOR;
    //  Example: burn_rate=3600000ms(1hr/unit), efficiency=5000(50%)
    //  Actual per unit = 3600000 * 5000 / 10000 = 1800000ms (30 minutes)

    // 3. Calculate total elapsed time (including previous cycle's remaining time)
    let elapsed_ms = if (current_time_ms > fuel.burn_start_time) {
        current_time_ms - fuel.burn_start_time
    } else { 0 };

    // Keep previous cycle's "fractional" time to avoid precision loss
    let total_elapsed_ms = elapsed_ms + fuel.previous_cycle_elapsed_time;

    // 4. Integer division to get consumed units
    let units_to_consume = total_elapsed_ms / actual_consumption_rate_ms;
    // 5. Remainder becomes next cycle's start time
    let remaining_elapsed_ms = total_elapsed_ms % actual_consumption_rate_ms;

    (units_to_consume, remaining_elapsed_ms)
}
```

**Why `previous_cycle_elapsed_time` is needed?**

```
This design addresses a common difficulty in "on-chain timed billing": you can't tick every second like a game server, only settle elapsed time in discrete transactions. So `previous_cycle_elapsed_time` actually saves the time remainder from last settlement that couldn't be fully divided. Without it, each settlement would round down, systematically under-charging fuel over time, eventually draining the economic model.

Timeline example (burn_rate = 1 hour/unit):
│───────────────────────────────────────────────────│
0              60min          90min         120min

First update (at 90min):
  elapsed = 90min
  units = 90min / 60min = 1 unit consumed
  remaining = 90min % 60min = 30min  ← Saved to previous_cycle_elapsed_time

Second update (at 120min):
  elapsed = 30min (from last burn_start_time)
  total = 30min + 30min(previous) = 60min
  units = 60min / 60min = 1 unit consumed
  remaining = 0
```

###  3.3 update Function: Batch Settlement

```move
/// Game server periodically calls this function to settle fuel consumption
pub(package) fun update(
    fuel: &mut Fuel,
    assembly_id: ID,
    assembly_key: TenantItemId,
    fuel_config: &FuelConfig,
    clock: &Clock,
) {
    // Not burning → return directly
    if (!fuel.is_burning || fuel.burn_start_time == 0) { return };

    let current_time_ms = clock.timestamp_ms();
    if (fuel.last_updated == current_time_ms) { return }; // Idempotent within same block

    let (units_to_consume, remaining_elapsed_ms) =
        calculate_units_to_consume(fuel, fuel_config, current_time_ms);

    if (fuel.quantity >= units_to_consume) {
        // Enough fuel: consume normally
        consume_fuel_units(fuel, ..., units_to_consume, remaining_elapsed_ms, current_time_ms);
        fuel.last_updated = current_time_ms;
    } else {
        // Fuel depleted: automatically stop burning
        stop_burning(fuel, assembly_id, assembly_key, fuel_config, clock);
    }
}
```

###  3.4 A Known Bug (Source Code Comment)

```move
pub(package) fun start_burning(fuel: &mut Fuel, ...) {
    // ...
    if (fuel.quantity != 0) {
        // todo : fix bug: consider previous cycle elapsed time
        fuel.quantity = fuel.quantity - 1; // Consume 1 unit to start the clock
    };
```

Starting burn directly deducts 1 unit, but doesn't consider `previous_cycle_elapsed_time` which may cause this unit to be double-counted. This is a clearly commented known bug in source code. Learning point: even production contracts have bugs; read source code with critical thinking.

---

## 4. How Do Builders Sense Fuel Status?

Builder extensions typically **don't directly manipulate** Fuel objects (it's `pub(package)` internal field), but can indirectly judge through building status:

```move
use world::assemblies::gate::{Self, Gate};
use world::status;

/// Check if Gate is operational (indirectly reflects fuel status)
pub fun is_gate_operational(gate: &Gate): bool {
    gate.status().is_online()
}
```

When fuel depletes, game server calls `stop_burning`, then building's `Status` changes to `Offline`, Builder contracts sense through `Status`:

```move
// Only online buildings can process jump requests
assert!(source_gate.status.is_online(), ENotOnline);
```

This is also an important boundary: World kernel hides fuel details within package, not to limit Builders, but to prevent extensions from directly tampering with underlying billing state. Builders are better suited to build product-layer logic around "whether online," "whether supply sufficient," "whether need reminder/charge/donation," rather than inventing another fuel ledger.

---

## 5. Energy vs Fuel State Flow

```
Fuel State Machine:
   EMPTY
     │ deposit_fuel()
     ▼
   LOADED
     │ start_burning()
     ▼
   BURNING ──── update() ────► Fuel sufficient continue BURNING
     │                          │
     │                          ▼ Fuel depleted
     │                        OFFLINE (building offline)
     │ stop_burning()
     ▼
   STOPPED (preserves previous_cycle_elapsed_time)

Energy State Machine (simpler):
   OFF
     │ start_energy_production()
     ▼
   ON (continuously provides max_energy_production capacity)
     │ stop_energy_production()
     ▼
   OFF
```

---

## 6. FuelEfficiency Design: Supporting Multiple Fuel Types

```move
pub struct FuelConfig has key {
    id: UID,
    fuel_efficiency: Table<u64, u64>,  // fuel_type_id → efficiency_bps
}
```

Different fuel types (different `type_id`) have different efficiencies:

| fuel_type_id | Fuel Name | efficiency_bps | Description |
|---|---|---|---|
| 1001 | Standard Fuel | 10000 (100%) | Baseline efficiency |
| 1002 | High-Efficiency Fuel | 15000 (150%) | Burns longer |
| 1003 | Common Fuel Rod | 8000 (80%) | Cheap but inefficient |

Higher efficiency means same fuel quantity can maintain building operation longer. Builders can require players to use specific fuel types in extensions.

---

## 7. Practice Exercises

1. **Fuel Calculator**: Given `burn_rate_in_ms = 3600000`, `fuel_efficiency = 7500`, remaining `quantity = 10`, calculate how many hours it can still run
2. **Fuel Warning Contract**: Write a Builder extension that automatically sends an on-chain event reminder to owner when Gate's fuel remaining is less than 5 units
3. **Fuel Donation System**: Design a shared `FuelDonationPool` allowing any player to donate fuel to buildings

---

## Chapter Summary

| Concept | Key Points |
|------|------|
| `EnergySource` | Power capacity system, reserve/release mode |
| `Fuel` | Consumable system, time-based burn cycles |
| `previous_cycle_elapsed_time` | Prevents precision loss from time rounding |
| `fuel_efficiency` | Efficiency multiplier for different fuel types (BPS) |
| Known Bug | `start_burning`'s 1 unit deduction doesn't consider prior remaining time |

> Next Chapter: **Extension Pattern in Practice** — Using two real examples from official `extension_examples`, master standard development flow for Builder extensions.
