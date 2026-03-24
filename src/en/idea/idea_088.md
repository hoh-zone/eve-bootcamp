# 88. Hot Potato Wanted Beacon

## 💡 Core Concept (Concept)
Make Hot Potato mode a high-stakes PvP activity beacon. The player holding the beacon must complete a specific action within a limited time, such as killing, arriving at a certain location, delivering goods, or passing the beacon to the next person; otherwise the deposit will be forfeited, or their location and identity will be broadcast to the hunting network. It is suitable for escape games, hunting shows, gambling expresses and internal league selections.

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (Programmable Transaction Block): Put delivery, settlement, and slashing into the same transaction link
- [x] Sponsored Transactions: Lower the threshold for participation and spectatorship
- [x] sui::random: Generate seasonal effects or burst rules
- [x] Move core mechanism (Hot Potato, Shared): implement non-persistent beacons

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `BountyBeacon`: Hot Potato Beacon
- `EscapePool`: deposit pool and bonus pool
- `RoundRule`: Rules for this round of competition

### Key functions
- `start_round`: Start a round of hunting
- `pass_beacon`: Pass the beacon to the next player
- `claim_survival_reward`: Receive rewards after completing the goal
- `slash_holder`: Forfeit if timeout is not completed

## 💻 Frontend & Client interaction layer (Frontend & Client)
The front-end displays a countdown, hunt map, pass history, prize pool, and survival rankings. It can be connected to the floating layer in the game to remind the beacon status in real time.

## 💰 Economic and Business Model (Economic Model)
- Event registration fee
- Sponsorship prize pool
- Tickets to watch the match
- High-level hunter ranking rewards

## 📅 Development Milestones (Milestones)
- [ ] MVP: Hot potato delivery in a single game
- [ ] Deposit and forfeiture logic
- [ ] Real-time ranking list
- [ ] Multi-season rules and sponsorship system