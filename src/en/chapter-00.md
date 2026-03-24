# Prelude: Understanding EVE Frontier as a Game First

> **Objective:** Before diving into contracts, components, and dApps, first understand what players in EVE Frontier are competing for, building, and why these mechanics are naturally suited to become on-chain rules.

---

> Status: Introductory chapter. Focus is on establishing "gameplay intuition" first, so that Gate, Turret, StorageUnit, KillMail, and LocationProof won't feel like abstract nouns in later chapters.

## 0.1 This Is Not a "Wallet Game with Blockchain Attached"

If you start thinking of EVE Frontier as "a space game with NFTs and tokens," you'll likely find things increasingly awkward as you learn more. Because the true core of this game isn't about issuing assets—it's **a persistent, resource-competitive, geographically-constrained, player-conflict-driven open world**.

It's closer to this combination:

| Dimension | What EVE Frontier is More Like | Why This Matters |
|------|------------------|--------------|
| World Structure | A persistent space sandbox | The world doesn't pause when you log off; facilities, routes, control zones, and economic relationships continue changing |
| Survival Pressure | Starts from "staying alive", not "daily check-in rewards" | Resources, fuel, transport, security, and location are real problems |
| Player Relationships | Long-term cooperation and conflict coexist | You'll need alliances, supply chains, corridors, defense, diplomacy, and retaliation |
| Building Significance | Buildings are infrastructure that changes gameplay, not decoration | Stargates, turrets, storage facilities directly affect who can pass, who can access cargo, and who gets attacked |
| Blockchain's Role | Public rules layer and asset layer | The focus isn't moving all gameplay on-chain, but making the parts worth public verification into programmable rules |

So you can start by remembering this:

> The "unit of fun" in EVE Frontier isn't a single NFT, but the long-term strategic interplay between player groups around infrastructure, resource flows, and territorial control.

## 0.2 What Does a Typical Player Actually Do in This World?

From a gameplay perspective, player activities usually revolve around this main loop:

```text
Enter the world
  -> Establish character and identity
  -> Find a safe foothold
  -> Acquire resources, items, and fuel
  -> Build your own base or connect to others' facilities
  -> Transport, trade, charge fees, defend, or raid
  -> Lose, recover, rebuild, and upgrade through conflicts
```

This isn't a linear quest chain, but a repeating cycle of operation and conflict. Players may focus on different playstyles:

- **Survival-focused players**: Prioritize supply, safety, and sustainable presence
- **Industrial players**: Focus on storage, logistics, item circulation, and markets
- **Military players**: Care about turrets, defensive lines, friend-or-foe identification, KillMail, and combat losses
- **Operator players**: Focus on toll gates, permission systems, alliance collaboration, and service pricing
- **Builder/Operator players**: Focus on turning infrastructure into fee-charging, filtering, incentivizing, and auto-executing rule systems

This book targets the last type, but what you design ultimately serves the first four types, so you must first understand what problems they actually encounter in the game.

### From a Player's Perspective, What Does a Typical Day Look Like?

If we compress gameplay into a more concrete daily loop, many actions happen like this:

```text
Log in
  -> Check current location and base status
  -> Verify fuel, inventory, access permissions, nearby risks
  -> Decide whether to mine, transport, trade, defend, or attack today
  -> Use Gate, Storage, market, or alliance facilities to achieve goals
  -> May encounter interception, tolls, turret checks, or PvP en route
  -> Successfully bring back gains, or regroup resources after losses
```

In this daily loop, almost every step can be influenced by Builders:

- "Can I safely go out" encounters `Gate`
- "Check inventory and supplies" encounters `Storage Unit`
- "Is my base still operational" encounters `Network Node / Energy / Fuel`
- "Will I get intercepted on the route" encounters `Turret` and regional governance
- "Can losses from losing fights be tracked" encounters `KillMail`
- "Is someone actually physically present" encounters `LocationProof`

In other words, Builders aren't just making extra web pages—they're integrating into decision points players encounter daily.

### What Do Players Really Weigh Repeatedly in This World?

From a gameplay perspective, many choices in EVE Frontier ultimately come down to these 4 trade-offs:

| What Players Weigh | Typical Questions |
|----------------|--------|
| **Profit vs Risk** | This route earns more, but is it more vulnerable to attack? |
| **Convenience vs Control** | Letting everyone use my facility earns more, but will I lose filtering power? |
| **Liquidity vs Security** | Goods in public nodes are easier to sell, but more prone to issues? |
| **Short-term Gain vs Long-term Order** | Charging high tolls today feels great, but will it drive everyone away and cause route decline? |

