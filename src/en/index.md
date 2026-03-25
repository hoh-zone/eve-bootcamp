# EVE Frontier Builder Complete Course

> Approximately **2 hours** per lesson, **54 lessons** total: 36 foundational chapters + 18 practical examples = **108 hours** of complete learning content.

---

## 📖 Chapter Roadmap (Recommended Learning Order, ~2 hours per lesson)

### Prerequisite

| Chapter | File | Summary |
|------|------|--------|
| Prelude | [chapter-00.md](./chapter-00.md) | Understand EVE Frontier first: What players compete for, why structures matter, how location/combat/logistics/economy form complete gameplay |

### Phase 1: Getting Started (Chapter 1-5)

| Chapter | File | Summary |
|------|------|--------|
| Chapter 1  | [chapter-01.md](./chapter-01.md) | EVE Frontier architecture overview: Three-layer model, smart component types, Sui/Move selection |
| Chapter 2  | [chapter-02.md](./chapter-02.md) | Development environment setup: Sui CLI, EVE Vault, test asset acquisition and minimal validation |
| Chapter 3  | [chapter-03.md](./chapter-03.md) | Move contract basics: Modules, Abilities, object ownership, Capability/Witness/Hot Potato |
| Chapter 4  | [chapter-04.md](./chapter-04.md) | Smart component development and on-chain deployment: Characters, network nodes, complete turret/stargate/storage unit modification workflow |
| Chapter 5  | [chapter-05.md](./chapter-05.md) | dApp frontend development: dapp-kit SDK, React Hooks, wallet integration, on-chain transactions |

Companion examples: [Example 1](./example-01.md) Turret whitelist, [Example 2](./example-02.md) Stargate toll booth

### Phase 2: Builder Engineering Loop (Chapter 6-10)

| Chapter | File | Summary |
|------|------|--------|
| Chapter 6 | [chapter-06.md](./chapter-06.md) | Builder Scaffold entry point: Project structure, smart_gate architecture, compilation and publishing |
| Chapter 7 | [chapter-07.md](./chapter-07.md) | TS scripts and frontend: helper.ts, script workflows, React dApp templates |
| Chapter 8 | [chapter-08.md](./chapter-08.md) | Server-side coordination: Sponsored Tx, AdminACL, on-chain and off-chain collaboration |
| Chapter 9 | [chapter-09.md](./chapter-09.md) | Data retrieval: GraphQL, event subscriptions, indexer approaches |
| Chapter 10 | [chapter-10.md](./chapter-10.md) | dApp wallet integration: useConnection, sponsored transactions, Epoch handling |

Companion examples: [Example 4](./example-04.md) Quest unlocking system, [Example 11](./example-11.md) Item rental system

### Phase 3: Advanced Contract Design (Chapter 11-17)

| Chapter | File | Summary |
|------|------|--------|
| Chapter 11  | [chapter-11.md](./chapter-11.md) | Deep dive into ownership models: OwnerCap, Keychain, Borrow-Use-Return, delegation |
| Chapter 12  | [chapter-12.md](./chapter-12.md) | Move advanced: Generics, dynamic fields, event systems, Table and VecMap |
| Chapter 13 | [chapter-13.md](./chapter-13.md) | NFT design and metadata management: Display standard, dynamic NFTs, Collection patterns |
| Chapter 14  | [chapter-14.md](./chapter-14.md) | On-chain economic system design: Token issuance, decentralized markets, dynamic pricing, vaults |
| Chapter 15 | [chapter-15.md](./chapter-15.md) | Cross-contract composability: Calling other Builders' contracts, interface design, protocol standards |
| Chapter 16 | [chapter-16.md](./chapter-16.md) | Location and proximity systems: Hashed locations, proximity proofs, geographic strategy design |
| Chapter 17 | [chapter-17.md](./chapter-17.md) | Testing, debugging, and security audits: Move unit tests, vulnerability types, upgrade strategies |

Companion examples: [Example 3](./example-03.md) On-chain auction house, [Example 6](./example-06.md) Dynamic NFTs, [Example 7](./example-07.md) Stargate logistics network, [Example 9](./example-09.md) Cross-Builder protocol, [Example 13](./example-13.md) Subscription-based pass, [Example 14](./example-14.md) NFT staking and lending, [Example 16](./example-16.md) NFT crafting and decomposition, [Example 18](./example-18.md) Cross-alliance diplomatic treaties

### Phase 4: Architecture, Integration, and Products (Chapter 18-25)

