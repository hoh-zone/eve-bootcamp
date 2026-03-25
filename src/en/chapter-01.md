# Chapter 1: EVE Frontier Macro Architecture and Core Concepts

> **Objective:** Understand what EVE Frontier is, why it chose the Sui blockchain, and the core philosophy of a "programmable universe."

---

> Status: Foundation chapter. The main text focuses on macro architecture and terminology establishment, suitable as an entry point for the entire book.

If you haven't formed a clear intuition about the game itself, we recommend reading [Preface Chapter: First Understand the EVE Frontier Game](./chapter-00.md).

## 1.1 Why is EVE Frontier Different?

Traditional online games have world rules dictated solely by developers—economic systems, combat formulas, content updates—players are merely participants. EVE Frontier challenges this paradigm: the game's core mechanics are **open**, and developers (Builders) can truly **rewrite and extend game rules** within the framework defined by the game server.

This isn't simply "MOD plugins"—the logic you write runs as smart contracts on the Sui public blockchain, permanently auditable, requiring no centralized server hosting, and executing automatically 7×24.

### What is it NOT?

Beginners most easily confuse EVE Frontier with the following things, but it's not entirely equivalent to any of them:

| Easily Confused With | Why Similar | Why Different |
|------|------|------|
| **Traditional MOD / Plugin Systems** | Both allow third-party extension of game logic | MODs typically run on centralized servers or clients; EVE Frontier's key state and rules can be on-chain, auditable, and composable |
| **Private Server Script Systems** | Both can modify default gameplay | Private server scripts are usually controlled unilaterally by operators; Builder contracts can form a public, verifiable rules market |
| **Ordinary Blockchain Game Contracts** | Both have NFTs, Tokens, markets | EVE Frontier's focus isn't on individual asset contracts, but on turning **game infrastructure** like "stargates, turrets, storage units" into programmable objects |
| **Pure On-chain Games** | Both emphasize on-chain rules | EVE Frontier still retains game servers, physics simulation, and a real-time world, so it's a hybrid system of "on-chain rules + game server collaboration" |

You can understand it as:

> EVE Frontier isn't about "putting the entire game on-chain," but rather putting **the sufficiently important, sufficiently composable, sufficiently worthy of public verification** portions of game rules on-chain.

### Three Player Roles

| Role | Primary Actions |
|------|--------|
| **Builder (Constructor)** | Write Move contracts, deploy smart components, build dApp interfaces |
| **Operator (Manager)** | Purchase/own facilities, configure Builder modules, manage economic factions |
| **Player** | Interact with facilities built by Builders/Operators, forming the game world |

> The target audience of this course is **Builders**, but understanding the other two roles helps you design more valuable products.

### How Do These Three Roles Interact?

Many people initially think these three roles are completely separate. Actually, they're not—they describe **three types of responsibilities within the same ecosystem**:

- **Builder** is responsible for "defining rules"
  Example: Write a toll stargate, rental market, alliance dividend system
- **Operator** is responsible for "operating rules"
  Example: Actually buy facilities, set rates, issue passes, maintain inventory
- **Player** is responsible for "consuming rules"
  Example: Buy tickets, rent equipment, pass turret checks, claim rewards

A minimal business chain typically looks like this:

```text
Builder writes contract
  -> Operator deploys and configures facility
  -> Player interacts with facility
  -> On-chain state changes are consumed by dApp / other Builders
```

This is why Builders can't just know how to write contracts. You also need to understand:

- What Operators care about: revenue, permissions, security, maintenance costs
- What Players care about: price, convenience, predictability, whether they're being scammed

### What Does a Minimal Builder Closed Loop Look Like?

If you compress the EVE Builder ecosystem into a minimal closed loop, it's typically this chain:

```text
Builder designs rules
  -> Deploys facilities and extensions
  -> Operator configures parameters and operates
  -> Player pays or meets conditions to use
  -> Transactions, permissions, and asset changes land on-chain
  -> Front-end and indexing layer display results
```

Every link in this chain is essential:

- Without Builders, there are no new rule facilities in the world
- Without Operators, facilities lack sustained managers
- Without Players, rules won't form real economic activity

So when designing any component later, it's best to first ask yourself three things:

1. Who defines the rules?
2. Who operates and maintains it?
3. Why would players be willing to use it?

---

## 1.2 Smart Assemblies: Programmable Space Infrastructure

**Smart Assemblies** are physical facilities built by players in space in EVE Frontier. They are both game objects and programmable contract objects on the blockchain.

More precisely, a smart assembly typically has three layers of identity simultaneously:

1. **Physical facility in the game world**
   Example: You can actually see a turret or stargate in space
2. **Shared object on-chain**
   Example: It has an object ID, state fields, permission rules