This is also why many rules you'll see later don't look like "button features" but more like institutional design. Fees, permissions, whitelists, insurance, deposits, payouts, and rewards are essentially tuning these contradictions.

### The Same World Looks Completely Different to Different Players

If you want to build truly useful Builder products, you must realize: the same gate, turret, or warehouse has completely different value to different people.

| Perspective | What They See First | What They Really Care About |
|------|----------------|----------------|
| **New players** | Is it safe, will I get lost, will I die immediately upon leaving | Surviving, avoiding mistakes, not getting scammed, knowing what to do next |
| **Merchants / Logistics players** | Route stability, warehouse usability, predictable fees | Cost, timeliness, wastage, inventory safety |
| **Pirates / Raider players** | Which routes have people, cargo, and vulnerabilities | Interception profit, ambush efficiency, target screening, escape cost |
| **Alliance operators** | Which nodes must be defended, which routes must be open, which facilities are worth long-term investment | Regional order, taxation, logistics resilience, defensive zone stability |
| **Builder / Operators** | Which nodes can become rule entry points, toll points, data entry points | Rule enforceability, operating costs, user conversion, long-term reusability |

This table is important because it explains why the same facility generates different demands:

- Newcomers want gates with "fewer restrictions"
- Operators want gates with "stronger screening and governance capabilities"
- Merchants want gates with "transparent pricing, stable passage"
- Pirates want gates that "create congestion and exposure"

A Builder's job isn't to satisfy just one party, but to consciously decide which side your product stands with.

### Viewing the Same Base Through Five Typical Identities

Suppose there's a base built on a route node with `Network Node + Gate + Turret + Storage Unit`. Different people think completely differently when entering:

#### 1. Newcomer

When a newcomer enters this base, their first reaction usually isn't "how elegant this rule system is," but:

- Will I get attacked
- Do I need to pay to pass through the gate
- Will my stuff be lost if I store it here
- Can I understand what this system is asking me to do

For newcomers, a good Builder system often has these characteristics:

- Clear rules
- Low failure cost
- Few erroneous operations
- Clearly explain "why you were rejected"

So many things you think are "UX copy" are actually part of gameplay retention.

#### 2. Merchant / Logistics Player

Merchants won't first look at whether this base is "cool"—they calculate:

- How much time does passing through this Gate save versus detouring
- Are tolls stable
- Can the Storage Unit safely store cargo temporarily
- Can turrets ensure basic safety for high-value cargo transport

If a base makes merchants form the expectation that "although expensive, it's stable and reliable," it might gradually become a trading node. For merchants, **predictability itself is product value**.

#### 3. Pirate / Raider

Pirates see not services, but vulnerabilities and traffic:

- Is this route a must-pass
- Does the gate entrance create queues and slowdowns
- Which players will linger because of paying, opening boxes, or trading
- Can turrets be circumvented, baited, or exploited

This perspective forces Builders to rethink security issues. Many systems aren't just "as long as the function runs"—you must ask:

- Will it create fixed ambush points
- Will it expose high-value users
- Will it allow certain playstyles to become overly stable farming machines

#### 4. Alliance Operator

Alliance operators look at sustained order:

- Is this base worth long-term defense
- Are power and maintenance costs manageable
- Can gate access rules distinguish allies, visitors, and hostiles
- Can KillMail and passage data help judge defense zone quality

For them, facilities aren't one-time interaction tools but part of territorial institutions. If Builders only provide one-off functions without sustained operational perspective, products will struggle to enter these players' long-term workflows.

#### 5. Builder / Operator

Builders and Operators usually see things more "institutionally":

- Can this ruleset scale
- Which parts should be on-chain, which parts off-chain
- Is there a way to reduce customer service explanation costs
- Can it accumulate data, build reputation, create reusable templates

This perspective views a base as a replicable business model, not a collection of scattered functions.

## 0.3 What Are the Most Critical "Game Objects" in This World?

### Character

Character is your **core identity** in the game. You can think of it as "you in the game," but in EVE Frontier, it also assumes a very special responsibility: **it's the central hub for on-chain permissions and asset control**.

Characters have at least three layers of meaning:

1. It's the character identity in the game
2. It's the on-chain `Character` object
3. It's also the "keychain" holding many `OwnerCap`s

Later when you learn about `OwnerCap`, `Receiving`, and `borrow-use-return`, if you don't first know that characters in gameplay are "the carrier of player control," you'll easily find the whole design overly convoluted.

### Tribe

