# 96. Cursed Mutated Ancient Divine Weapon

## 💡 Core Concept (Concept)
Create a dangerous weapon system that will constantly mutate with kills, recasts, repairs, and sacrifices. Ancient divine weapons will grow and have backlash: they may obtain powerful entries, or they may bring curse effects, maintenance costs, or extreme paranoia towards certain types of targets. Players need to decide whether to continue to cultivate it, sell it to collectors, take it to the altar for refinement, or seal it before it gets out of control.

## 🛠️ Sui core feature application (Sui Features)
- [x] Dynamic Fields / Object Fields: Record mutation history, entries and curse status
- [x] sui::random: settlement mutation direction
- [x] Sponsored Transactions: Lower the altar interaction threshold
- [x] Sui Kiosk: Trading dangerous gear
- [x] Move core mechanism (Owned): weapons as independent growth objects

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `AncientWeapon`: Divine weapon body
- `MutationRecord`: mutation record
- `CurseAltar`: Altar or lavatory

### Key functions
- `feed_killmail`: Drive growth with KillMail
- `mutate_weapon`: Trigger mutation
- `purify_weapon`: Attempt to cleanse side effects
- `seal_weapon`: Seal it as a collection

## 💻 Frontend & Client interaction layer (Frontend & Client)
The front end displays growth trees, mutation logs, risk ratings and transaction price curves. Suitable for collection market and PvP equipment show.

## 💰 Economic and Business Model (Economic Model)
- Cleaning fee
-Altar toll
- Rare equipment transaction fees
- Collection and exhibition services

## 📅 Development Milestones (Milestones)
- [ ] MVP: Growth record
- [ ] Random mutation
- [ ] Purification and sealing
- [ ] Transactions and Leaderboards