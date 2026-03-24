# Chapter 6: Complete Guide to Builder Scaffold (Part 1) — Project Structure and Contract Development

> **Learning Objectives**: Master the complete directory structure of `builder-scaffold`, understand both Docker and native development workflows, and be able to independently complete local development and deployment of the smart_gate contract.

---

> Status: Mapped to local scaffold directory. Commands in this text are based on the existing `builder-scaffold` directory in this repository.

## Minimal Call Chain

`Start local chain -> Compile smart_gate -> Deploy -> Record package/object id -> Configure rules -> Issue permit`

## Corresponding Code Directory

- [builder-scaffold](https://github.com/evefrontier/builder-scaffold)

## 1. What is Builder Scaffold?

`builder-scaffold` is the official one-stop Builder development scaffold provided by EVE Frontier, including:

- **Move Contract Templates**: Two complete Smart Gate Extension examples
- **TypeScript Interaction Scripts**: Ready-to-use on-chain interaction scripts after deployment
- **Docker Development Environment**: Zero-configuration, out-of-the-box local chain
- **dApp Template**: React + EVE Frontier dapp-kit frontend starting point

```
builder-scaffold/
├── docker/             # Docker dev environment (Sui CLI + Node.js container)
├── move-contracts/     # Move contract examples
│   ├── smart_gate/     # Main example: Star Gate Extension
│   ├── storage_unit/   # Storage Unit Extension example
│   └── tokens/         # Token contract example
├── ts-scripts/         # TypeScript interaction scripts
│   ├── smart_gate/     # 6 operation scripts for smart_gate
│   ├── utils/          # Common utilities: env config, derive-object-id, proof
│   └── helpers/        # Helper functions for querying OwnerCap, etc.
├── dapps/              # React dApp template (EVE Frontier dapp-kit)
└── docs/               # Complete deployment flow documentation
```

The most important thing about this chapter isn't memorizing the directory structure, but understanding:

> `builder-scaffold` isn't just an example repository; it's actually pre-wiring "local chain, contracts, scripts, and frontend" together for you.

So the real value is:

- Reducing the cost of getting the full loop working for the first time
- Giving you a standard skeleton that can be modified and run iteratively
- Making future custom development start from "modifying templates" rather than "building the platform yourself"

---

## 2. Choosing a Development Workflow

The official documentation supports two workflows:

| Workflow | Applicable Scenario | Prerequisites |
|------|---------|---------|
| **Docker Workflow** | Users who don't want to install Sui/Node locally | Docker only |
| **Host Workflow** | Already have Sui CLI + Node.js | Sui CLI + Node.js |

### The Real Trade-offs of These Two Workflows

- **Docker**
  More stable, fewer environment differences, suitable for getting it working first
- **Host**
  Faster, closer to daily development, but more dependent on your local environment being clean

If your goal is to "understand the complete loop first", prioritize Docker.
If your goal is "high-frequency iteration writing your own code", you'll typically gradually transition to Host.

---

## 3. Docker Development Environment (Recommended for Beginners)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/evefrontier/builder-scaffold.git
cd builder-scaffold

# Start the development container (first time will download images, ~2-3 minutes)
cd docker
docker compose run --rm --service-ports sui-dev
```

On first startup, the container will automatically:
1. Create 3 ed25519 key pairs (`ADMIN`, `PLAYER_A`, `PLAYER_B`)
2. Start the local Sui node
3. Fund accounts with test SUI

Keys are persistently saved in Docker Volume and won't be lost when the container restarts.

### Working Directory Structure Inside Container

```
/workspace/
├── builder-scaffold/    # Complete repository (synced with host)
└── world-contracts/     # Visible in container after cloning on host
```

Edit files on the host, run commands in the container — both are synced in real-time.

### Why Use `-e testnet` When Building?

```bash
sui move build -e testnet   # ← The testnet here is "build environment", not deployment target
```

The local chain's chain ID changes every restart and can't be fixed in `Move.toml`. `-e testnet` lets dependency resolution use testnet rules, but actual deployment still goes to the local chain.

The most easily misunderstood part here is conflating "build environment" with "deployment target" as the same thing.

Using `-e testnet` here doesn't mean you're actually deploying to testnet now, but rather tells the builder:

- By which set of rules should dependencies be resolved
- How should package builds be processed according to which environment conventions

If this concept isn't separated, later when switching between localnet / testnet / mainnet, you'll be very prone to making incorrect judgments.

### Container Common Commands Reference

| Task | Command |
|------|------|
| View all keys | `cat /workspace/builder-scaffold/docker/.env.sui` |
| Switch to testnet | `sui client switch --env testnet` |
| Import existing key | `sui keytool import <key> ed25519` |
| Compile contract | `cd .../smart_gate && sui move build -e testnet` |
| Run TS script | `cd /workspace/builder-scaffold && pnpm configure-rules` |
| Start GraphQL | `curl http://localhost:9125/graphql` |
| Clear and reset | `docker compose down --volumes && docker compose run --rm --service-ports sui-dev` |

### PostgreSQL + GraphQL Indexer

The Docker environment has built-in Sui indexer and GraphQL support:

```bash
# Query chain ID (verify GraphQL startup)
curl -X POST http://localhost:9125/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ chainIdentifier }"}'
```

GraphQL endpoint: `http://localhost:9125/graphql` (can be debugged with [Altair](https://altairgraphql.dev/))

---

## 4. Smart Gate Contract File Structure

```
move-contracts/smart_gate/
├── Move.toml                # Package config (depends on world-contracts)
├── sources/
│   ├── config.move          # Shared config foundation: ExtensionConfig + AdminCap + XAuth
│   ├── tribe_permit.move    # Example 1: Tribal identity verification pass
│   └── corpse_gate_bounty.move # Example 2: Submit corpse items for pass
└── tests/
    └── gate_tests.move      # Tests
```

### Move.toml Analysis

```toml
[package]
name = "smart_gate"
edition = "2024"

[dependencies]
# Git dependency (recommended to lock stable tag)
world = { git = "https://github.com/evefrontier/world-contracts.git", subdir = "contracts/world", rev = "v0.0.14" }

[addresses]
smart_gate = "0x0"   # Automatically replaced with actual address on deployment
```

> **Important**: It's recommended to use git dependencies and lock the `rev` (e.g., `v0.0.14`), don't track `main`, otherwise breaking changes in the world-contracts main branch will directly affect compilation results.

### Why the Scaffold Example Is Best for Learning "Extension Pattern"

Because it's not an abstract demo, but rather puts several key Builder elements in:

- Dynamic field configuration
- AdminCap management
- Typed Witness extension
- Gate component integration

In other words, `smart_gate` isn't teaching you to write a specific business case, but teaching you the core extension skeleton of EVE Builder.

---

## 5. config.move: Extension Base Framework

```move
module smart_gate::config;

use sui::dynamic_field as df;

/// Automatically created after deployment, shared storage for all rules
public struct ExtensionConfig has key {
    id: UID,
}

/// Admin permission credential (transferred to deployer on init)
public struct AdminCap has key, store {
    id: UID,
}

/// Authorization witness type (Typed Witness), passed to gate::issue_jump_permit<XAuth>
public struct XAuth has drop {}

fun init(ctx: &mut TxContext) {
    // Transfer AdminCap to deployer
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
    // Share ExtensionConfig (everyone can read, only AdminCap holders can write)
    transfer::share_object(ExtensionConfig { id: object::new(ctx) });
}
```

### Dynamic Field Rules System

`ExtensionConfig` uses dynamic fields to store various rules, allowing a single config object to support multiple different extension rules simultaneously:

```move
// set_rule: Insert or overwrite rule (value needs drop ability)
public fun set_rule<K: copy + drop + store, V: store + drop>(
    config: &mut ExtensionConfig,
    _: &AdminCap,      // Only AdminCap can set
    key: K,
    value: V,
) {
    if (df::exists_(&config.id, copy key)) {
        let _old: V = df::remove(&mut config.id, copy key);
    };
    df::add(&mut config.id, key, value);
}
```

---

## 6. tribe_permit.move: Tribal Pass (Detailed Reading)

This is the simplest Extension implementation, suitable for understanding the core structure of the extension pattern:

```move
module smart_gate::tribe_permit;

// Rule configuration (dynamic field value)
public struct TribeConfig has drop, store {
    tribe: u32,              // Allowed tribe ID
    expiry_duration_ms: u64, // Pass validity period (milliseconds)
}

// Rule identifier (dynamic field Key)
public struct TribeConfigKey has copy, drop, store {}
```

### Issuing a Pass

```move
pub fun issue_jump_permit(
    extension_config: &ExtensionConfig,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. Read rule configuration
    let tribe_cfg = extension_config.borrow_rule<TribeConfigKey, TribeConfig>(TribeConfigKey {});

    // 2. Verify character tribe
    assert!(character.tribe() == tribe_cfg.tribe, ENotStarterTribe);

    // 3. Calculate expiry time (overflow check)
    let ts = clock.timestamp_ms();
    assert!(ts <= (0xFFFFFFFFFFFFFFFFu64 - tribe_cfg.expiry_duration_ms), EExpiryOverflow);
    let expires_at = ts + tribe_cfg.expiry_duration_ms;

    // 4. Call world contract to issue JumpPermit NFT
    gate::issue_jump_permit<XAuth>(
        source_gate, destination_gate, character,
        config::x_auth(),  // Package-unique XAuth instance
        expires_at, ctx,
    );
}
```

> **Design Detail**: Compared to the original in world-contracts, this adds **overflow checking** (`EExpiryOverflow`), making it a more robust production implementation.

### Admin Rule Setting

```move
pub fun set_tribe_config(
    extension_config: &mut ExtensionConfig,
    admin_cap: &AdminCap,
    tribe: u32,
    expiry_duration_ms: u64,
) {
    extension_config.set_rule<TribeConfigKey, TribeConfig>(
        admin_cap,
        TribeConfigKey {},
        TribeConfig { tribe, expiry_duration_ms },
    );
}
```

---

## 7. Compilation and Testing

```bash
# Enter smart_gate directory
cd move-contracts/smart_gate

# Compile (use testnet as build environment)
sui move build -e testnet

# Run tests
sui move test -e testnet
```

### Common Compilation Failure Issues

| Error Message | Cause | Solution |
|---------|------|---------|
| `Unpublished dependencies: World` | world-contracts not deployed | Deploy world-contracts first, or switch to local dependency |
| `Move.lock wrong env` | Move.lock recorded environment doesn't match | `rm Move.lock && sui move build -e testnet` |
| `edition = "legacy"` warning | Using old version Move | Change to `edition = "2024"` in `Move.toml` |

---

## 8. Publishing Contract to Local Chain

```bash
# Ensure world-contracts is deployed, obtaining its publication file
sui client test-publish \
  --build-env testnet \
  --pubfile-path ../../deployments/Pub.localnet.toml

# After successful publication, record the output Package ID
# Fill in BUILDER_PACKAGE_ID in .env file
```

> **`test-publish` vs `publish`**: `test-publish` is Sui's special publish mode that allows publishing packages with unpublished dependencies on the local chain (for testing). For actual deployment to testnet/mainnet, use `sui client publish`.

---

## 9. Adding Your Own Extension Rules

Using the example of adding a "toll gate rule":

### Step 1: Create a new file `toll_gate.move` alongside `config.move`

```move
module smart_gate::toll_gate;

use smart_gate::config::{Self, AdminCap, XAuth, ExtensionConfig};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};

// Rule data
public struct TollConfig has drop, store {
    toll_amount: u64,
    expiry_duration_ms: u64,
}
public struct TollConfigKey has copy, drop, store {}

// Fee ledger (shared object)
public struct TollVault has key {
    id: UID,
    balance: Balance<SUI>,
}

// Create vault on initialization
public fun create_vault(ctx: &mut TxContext) {
    transfer::share_object(TollVault {
        id: object::new(ctx),
        balance: balance::zero(),
    });
}
```

### Step 2: Implement Issuance Function

```move
pub fun pay_and_jump(
    extension_config: &ExtensionConfig,
    vault: &mut TollVault,
    source_gate: &Gate,
    destination_gate: &Gate,
    character: &Character,
    mut payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let toll_cfg = extension_config.borrow_rule<TollConfigKey, TollConfig>(TollConfigKey {});
    assert!(coin::value(&payment) >= toll_cfg.toll_amount, ETollInsufficient);

    let toll = coin::split(&mut payment, toll_cfg.toll_amount, ctx);
    balance::join(&mut vault.balance, coin::into_balance(toll));
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    let expires = clock.timestamp_ms() + toll_cfg.expiry_duration_ms;
    gate::issue_jump_permit<XAuth>(
        source_gate, destination_gate, character, config::x_auth(), expires, ctx,
    );
}

const ETollInsufficient: u64 = 0;
```

---

## Chapter Summary

| Component | Purpose |
|------|------|
| `docker/compose.yml` | One-click startup for local Sui chain + GraphQL indexer |
| `move-contracts/smart_gate/` | Gate Extension main template |
| `config.move` | ExtensionConfig + AdminCap + XAuth base framework |
| `tribe_permit.move` | Example ①: Tribal identity verification |
| `corpse_gate_bounty.move` | Example ②: Item consumption for pass |
| `-e testnet` build flag | Solves local chain chain ID instability problem |

> Next Chapter: **TypeScript Scripts and dApp Development** — After contract deployment, how to interact with on-chain contracts using 6 ready-made scripts, and how to build an EVE Frontier frontend based on the dApp template.