Tribes can initially be understood as the character's initial affiliation or identity tag. It doesn't necessarily equal permanent political faction, but it's often used for:

- Newbie protection
- Gate access conditions
- Passage permissions
- Faction identification
- Gameplay segmentation

So when you later see "only allow certain tribe through stargate" or "determine turret attitude by tribe," don't treat it as just a random `u32` field—in gameplay it carries identity classification.

### Items

Items are resources, equipment, loot, keys, licenses, and economic carriers in the game. What's most important in gameplay isn't whether "it's an NFT," but whether it can participate in these actions:

- Be carried by characters
- Be deposited in storage facilities
- Be traded, rented, collateralized, synthesized, destroyed
- Become loot or loss upon player death
- Become a ticket, deposit, or consumable for certain services

This is also why `StorageUnit` is so important in EVE Frontier. You're not simply making an on-chain warehouse but controlling "how items flow" in the game.

### Bases and Facilities (Assemblies)

Players don't just survive on wallets and characters—they build facility networks around spatial locations. Facilities are true gameplay amplifiers because they turn "one player's action" into "one region's rules."

### What Roles Do High-Frequency Terms Actually Play?

The table below tries to explain terms you'll frequently see using "gameplay language" rather than "source code language":

| Term | What It Is in the World | Role It Plays |
|------|--------------|------------|
| `Character` | Player's on-chain character identity | Starting point for many permissions, facility control rights, and interaction qualifications |
| `Wallet` / EVE Vault | Player's wallet and identity container for initiating on-chain actions | Responsible for signing, holding coins, connecting dApps, but not equal to complete game identity |
| `Tribe` | Identity classification the character belongs to | Often used for faction, whitelist, passage, and newbie protection logic |
| `Item` | Resources, equipment, licenses, loot, etc. | Foundation material for logistics, trading, insurance, rental, and reward systems |
| `Assembly` | Facility objects players deploy in the universe | Amplifies individual behavior into regional rules, the actual landing node for gameplay |
| `Network Node` | Base power core | Determines whether a base can carry more facilities, prerequisite for "can it operate" |
| `Energy` | Power capacity / quota | Determines how many facilities a base can have online simultaneously |
| `Fuel` | Continuously consumed operational resource | Determines how long facilities can stay online, operational cost |
| `Gate` | Space passage and jump entrance | Affects routes, fees, access control, and regional traffic |
| `JumpPermit` | One-time or time-limited passage license | Makes "can pass through gate" into explicit rules and assets |
| `Turret` | Automatic defense facility | Responsible for screening and punishing targets approaching certain areas |
| `Storage Unit` | Warehousing and item circulation node | Foundation for markets, consignment, rental, prize pools, loot management |
| `Location` | Spatial position expression of an object in the world | Makes "where this thing is" into state referenceable by rules |
| `LocationProof` | Server-issued certificate proving "you're actually present" | Brings offline spatial facts on-chain, avoiding remote abuse |
| `KillMail` | Public record of a kill or combat loss | Makes conflicts and losses into indexable, rewardable, statistical facts |
| `OwnerCap` | Control credential for an object | Determines who's qualified to configure and manage certain facilities or key objects |
| `AdminACL` | Server authorization whitelist | Allows only trusted backends to write certain high-permission world states |
| `Extension` | Extended logic Builder writes for facilities | Determines how facilities charge, grant access, screen, consume, and respond |

If you want to remember these terms more deeply, use a simpler classification:

- `Character / Wallet / Tribe`
  This group solves "who you are"
- `Item / Storage Unit / Logistics`
  This group solves "how things flow"
- `Gate / Turret / Location`
  This group solves "who can enter, who can stay, who gets attacked"
- `Network Node / Energy / Fuel`
  This group solves "can facilities continue operating"
- `KillMail / LocationProof / AdminACL`
  This group solves "which facts are worth public verification"
- `OwnerCap / Extension`
  This group solves "who has authority to change rules, how rules get attached"

### Looking Deeper, What Problems Does Each Term Actually Solve for the World?

If you only memorize "definitions," these terms still scatter easily. A more useful approach is: what long-term problems does each solve for this world?

