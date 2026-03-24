# 16. Decentralized Mining Order Board (Alliance Job Board)

## 💡 Core Concept (Concept)
Similar to an outsourced publishing platform. Anyone who posts the required resources (for example: 10 million tons of ice ore is needed) deposits a SUI bounty. As long as any individual deposits the minerals into the designated storage box, the contract will be automatically settled.

## 🧩Pain Points Solved
- **Raw material supply is cut off**: The Grand Alliance is busy fighting wars and has no time to organize mining.
- **Gig worker trust threshold**: Individual miners dare not work for large guilds for fear of being repudiated.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Smart Anchoring for Contract Performance**: The issuer deposits the bounty amount and the required ore Object definition into the contract.
2. **Item deposit trigger**: Utilize the storage box permission hook of EVE World. When the ore object with the specified ID is put into the vault, the contract senses and deducts the task quota.
3. **Atomic settlement**: Complete "ore ownership transfer" and "SUI remuneration payment" in one transaction, without administrator intervention at all.

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (atomized physical-fund exchange)
- [x] Sui Kiosk (Manage item ownership confirmation)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `JobPost`: Storage demand, unit price, target storage point.
- `MinerProfile`: Record completion.

## 📅 Development Milestones (Milestones)
- [ ] Write item type verification module
- [ ] Implement automatic quotation and transaction logic
- [ ] Management console for development task publishers