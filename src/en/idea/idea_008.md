# 8. Shared Battery Network

## 💡 Core Concept (Concept)
Shared energy Object deployed on sector nodes. Any ship can approach it and pay SUI to replenish hull power/fuel in real time.

## 🧩Pain Points Solved
- **Food Crisis**: The power ran out during a long-distance jump and was forced to float in space to wait for death.
- **Energy Monopoly**: It is difficult for small guilds to build their own fuel supply lines.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **On-demand billing micropayment**: Using PTB, every time a player requests 10% fuel replenishment, the corresponding $SUI will be automatically deducted.
2. **Investment income**: Individual players can "inject energy" into charging piles or invest $SUI to purchase shares, and receive passive income dividends based on the popularity of charging.
3. **Service competition**: The prices of different nodes can fluctuate with market demand, forming a Sinopec/CNPC competition network in space.

## 🛠️ Sui core feature application (Sui Features)
- [x] Shared Objects (concurrent charging)
- [x] Sponsored Transactions (allows ships with no power to pay a startup fee on behalf of the system)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `BatteryNode`: Shared object containing inventory and exchange rates.
- `DividendShare`: Investor warrant.

## 📅 Development Milestones (Milestones)
- [ ] Implement fuel-SUI exchange logic
- [ ] Prepare a multi-shareholder dividend contract
- [ ] Front-end map marks charging points