| Term | The Real Problem It Solves for the World |
|------|--------------------|
| `Character` | Centralizes "who the player is and what they can control" to a stable identity node |
| `Wallet` / EVE Vault | Reduces Web2 login, signing, and on-chain interaction friction, allowing more players to enter the rule system |
| `Tribe` | Provides the most basic layer of social grouping, giving access control, protection, and screening natural handles |
| `Gate` | Makes paths no longer naturally given, but governable, fee-chargeable, and institutionalizable |
| `JumpPermit` | Turns "allowed to pass" from verbal rules into verifiable, time-expirable credentials |
| `Turret` | Gives regional rules automatic enforcement consequences, not just UI prompts |
| `Storage Unit` | Makes item control and circulation order stably orchestrable |
| `Network Node` | Makes base expansion face capacity and power realities, not unlimited facility stacking |
| `Energy` | Makes "how many facilities can be mounted" a clear resource constraint |
| `Fuel` | Gives facility operation sustained cost, forcing management and resupply to happen |
| `LocationProof` | Makes "must be physically present" rule-verifiable |
| `KillMail` | Makes combat losses, kills, and war results leave publicly verifiable traces |
| `OwnerCap` | Makes "object control" not just an address field, but a borrowable, constrainable capability object |
| `AdminACL` | Lets the world recognize certain off-chain backend inputs, without fully opening high permissions to everyone |
| `Extension` | Lets Builders change rules without directly rewriting world kernel |

When designing a new product later, you can ask in reverse:

- Are you solving a "path problem" or "permission problem"?
- An "item circulation problem" or "presence verification problem"?
- A "regional consequence enforcement problem" or "combat loss recording problem"?

This way you'll more easily find which World capabilities to interface with, rather than randomly piling modules.

### Why Do Many Beginners Mix Up These Terms?

Because these terms all look like "on-chain concepts," but they actually come from different layers:

| Layer | Typical Terms | What Questions They Answer |
|------|------|----------------|
| **Identity Layer** | `Character`, `Wallet`, `Tribe` | Who's acting? Whose character? |
| **Asset Layer** | `Item`, `Storage Unit`, `KillMail` | What things are being held, lost, transferred, recorded? |
| **Spatial Layer** | `Gate`, `Turret`, `Location` | Where can you go, where can you stay, will you be attacked? |
| **Operational Layer** | `Network Node`, `Energy`, `Fuel` | Can facilities stay online continuously? |
| **Permission Layer** | `OwnerCap`, `AdminACL`, `Extension` | Who can configure, who can modify, who can represent server writes? |

As long as you separate these layers first, many concepts won't pile up together later.

### Another Set of Easily Confused Terms

These terms are often mentioned together, but they're actually not the same:

| Easily Confused Terms | Real Difference |
|------------|--------|
| `Character` vs `Wallet` | `Wallet` handles signing and holding on-chain assets, `Character` is more like game identity and control hub |
| `Gate` vs `JumpPermit` | `Gate` is the infrastructure itself, `JumpPermit` is a credential allowing you to pass through it |
| `Energy` vs `Fuel` | `Energy` is capacity quota, `Fuel` is continuously consumed resource |
| `Storage Unit` vs `Item` | Former is circulation container and rule entry point, latter is the object being moved, traded, locked |
| `OwnerCap` vs `AdminACL` | Former leans toward object-level control, latter toward server-level high-permission whitelist |
| `Location` vs `LocationProof` | Former is position state, latter is proof that "you indeed currently meet certain location conditions" |
| `KillMail` vs Event logs | `KillMail` is an indexable and reusable combat loss fact object, not just one-time broadcast message |

## 0.4 Why Are Smart Assemblies the Gameplay Core?

One of EVE Frontier's most special features is making infrastructure into player-ownable, configurable, extensible Smart Assemblies.

You can first understand them as "service nodes in space":

| Facility | Role in Game | Significance to Builder |
|------|------------|-----------------|
| `Network Node` | Base power core, facility networking starting point | Determines which facilities can come online, affects entire base capacity ceiling |
| `Gate` | Controls passage, jumps, routes | Can do tolls, whitelists, tickets, quest gates, alliance-exclusive routes |
| `Turret` | Defense and automatic attacks | Can do defense zone rules, threat screening, automatic security |
| `Storage Unit` | Warehousing and item circulation | Can do stores, rental, consignment, prize pools, quest delivery points |

The value of these facilities isn't that "they're on-chain objects," but that they directly control players' most real needs:

- Can I pass through here?
- Can I safely store cargo here?
- Will I be shot by the turrets here?
- Can I buy, rent, or deliver certain items here?

Once a facility controls these entry points, it naturally becomes an economic node, strategic node, or political node.

## 0.5 Why Can't Bases Avoid Network Node, Energy, and Fuel?

Many people first encountering EVE Frontier instinctively think of facilities as "on-chain objects you can use once placed." Actually not. Facilities in gameplay have survival costs and operational conditions.