3. **Service entry point accessible to dApps**
   Example: Front-end can query its inventory, rates, online status, and initiate transactions

So when you say "I made a smart stargate," you're essentially not just making a UI, nor just writing a Move module, but creating:

> An infrastructure service that's visible in-game, verifiable on-chain, and operable from the front-end.

### Main Component Types

#### 🏗 Network Node
- Anchored at Lagrange Points
- Provides Energy for the entire base
- All facilities must connect to a network node to operate
- **Not directly programmable**, but the operational foundation for other components

#### 📦 Smart Storage Unit (SSU)
- Stores items on-chain, supports "main inventory" and "Ephemeral Inventory"
- By default, only allows Owner to deposit/withdraw items
- Through custom contracts can become: vending machines, auction houses, guild vaults

#### ⚡ Smart Turret
- Automated defense facility
- Default behavior is standard attack logic
- Through contracts can customize target locking judgment logic (e.g., only attack characters without permits)

#### 🌀 Smart Gate
- Links two locations, allows character jumps
- By default, everyone can jump
- Through contracts introduces "Jump Permit" mechanisms, enabling whitelists, fees, time limits, etc.

### Four Most Common Builder Transformation Directions for Components

| Component | Default Capability | Most Common Builder Transformations |
|------|------|------|
| Network Node | Provides power and network foundation | Generally don't directly modify logic, but build upper-layer business around energy/network status |
| Storage Unit | Store/retrieve items | Shops, auctions, rentals, quest storage, alliance vaults |
| Turret | Auto-attack | Whitelists, paid protection, combat event linkage, priority AI |
| Gate | Allow jumps | Fees, permits, quest thresholds, faction/camp filtering |

If you're unsure which component to start from for an idea, first ask yourself:

- Is it fundamentally about "storing things"? Start with `Storage Unit`
- Is it fundamentally about "deciding who can pass"? Start with `Gate`
- Is it fundamentally about "deciding who gets attacked"? Start with `Turret`
- Does it fundamentally depend on power/network constraints? Need to understand `Network Node` simultaneously

### Smart Assembly Lifecycle

A smart assembly isn't "done once deployed on-chain"—it typically goes through an entire lifecycle:

1. **Creation / Anchoring**
   Facility is first established in the world
2. **Attribution**
   It's bound to a character or operating entity
3. **Online**
   It obtains energy, network, and interactive state
4. **Extension**
   Builder plugs in custom rules
5. **Operation**
   Operator adjusts prices, inventory, permissions
6. **Consumption**
   Player has real interactions with it
7. **Offline / Migration / Deactivation**
   Facility may lose energy, upgrade, be replaced, or cease operations

The contracts, dApps, scripts, wallets, and indexing you'll learn later all serve around this lifecycle.

---

## 1.3 Three-Layer Architecture: How is the Game World Built?

EVE Frontier's world contracts use a strict three-layer architecture, which is key to understanding all subsequent content:

```
┌────────────────────────────────────────────────────┐
│  Layer 3: Player Extensions (Player Extension Layer)  │
│  Your Move contracts are here                          │
└────────────────┬───────────────────────────────────┘
                 │  Invoked via Typed Witness Pattern
┌────────────────▼───────────────────────────────────┐
│  Layer 2: Smart Assemblies (Smart Component Layer)    │
│  storage_unit.move  gate.move  turret.move            │
└────────────────┬───────────────────────────────────┘
                 │  Internal calls
┌────────────────▼───────────────────────────────────┐
│  Layer 1: Primitives (Basic Primitive Layer)          │
│  status  location  inventory  fuel  energy            │
└────────────────────────────────────────────────────┘
```

- **Layer 1 - Primitives**: Bottom-layer modules not directly callable, implementing "digital physics" (like location, inventory, fuel)
- **Layer 2 - Smart Assemblies**: Component objects exposed to players, each is a Sui Shared Object
- **Layer 3 - Player Extensions**: **Where you as a Builder work**, safely inserting custom logic through Typed Witness

> **Key Understanding**: You cannot directly modify Layer 1/2, but you can write logic in Layer 3 that interacts with components through officially authorized APIs. This ensures both the safety of the game world and provides sufficient freedom for Builders.

### What Does Each Layer Actually Handle?

| Layer | Responsible For | Typical Questions | How You Usually Encounter It |
|------|------|------|------|
| **Layer 1: Primitives** | Define lowest-level world rules | How are location, inventory, fuel, energy, state transitions represented | Usually understood through source code deep reading, not directly modified |
| **Layer 2: Assemblies** | Package low-level rules into facilities players can use | How gates jump, turrets shoot, storage units deposit/withdraw | Interact through official APIs, official component entry points |
| **Layer 3: Extensions** | Insert custom business logic without breaking the core | Who can pass gates, how much to charge, what conditions must be met before release | This is the Builder's main battlefield |

