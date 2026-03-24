# 89. Shared mining agreement

## 💡 Core Concept (Concept)
Design the entire mineral belt as a shared object, rather than each player digging their own copy of the resource. Multiple players, teams and alliances can initiate mining, buffing, snatching and blocking operations on the same resource pool at the same time. The system dynamically settles output based on time windows, tool levels, location conditions and the number of collaborators, truly reflecting the sense of the world where "everyone is grabbing the same mine".

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (Programmable Transaction Block): Complete mining, settlement, and rewards in one transaction
- [x] Dynamic Fields / Object Fields: Record mineral layer, gain, collection position and remaining amount
- [x] Sponsored Transactions: Lower the threshold for participation in large-scale events
- [x] Move core mechanism (Shared): multiple parties competing for the same resource pool concurrently

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `SharedAsteroidBelt`: shared mineral zone
- `MiningSlot`: placeholder and tool bonus
- `YieldPool`: Distributable output in this round

### Key functions
- `enter_belt`: Enter the battle for the mineral belt
- `mine_tick`: Settlement of current output according to conditions
- `boost_team`: Add collaboration bonus to the team
- `drain_belt`: Ore belt exhausted and cycle reset

## 💻 Frontend & Client interaction layer (Frontend & Client)
The front end displays the popularity of the mineral zone, remaining amount, participating teams, real-time income and competition logs. Suitable for sector resource battle panels.

## 💰 Economic and Business Model (Economic Model)
- Resource tax
- Tool rental
- Escort service fee
- The party occupying the mineral zone will draw a commission

## 📅 Development Milestones (Milestones)
- [ ] MVP: shared mineral belt and basic mining
- [ ] Multi-person concurrent settlement
- [ ] Alliance bonus and blocking mechanism
- [ ] Hot zone map and tax settlement