A minimal base roughly looks like this:

```text
First find an anchorable location
  -> Establish Network Node
  -> Refuel the node and bring it online
  -> Connect Gate / Turret / Storage Unit
  -> These facilities reserve Energy from the network node
  -> They rely on Fuel and online status to continue operating
```

Here there are at least three completely different constraints:

1. **Geographic constraint**: You must first have a foothold in space
2. **Capacity constraint**: How much Energy the node can provide determines how many facilities you can mount
3. **Consumption constraint**: Fuel burns over time, facilities aren't permanently cost-free online

This means "why can't I use my gate" in gameplay could be three completely different problems:

- This gate isn't connected to an available node at all
- Node capacity is insufficient, Energy is occupied by other facilities
- Fuel burned out, building entered offline state

This is also why the later `Energy` / `Fuel` chapters aren't just technical details. They directly determine whether a base is a truly operable, fee-chargeable, sustainable system.

### Why Does a Base Naturally Grow Into a "Service Network"?

Many people think bases are just "placing several buildings together." But in EVE Frontier, a mature base is more like a small institutional system:

- `Network Node` provides underlying power capability
- `Gate` determines who can enter, exit, detour, or pay
- `Turret` determines safety consequences for those approaching
- `Storage Unit` determines how cargo, supplies, and deposits are managed

Once these 4 types of facilities combine, bases no longer just become footholds but gradually evolve into:

- Toll outposts
- Alliance defense zones
- Logistics transit stations
- Border trading ports
- War supply nodes

So what Builders actually write is often not individual functions, but rule networks for "how a certain region should operate."

### What "Secondary Gameplay" Usually Emerges Once a Base Matures?

Initially bases are just tools for survival, but once stabilized, many secondary gameplays emerge:

- **Fee gameplay**
  Like passage fees, storage fees, agent fees, rush fees
- **Screening gameplay**
  Like whitelists, memberships, tribe-exclusives, post-quest access
- **Security gameplay**
  Like gate entrance turret linkage, critical cargo warehouse defense zones, danger list auto-identification
- **Financial gameplay**
  Like deposits, insurance, rental, payouts, bounties
- **Social / Political gameplay**
  Like alliance-exclusive corridors, diplomatic treaties, regional joint defense, war zone access systems

This is also why a base that's "just gates and turrets" eventually becomes something like a hybrid of port, checkpoint, market, and border station.

## 0.6 Why Are Stargates, Location, and Spatial Control So Important?

EVE Frontier is a strongly spatial world. You're not just "clicking a button to go to a page," but moving in a universe with distance, paths, and risk exposure.

### What Does Gate Mean in Gameplay?

The essence of `Gate` isn't teleportation effects, but a **passage rights controller**. Who can pass, when they can pass, how much they pay, whether they meet certain conditions—all affect player behavior paths.

So a stargate can naturally evolve into many gameplay forms:

- Toll stations
- Whitelist corridors
- Reward entrance after quest completion
- Alliance-exclusive routes
- Risk zone customs

More specifically, Gates in gameplay control at least 4 things simultaneously:

1. **Path choice**
   Whether players are willing to take this route depends on whether it's fast, stable, and cheap.
2. **Access qualification**
   Who can pass, who must first meet conditions, who gets rejected.
3. **Passage cost**
   Can this become a fee node, monthly card node, alliance privilege node.
4. **Regional rhythm**
   Once a gate is fee-charged, blockaded, or militarized, surrounding logistics and conflict distribution change.

So Gates are never "a jump button," but transportation institutions.

### Why Are Gates Often the First Commercialized Facility?

Because Gates naturally sit on "must-pass paths." Whoever controls paths controls three particularly monetizable capabilities:

1. **Fee capability**
   Tolls, membership fees, temporary license fees all come naturally.
2. **Screening capability**
   Who can enter, who can't directly affects regional population and cargo flow.
3. **Traffic capability**
   Players lingering at gates means surrounding storage, shops, and quest points can be activated.

So many Builders' first truly decent commercial product starts from Gates, not from more abstract Token models.

### Why Do We Need Location Proofs?

Because many actions aren't "as long as you own a certain wallet address you can do it," but "only if you've actually arrived on site." For example:

- You must be near a certain gate to pass through
- You must be near a certain treasure chest to open it
- You must be near a certain market node to trade on-site

On-chain contracts can't know your real-time coordinates in the game world themselves, so the game server needs to issue proof that "you're near a certain object," then the chain verifies it. This is the gameplay background for why `LocationProof` and proximity systems exist later.

