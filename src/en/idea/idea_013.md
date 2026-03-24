# 13. Alliance loot distribution system (Automated Loot Distributor)

## 💡 Core Concept (Concept)
After the battle, the commander only needs to put a package of loot into the contract, and the system will automatically distribute the resources to each team member based on the battle list and contribution ratio.

## 🧩Pain Points Solved
- **Manual accounting is tiring**: Counting thousands of pieces of debris and distributing them manually is a nightmare for managers.
- **Low Transparency**: Ordinary members suspect that the commander is withholding high-level loot, which can easily lead to the guild falling apart.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Contribution weight record**: Based on the `Damage_Event` or `Healing_Event` flow generated in the battle, the contract automatically calculates the weight of each address.
2. **Batch Distribution PTB**: Take advantage of Sui’s ability to process thousands of commands in a single transaction. Disassemble the loot SUI or parts with one click and `transfer` to the address list of the corresponding weight.
3. **Public ledger disclosure**: The distribution record exists permanently on the chain, and anyone can audit whether the distribution ratio is fair.

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (high concurrency batch ledger)
- [x] DeepBook (if the loot is minerals, you can sell them with one click and exchange them for SUI for redistribution)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `LootPool`: Shared object to temporarily store loot.
- `ActionRegistry`: Stores the player's recent combat performance.

## 📅 Development Milestones (Milestones)
- [ ] Implement weighted ledger algorithm
- [ ] Write a unified valuation module for loot
- [ ] Automated batch distribution testing