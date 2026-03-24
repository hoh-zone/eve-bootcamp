# 17. Fuel Futures Exchange

## 💡 Core Concept (Concept)
Allow players to tokenize resources that are expected to be produced in the future (such as next week's expected fuel production) and conduct early trading and hedging.

## 🧩Pain Points Solved
- **Severe price fluctuations**: As the decisive battle approaches, fuel prices skyrocket, and guilds need to lock in costs in advance.
- **Cash flow pressure**: Miners need to obtain funds in advance to upgrade equipment.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Capacity Bonding**: Miners mortgage their own resource generator Object. Based on its production capacity, the contract issues the corresponding "Futures Token".
2. **DeepBook limit order matching**: Use DeepBook as the underlying engine to allow buyers and sellers to conduct futures betting transactions.
3. **Physical Delivery at Expiration**: The contract sets the expiration time. When it expires, the holder of the production capacity token can directly withdraw the corresponding physical resources from the miner's output Object.

## 🛠️ Sui core feature application (Sui Features)
- [x] DeepBook (Central Limit Order Book Trading)
- [x] Move core mechanism (minting and destruction of capacity tokens)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `FutureToken`: Represents future resource ownership.
- `SettlementVault`: Settlement vault.

## 📅 Development Milestones (Milestones)
- [ ] Integrate DeepBook trading pairs
- [ ] Write production capacity assessment and bond issuance logic
- [ ] Develop delivery and clearing system