| Chapter | File | Summary |
|------|------|--------|
| Chapter 18 | [chapter-18.md](./chapter-18.md) | Multi-tenancy and game server integration: Tenant model, ObjectRegistry, server-side scripts |
| Chapter 19 | [chapter-19.md](./chapter-19.md) | Full-stack dApp architecture design: State management, real-time updates, multi-chain support, CI/CD |
| Chapter 20 | [chapter-20.md](./chapter-20.md) | In-game integration: Overlay UI, postMessage, game event bridging |
| Chapter 21 | [chapter-21.md](./chapter-21.md) | Performance optimization and Gas minimization: Transaction batching, read-write separation, off-chain computation |
| Chapter 22 | [chapter-22.md](./chapter-22.md) | Move advanced patterns: Upgrade-compatible design, dynamic field extensions, data migration |
| Chapter 23 | [chapter-23.md](./chapter-23.md) | Publishing, maintenance, and community collaboration: Mainnet deployment, Package upgrades, Builder collaboration |
| Chapter 24 | [chapter-24.md](./chapter-24.md) | Troubleshooting handbook: Common Move/Sui/dApp error types and systematic debugging methods |
| Chapter 25 | [chapter-25.md](./chapter-25.md) | From Builder to product: Business models, user growth, community operations, progressive decentralization |

Companion examples: [Example 5](./example-05.md) Alliance DAO, [Example 12](./example-12.md) Alliance recruitment, [Example 15](./example-15.md) PvP item insurance, [Example 17](./example-17.md) In-game overlay implementation

### 🔬 Phase 5: World Contract Source Code Deep Dive (Chapter 26-32)