A very practical judgment criterion:

- If you're defining "world basic laws," that's usually a Layer 1 issue
- If you're defining "how official facilities work by default," that's usually a Layer 2 issue
- If you're defining "how I want my facility to work," that's usually a Layer 3 issue

### How Does a Real Interaction Pass Through Three Layers?

Taking "player pays to pass through stargate" as an example:

```text
Player clicks "Purchase and Jump" in dApp
  -> Layer 3: Your fee extension checks if payment made / if holding ticket
  -> Layer 2: Gate component executes jump entry
  -> Layer 1: Underlying location, state, permissions, fuel primitives complete validation and state updates
  -> Result written back to on-chain object, front-end refreshes
```

So when writing extensions, keep in mind to always distinguish:

- Which part is "my business rules"
- Which part is "behavior guaranteed by official components"
- Which part is "underlying world physics rules"

### Why is This Layering Important for Builders?

Because it directly determines where you should write your logic.

For example, if you want to make a "toll stargate":

- Fee rules and discount strategies: Write in your extension
- How the stargate jump itself executes: Handled by official components
- Location, permissions, state transitions involved in jumping: Handled by underlying primitives

If you mix these three things together, two common problems will occur:

- You reimplement rules in extensions that are already guaranteed at the bottom layer
- You think you can modify the official component core, but actually have no such authority

### What is Typed Witness?

Here's an intuitive understanding first, without diving into syntax details:

- You can't just tell an official stargate "use my function from now on"
- You must access through a **type identity marker** accepted by officials
- This type identity is the `Typed Witness` that will repeatedly appear later

You can roughly understand it as:

> "I'm not directly modifying official code, but holding a typed authorization badge to attach my extension logic to official components."

Later in [Chapter 30](./chapter-30.md) you'll see how it works specifically.

---

## 1.4 Why Choose the Sui Blockchain?

EVE Frontier's migration to Sui wasn't accidental, but a carefully considered technical choice.

### Sui's Core Advantages

| Feature | Traditional Blockchain | Sui |
|------|-----------|-----|
| **Asset Model** | Account balance model | Centered on **Objects**, each asset has unique ID and ownership history |
| **Concurrent Processing** | Serial execution | Independent objects can execute in parallel, extremely high throughput |
| **Transaction Latency** | Seconds to minutes | Sub-second finality |
| **Player Experience** | Need to manage mnemonic phrases | zkLogin: Login with Google/Twitch account |
| **Gas Fees** | User pays | Supports sponsored transactions, developers can pay |

### What Does the Object Model Mean?

On Sui, **every item, every character, every component** in the game is an independent on-chain object, with:
- Unique `ObjectID`
- Clear ownership (`owned by address` / `shared` / `owned by object`)
- Complete traceable operation history

This is especially important for game worlds, because many game objects are naturally suited to "independent entity" representation:

- A permit is an independent ticket
- A warehouse is an independent facility
- A treaty is an independent agreement
- A kill record is an independent battle report

When these things are all objects, you can naturally do:

- Transfer
- Authorization
- Query
- Composition
- History tracking

This is why EVE Frontier can make "facilities, permissions, transactions, events" into a programmable ecosystem, rather than a pile of database records that can only be consumed internally.

This makes decentralized ownership, trading, and game history archives naturally viable capabilities.

### Three Most Critical Object States

If this section isn't explained clearly, much of the content later will feel awkward.

| Object State | Meaning | Common Examples in EVE Frontier |
|------|------|------|
| `owned by address` | Object is directly owned by an address | NFTs in player wallets, certain credential objects |
| `shared` | Object can be accessed by anyone under rule satisfaction | Stargates, turrets, markets, shared vaults |
| `owned by object` | Object is held by another object | Capability objects held by characters, internal facility assets |

These three states determine almost all your later designs:

- How to write permissions
- How to assemble transactions
- How the front-end queries objects
- Whether parallel execution is possible

### Why is the Object Model Particularly Suitable for Space Games?

Because space games are naturally "many discrete objects interacting":

- Ships are objects
- Characters are objects
- Gates, turrets, storage units are objects
- Passes, policies, rental vouchers are also objects

Sui's object model means these things don't need to be forcibly stuffed into a centralized database table or a huge contract mapping. You can make each facility, each voucher, each relationship into independent objects, then through:

- Ownership relationships
- Shared access
- Events
- Dynamic fields

Organize them together.

### Why are Sponsored Tx and zkLogin Important for Game Experience?

The two most discouraging points for players in traditional on-chain applications are:

1. Need to learn about wallets, mnemonic phrases, Gas first
2. Must pay transaction fees yourself for every action

Sui's value in EVE Frontier isn't just "higher performance," but that it provides the foundational conditions for gradually introducing Web2 players to on-chain interactions:

- **zkLogin**: Lower wallet barriers
- **Sponsored Tx**: Lower transaction barriers
- **Low-latency object transactions**: Reduce interaction waiting time

These three points combined make "one click in-game completes on-chain action" a reality.

---

## 1.5 EVE Vault: Your Identity and Wallet

**EVE Vault** is the officially provided browser extension + Web wallet, serving as your digital identity as a Builder and player.

### Core Functions

- Store LUX, EVE Token, and in-game NFTs
- Create Sui wallet through **zkLogin** using EVE Frontier SSO account, **no need to manage mnemonic phrases**
- Serve as dApp connection protocol, authorizing third-party dApp access in-game and external browsers
- FusionAuth OAuth binds game character identity with wallet

### How is it Different from Regular Wallets?

Regular crypto wallets typically follow the mindset: "Have wallet first, then find applications."

EVE Vault is more like: "I'm first a user in EVE Frontier, then wallet capability naturally embeds into this identity system."

This means it simultaneously handles three things:

1. **Asset Container**
   Holds LUX, Tokens, NFTs, credentials
2. **Identity Bridge**
   Connects game account, SSO login, Sui address
3. **Interaction Authorizer**
   Provides dApps with connection, signing, sponsored transaction capabilities

### What Do You Need to Remember About zkLogin First?

Don't dive into cryptographic details right away—understanding these three points is enough:

- It allows users to enter on-chain systems using familiar login methods
- Behind it still falls to a wallet identity usable on Sui
- This isn't "no wallet," but "wallet creation and recovery experience is repackaged"

When you reach [Chapter 33](./chapter-33.md), dive into its proof structure and temporary key mechanism.

### Two Currencies

| Currency | Purpose |
|------|------|
| **LUX** | Main in-game transaction currency, used for purchases, services, fees, etc. |
| **EVE Token** | Ecosystem participation token, used for developer incentives, special asset purchases |

---

## 1.6 Programmable Economy: Builder's Business Possibilities

Review what real business logic Builders can implement:

```
💰 Economic Systems
  ├── Custom trading markets (auto-matching, bidding auctions)
  ├── Alliance tokens (Sui-based Fungible Tokens)
  └── Service fees (stargate tolls, storage rent)

🛡 Security & Permissions
  ├── Whitelist access control (which players can use your facilities)
  └── Conditional locks (only characters who complete quests can withdraw items)

🤖 Automation
  ├── Turret custom locking logic
  ├── Automatic item distribution (quest rewards, airdrops)
  └── Cross-facility linkage (facility A's behavior triggers facility B's response)

🏗 Infrastructure Services
  ├── Third-party dApps read on-chain state
  └── External API linkage (off-chain data triggers on-chain actions)
```

### What Does a Minimal Builder Business Closed Loop Look Like?

If you still find "what Builders actually do" a bit abstract, remember this minimal closed loop:

```text
I control a facility
  -> I define rules others must follow when using it
  -> Rules written on-chain
  -> Players use facility after paying/holding credentials/meeting conditions per rules
  -> Revenue, permissions, credentials, history records all stay on-chain
```

For example:

- Toll stargate: Charge per use
- Alliance warehouse: Place items by permissions
- Quest gate: Can only enter after completing assessment
- Auction box: Sell resources by price curve

The biggest difference from "making a regular game plugin" is:

- Rules are public
- State is verifiable
- Asset flows are traceable
- Other Builders can continue composing your rules

### After Finishing Chapter 1, You Should Be Able to Answer These 5 Questions

1. Why isn't EVE Frontier a regular MOD system?
2. What are Builder, Operator, and Player each responsible for?
3. Why is a Smart Assembly both a game facility and an on-chain object?
4. In the three-layer architecture, which layer do Builders actually work in?
5. Why is Sui's object model more suitable for this type of game than traditional account balance models?

---

## 🔖 Chapter Summary

| Learning Point | Core Concept |
|--------|--------|
| EVE Frontier's Positioning | Truly open programmable universe, Builders can rewrite game rules |
| Smart Assembly Types | Network Node / SSU / Turret / Gate |
| Three-Layer Architecture | Primitives → Assemblies → Player Extensions |
| Why Sui | Object model, concurrency, low latency, zkLogin frictionless experience |
| EVE Vault | Official wallet + identity system, based on zkLogin |

## 📚 Extended Reading

- [Why Build on EVE Frontier?](https://github.com/evefrontier/builder-documentation/blob/main/README.md)
- [Smart Infrastructure](https://github.com/evefrontier/builder-documentation/blob/main/welcome/smart-infrastructure.md)
- [EVE Frontier World Explainer](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/eve-frontier-world-explainer.md)
- [Sui Documentation: Object Model](https://docs.sui.io/concepts/object-ownership)