You can also understand location proof as "making geographic presence a ticket condition." Without it, many gameplays that should depend on on-site presence will degrade into remote script operations:

- Remote gate opening
- Remote chest opening
- Remote trading
- Remote submission of tasks that should be completed on-site

Once these can all be done remotely, space loses meaning, and the strategic value of bases and routes declines together.

## 0.7 How Do Turrets, Defense Lines, and "Regional Order" Come About?

If Gates solve "who can pass," then `Turret` solves "who approaching gets shot."

Turrets in gameplay aren't simply damage devices but part of regional order. They turn a space from "anyone can come" into "better consider consequences before coming." This directly changes:

- Friend-or-foe identification
- Newbie protection
- Base defense
- Corridor deterrence
- Logistics safety costs

By default turrets only provide basic defense logic, but after Builder intervention, turrets can become more complex strategic facilities:

- Prioritize attacking active aggressors
- Spare whitelists or specific tribes
- Escalate threats for high-risk targets
- Work with gates and fees to govern entire regions

So don't only view turrets as combat modules. They're essentially spatial governance modules.

In mature regional gameplay, turrets often work together with other facilities:

- `Gate + Turret`
  Forms fee-charging border ports with enforcement power
- `Storage Unit + Turret`
  Forms defense system for high-value material nodes
- `LocationProof + Turret`
  Forms regional rules where "only on-site and condition-meeting people can safely operate"

In other words, turrets aren't just damage output but "consequence machines when rules aren't followed."

### Why Do Turrets Directly Change Economics?

Because safety is never a free environmental variable but part of transaction costs. As long as turrets exist, these things change:

- Whether cargo players are willing to take certain routes
- Whether high-value cargo dares to temporarily store at certain nodes
- Whether fees in certain regions can be enforced
- Whether pirate interception costs rise

So turrets aren't just "things military players care about." They actually affect decisions of merchants, operators, and ordinary passing players.

## 0.8 Death, Loot, KillMail, and "Visibility of Losses"

EVE-style gameplay has a fundamental difference from many lightweight blockchain games: **losses aren't abstract numerical drops, but real asset, location, and opportunity losses**.

A PvP or wrong navigation can bring these results:

- Ships or facilities destroyed
- Items lost
- Loot picked up by others
- Certain transport line forced to interrupt
- Opponent obtains a public KillMail record

KillMail's significance isn't just "making a combat rankings look good." It has at least 4 roles in gameplay:

1. Makes losses publicly verifiable
2. Makes combat history part of economic and reputation systems
3. Lets Builders design rewards, insurance, bounties, leaderboards around kill records
4. Makes conflicts in the world leave lasting traces

This is also why you'll later see designs around `KillMail` for insurance, bounties, achievements, and statistics. Because it's not marginal logs but part of war narratives.

If we speak more directly, KillMail makes many things in this world institutionalizable for the first time:

- "Is this loss real" can be verified
- "Is this person recently a high-risk target" can be statistically tracked
- "Should insurance pay out" doesn't rely on hearsay
- "Is this alliance defending routes" can be indirectly reflected through combat records

So it's not simply combat reports but public baseline for warfare, insurance, reputation, and bounty systems.

### Why Does "Death Has Records" Profoundly Change Player Behavior?

Because once losses leave public traces, player behavior no longer just short-term results but also affects long-term reputation and institutional evaluation:

- Operators care more about route safety
- Insurers care more about whether payout conditions are real
- Bounty systems can more precisely identify targets
- Players care more about which places are prone to incidents

KillMail makes "what happened in this world" no longer just exist in chat records and memories, but enter the statistically composable rules layer.

## 0.9 Why Do Storage, Logistics, and Trading Become an Entire Economy?

In EVE Frontier, items aren't "done once in backpack." What's truly valuable is **how items are stored, transported, exchanged, and permission-accessed**.

An item from production to consumption may go through many stages:

```text
Player obtains item
  -> Temporarily carry
  -> Deposit in Storage Unit
  -> Listed for sale / as deposit / as rental target
  -> Purchased, rented, redeemed, or consumed by other players
  -> Recirculated in war, transport, or death
```

Thus storage facilities no longer just warehouses but naturally evolve into:

- Stores
- Vending machines
- Consignment points
- Shared warehouses
- Reward pools
- Loot recovery points
- Inter-alliance material exchange interfaces

From a gameplay perspective, where Builders most easily create value is often not "issuing a new Token," but making existing item circulation paths smoother, safer, more rule-bound.