> Based on real source code from [world-contracts](https://github.com/evefrontier/world-contracts), deep analysis of EVE Frontier core system mechanisms.

| Chapter | File | Summary |
|------|------|--------|
| Chapter 26 | [chapter-26.md](./chapter-26.md) | **Complete access control analysis**: GovernorCap / AdminACL / OwnerCap / Receiving pattern |
| Chapter 27 | [chapter-27.md](./chapter-27.md) | **Off-chain signing × on-chain verification**: Ed25519, PersonalMessage intent, sig_verify deep dive |
| Chapter 28 | [chapter-28.md](./chapter-28.md) | **Location proof protocol**: LocationProof, BCS deserialization, proximity verification implementation |
| Chapter 29 | [chapter-29.md](./chapter-29.md) | **Energy and fuel systems**: EnergySource, Fuel consumption rate calculation, known bug analysis |
| Chapter 30 | [chapter-30.md](./chapter-30.md) | **Extension pattern implementation**: Official tribe_permit + corpse_gate_bounty deep dive |
| Chapter 31 | [chapter-31.md](./chapter-31.md) | **Turret AI extensions**: TargetCandidate, priority queue, custom AI development |
| Chapter 32 | [chapter-32.md](./chapter-32.md) | **KillMail system**: PvP kill records, TenantItemId, derived_object anti-replay |

Companion examples: [Example 8](./example-08.md) Builder competition system, [Example 10](./example-10.md) Comprehensive implementation

### 🔐 Phase 6: Wallet Internals and Future (Chapter 33-35)

> After mastering wallet integration and dApps, dive deeper into wallet internals and future directions for a smoother learning curve.

| Chapter | File | Summary |
|------|------|--------|
| Chapter 33 | [chapter-33.md](./chapter-33.md) | **zkLogin principles and design**: Zero-knowledge proofs, FusionAuth OAuth, Enoki salt, ephemeral key pairs |
| Chapter 34 | [chapter-34.md](./chapter-34.md) | **Technical architecture and deployment**: Chrome MV3 five-layer structure, Keeper security container, messaging protocol, local build |
| Chapter 35 | [chapter-35.md](./chapter-35.md) | **Future outlook**: Zero-knowledge proofs, fully decentralized games, EVM interoperability |

Recommended companion: After completing this phase, review [Example 17](./example-17.md)'s wallet connection, signing, and in-game integration workflow.

---

## 🛠 Example Index (By Complexity, 2 hours each)

> Main roadmap distributed above; index by complexity below for topic selection and review.

### Beginner Examples (Example 1-3) — Basic Component Applications

| Example | File | Technical Highlights |
|------|------|--------|
| Example 1  | [example-01.md](./example-01.md) | Turret whitelist: MiningPass NFT + AdminCap + admin dApp |
| Example 2  | [example-02.md](./example-02.md) | Stargate toll booth: Vault contract + JumpPermit + player ticket dApp |
| Example 3  | [example-03.md](./example-03.md) | On-chain auction house: Dutch auction pricing + auto-settlement + real-time countdown dApp |

### Intermediate Examples (Example 4-7) — Economy and Governance

| Example | File | Technical Highlights |
|------|------|--------|
| Example 4  | [example-04.md](./example-04.md) | Quest unlocking system: On-chain bit flags + off-chain monitoring + conditional stargate |
| Example 5  | [example-05.md](./example-05.md) | Alliance DAO: Custom Coin + snapshot dividends + weighted governance voting |
| Example 6  | [example-06.md](./example-06.md) | Dynamic NFTs: Evolvable equipment with real-time metadata updates based on game state |
| Example 7  | [example-07.md](./example-07.md) | Stargate logistics network: Multi-hop routing + Dijkstra pathfinding + dApp |

### Advanced Examples (Example 8-10) — System Integration

| Example | File | Technical Highlights |
|------|------|--------|
| Example 8  | [example-08.md](./example-08.md) | Builder competition system: On-chain leaderboard + points + automatic trophy NFT distribution |
| Example 9  | [example-09.md](./example-09.md) | Cross-Builder protocol: Adapter pattern + multi-contract aggregated marketplace |
| Example 10 | [example-10.md](./example-10.md) | Comprehensive implementation: Space resource war (integrating characters/turrets/stargates/tokens) |

### Extended Examples (Example 11-15) — Finance and Productization

| Example | File | Technical Highlights |
|------|------|--------|
| Example 11 | [example-11.md](./example-11.md) | Item rental system: Time-locked NFTs + deposit management + early return refund |
| Example 12 | [example-12.md](./example-12.md) | Alliance recruitment: Application deposit + member voting + veto power + auto NFT issuance |
| Example 13 | [example-13.md](./example-13.md) | Subscription-based pass: Monthly/quarterly packages + transferable Pass NFT + renewal |
| Example 14 | [example-14.md](./example-14.md) | NFT staking and lending: 60% LTV + 3% monthly interest + overdue liquidation auction |
| Example 15 | [example-15.md](./example-15.md) | PvP item insurance: Purchase policy + server-signed claims + payout pool |

### Advanced Extended Examples (Example 16-18) — Innovative Gameplay

| Example | File | Technical Highlights |
|------|------|--------|
| Example 16 | [example-16.md](./example-16.md) | NFT crafting and decomposition: Three-tier item system + on-chain randomness + consolation prize mechanism |
| Example 17 | [example-17.md](./example-17.md) | In-game overlay implementation: In-game toll booth + postMessage + seamless signing |
| Example 18 | [example-18.md](./example-18.md) | Cross-alliance diplomatic treaties: Dual-signature activation + deposit constraint + breach evidence and penalties |

---

## 📖 Reading Recommendations

| Phase | Content | Recommendation | Duration |
|------|------|------|------|
| Getting Started | Prelude → Chapter 1-5 → Example 1, 2 | Build gameplay intuition first, then architecture, components, and minimal loop | ~16h |
| Engineering Loop | Chapter 6-10 → Example 4, 11 | Complete the Builder end-to-end workflow first | ~14h |
| Advanced Contracts | Chapter 11-17 → Example 3, 6, 7, 9, 13, 14, 16, 18 | Return to strengthen contract design skills | ~30h |
| Architecture & Products | Chapter 18-25 → Example 5, 12, 15, 17 | Focus on long-term maintenance, game integration, and productization | ~24h |
| Source Code Deep Dive | Chapter 26-32 → Example 8, 10 | Reverse-engineer design philosophy from World core modules, then build complex systems | ~18h |
| Wallet Internals & Future | Chapter 33-35 | Deep understanding of EVE Vault internals and future directions | ~6h |

### Recommended Learning Paths

**Quick Builder Start (Shortest Path, ~26h)**:
Prelude → Chapter 1-4 → Example 1-2 → Chapter 6-10 → Example 4

**Complete Builder Path (~96h)**:
Prelude → Chapter 1-5 → Example 1-2 → Chapter 6-10 → Example 4, 11 → Chapter 11-17 → Example 3, 6, 7, 9, 13, 14, 16, 18 → Chapter 18-25 → Example 5, 12, 15, 17 → Chapter 26-32 → Example 8, 10 → Chapter 33-35

**Source Code Researcher Path (~32h)**:
Prelude → Chapter 3 → Chapter 11 → Chapter 15 → Chapter 26-32 → Example 8, 10 → Chapter 6-10

---

## 📚 Reference Resources

- [Official builder-documentation](https://github.com/evefrontier/builder-documentation)
- [builder-scaffold](https://github.com/evefrontier/builder-scaffold)
- [World Contracts Source Code](https://github.com/evefrontier/world-contracts)
- [Sui Documentation](https://docs.sui.io)
- [Move Book](https://move-book.com)
- [EVE Frontier dapp-kit API](http://sui-docs.evefrontier.com/)
- [Sui GraphQL IDE (Testnet)](https://graphql.testnet.sui.io/graphql)
- [EVE Frontier Discord](https://discord.com/invite/evefrontier)
- [Glossary](./glossary.md)