This is also why `Storage Unit` is often the most underestimated facility. Many product innovations look like markets, rentals, insurance, loot boxes, or quest systems on the surface, but underneath are answering one question:

> When can certain items be taken by whom, put in, locked, released, transferred, destroyed, or redeemed?

Whoever controls this process controls a considerable portion of the game economy.

### Why Is Storage Unit Often the "Behind-the-Scenes Star" of All Gameplay?

Because many systems ultimately come down to "where things are placed, who can take them, when to release":

- Markets must solve settlement
- Rentals must solve temporary transfer and expiry recovery
- Reward pools must solve conditional release
- Insurance must solve payout material or fund distribution
- Quest systems must solve delivery and pickup item sequence

So although `Storage Unit` doesn't look as conspicuous as Gate on the surface, it's often the facility closest to the economic base.

## 0.10 In the Economic System, What Roles Do SUI and LUX Play?

In this book's context, you can first make a sufficiently practical understanding:

- **SUI** is more like underlying on-chain fuel and general settlement asset
- **LUX** is more like assets closer to game services and daily economic interactions

Many Builder products will design around these actions in gameplay:

- Passage fees
- Service fees
- Deposits
- Rental settlement
- Insurance premiums and payouts
- Reward distribution

What's truly important isn't "which Coin is more advanced," but whether your designed fee model fits gameplay. For example:

- High-frequency small-amount services care more about low friction
- Risk scenarios need more deposits and breach penalties
- Long-term relationships suit subscriptions, memberships, license models better
- War-related products value payouts, guarantees, and reputation more

So economic design is never an independent chapter. It's always embedded in gameplay like passage, defense, warehousing, logistics, and diplomacy.

## 0.11 Which Things Are On-Chain, Which Things Still on Game Server?

The most critical point to understanding EVE Frontier is not to mix "open world game" and "on-chain contracts" into one system.

| Better Suited for Game Server Processing | Better Suited for On-Chain Processing |
|----------------------|------------------|
| Real-time position, physics simulation, combat process | Asset ownership, permission objects, license rules, fee settlement |
| High-frequency state refresh, instant judgments | Verifiable records, long-term state, open composition interfaces |
| In-game coordinates and real-time observation | KillMail, OwnerCap, JumpPermit, configuration objects |

Both sides are collaborative, not replacement relationships.

You can understand it as:

- **Game server** handles "what's happening in the world"
- **Blockchain** handles "which rules and results need to be public, persistent, composably established"

Precisely because of this, what Builders write is more like "rule infrastructure," not taking over the entire game engine.

If this layer of division is misunderstood, two common misconceptions will arise later:

- One misconception is "why not move all real-time gameplay on-chain"
  Real-time physics and high-frequency judgments aren't suitable to be directly made into public chain state
- Another misconception is "since the server knows, why put it on-chain"
  Because permissions, assets, licenses, payouts, public records—these things precisely need public verification

EVE Frontier's special feature isn't extremely choosing only one side, but piecing together the parts each side excels at into a stronger system.

### As a Builder, 10 Types of Gameplay Entry Points Most Worth Observing First

If you want to transition from "knowing the worldview" to "knowing what to do," the most worthwhile first observations are these entry points:

1. Who has natural traffic on a certain route.
2. Which locations require players to physically be present.
3. Which items are frequently deposited, withdrawn, traded, bet on, or consumed.
4. Which rules need automatic enforcement, not just verbal agreements.
5. Which losses need public records to support subsequent payouts or statistics.
6. Which regions already have stable but inefficient fee or screening demand.
7. Which services can't scale because they need manual trust.
8. Which alliances or groups need to long-term maintain their own order and boundaries.
9. Which players abandon certain trades or collaborations due to excessive operational costs.
10. Which places, once rules are standardized, can be replicated to many bases and routes.

These 10 types of entry points are essentially where Builders most easily discover real needs.

## 0.12 What Can Developers (Builders) Do in This World?

After understanding players' game loops, as a developer (Builder), you can leverage Sui smart contracts and EVE Frontier's open interfaces to excel in four core directions:

### 1. Write Smart Component Extensions

In-game stargates (Gate), turrets (Turret), and storage boxes (Storage Unit) only have the most basic operational logic by default. Builders can write Move contracts to turn these facilities into complex business rule engines:
- **Stargate toll stations**: Charge per use, provide monthly card subscriptions, or charge high "tolls" for hostile alliances.
- **Smart fire control networks**: Let turrets identify "wanted criminals with bounties" or "passersby who haven't paid protection fees" and automatically fire.
- **Automated logistics boxes**: Players deposit ore objects, contract automatically settles LUX tokens at current market rate.

### 2. Build Decentralized Applications & Interfaces (dApps & UI)

With on-chain rules, players need convenient user interfaces to interact. You can develop using EVE Vault (player digital identity plugin) combined with frontend and dApp Kit:
- **Ticket sales hall**: A webpage for players to purchase "Jump Permits" online.
- **Alliance finance dashboard**: Shows shared treasury real-time balance, daily tax revenue, and loot distribution records.
- **In-game embedded overlay**: Web UI that pops up directly in-game, letting players complete interactions and signing without leaving the client.

### 3. Design Advanced Deep Space Finance & Economic Models (DeFi)

Since all items (ships, weapons, resources) can be mapped on-chain as unique Objects, EVE Frontier naturally suits breeding hardcore financial protocols:
- **Combat loss insurance contracts**: Verify exact combat losses based on kill logs (KillMail), automatically payout to exploded ship players.
- **Decentralized rental protocols**: Mechanisms with great player safety to temporarily borrow premium firepower equipment (like turrets), automatically forfeit deposit or revoke control if not returned on time.
- **Futures & options markets**: Combine major corporation war zone resource output rates to establish large-depth trading pools (like DeepBook integration) to lock mineral prices.

### 4. Data Intelligence & Intelligence Networks (Data & Intel Indexing)

Every on-chain event broadcasts real-time changes in the game world. Builders can use indexers or backend monitoring to build ecosystem intelligence tools:
- **Interstellar warfare heat maps**: By aggregating network-wide jump permit records and `KillMail` data, real-time prompt which star systems are erupting in warfare, becoming frontline high-risk areas.
- **Network-wide bounty hunter red name list**: Record each player's malicious breach, hostile kill behavior and other on-chain footprints, letting mercenary alliances form quantifiable reputation ratings.

In short, ordinary players are **experiencing** this digital universe's cruelty and grandeur, while Builders are directly **writing** and **distributing** this universe's fundamental operating laws.

## 0.13 Using a Complete Scenario to String These Concepts Together

Suppose a Builder team operates a outpost base on an important route:

1. They first establish `Network Node`, giving the entire base power capability.
2. Then deploy a `Gate`, turning this route into a fee-chargeable corridor.
3. Deploy `Turret` near the gate to prevent hostile players from freeloading or harassing.
4. Add a `Storage Unit`, letting passing players buy supplies, store materials, pay deposits.
5. To avoid anyone passing through the gate, they write an extension for Gate:
   - Whitelist alliance members pass free
   - Ordinary players pay tolls
   - High-risk area players must hold temporary permits
6. To handle "only allowing trades if person is on-site" gameplay, they require market operations to attach location proof.
7. If nearby kills occur, KillMail gets indexed and used to give combat rewards to security alliances.

You'll find this already strings together most major themes of the entire book:

- `Character` and permissions
- `Gate / Turret / StorageUnit`
- `Energy / Fuel`
- `LocationProof`
- `KillMail`
- Fees, licenses, insurance, rewards
- dApp display and off-chain indexing

So each chapter later isn't actually about "an abstract technical point," but dissecting certain types of real gameplay needs in this world.

## 0.14 After Reading This Chapter, What Should You Bring Into Subsequent Chapters?

If this chapter has established these intuitions for you, later content will go much smoother:

1. EVE Frontier's core isn't issuing assets but operating infrastructure and rule entry points.
2. Facilities are gameplay nodes, not decorations.
3. Location, passage, warehousing, defense, combat losses, and economics are interconnected.
4. Game server and on-chain contracts have clear division of labor but collaborate on key rules.
5. Builders write not "plugin features" but rule systems that may long-term embed into world order.

Next recommend entering in this order:

- [Chapter 1: EVE Frontier Macro Architecture](./chapter-01.md)
- [Chapter 2: Development Environment Setup](./chapter-02.md)
- [Chapter 3: Move Contract Basics](./chapter-03.md)

When you read further into these chapters later, you can always come back to this one:

- [Chapter 16: Location and Proximity Systems](./chapter-16.md)
- [Chapter 32: KillMail System](./chapter-32.md)
- [Chapter 29: Energy and Fuel Systems](./chapter-29.md)
- [Chapter 30: Extension Pattern Practice](./chapter-30.md)
- [Chapter 31: Turret AI Extensions](./chapter-31.md)
- [Chapter 26: Complete Access Control Analysis](./chapter-26.md)
