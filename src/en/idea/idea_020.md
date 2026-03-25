# 20. Universal Basic Income Generator (UBI Generator)

## 💡 Core Concept (Concept)
A completely public welfare DAO treasury that automatically airdrops low-income materials to novices who have been registered for less than 7 days or whose assets are below a specific threshold every day based on the server-wide transaction tax or donations from big players.

## 🧩Pain Points Solved
- **High turnover rate for newbies**: The game is completely robbed by old players at the beginning and cannot continue to mine and jump.
- **Poor ecological diversity**: The gap between the rich and the poor is too large, causing it to become a small circle of die-hard bosses in the later stages of the game.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Identity authentication and anti-swipe**: Verify the identity of newbies through SuiNS registration duration or specific anti-swipe authentication (such as the non-temporary email associated with zkLogin).
2. **Flow Energy Pool**: All commercial facilities (star gates, toll stations) in the server withdraw 0.1% of their profits and flow them to this UBI contract.
3. **Daily one-click claim**: Novice players can claim a small bundle of fuel, a few ordinary shells and a small amount of SUI Gas subsidies through PTB by clicking on the UI.

## 🛠️ Sui core feature application (Sui Features)
- [x] Sponsored Transactions (Exempting gas fees for novices receiving minimum living allowance)
- [x] zkLogin (social identity binding verification)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `UBITreasury`: Shared object that stores grants.
- `ClaimLog`: History table to prevent repeated collection.

## 📅 Development Milestones (Milestones)
- [ ] Write a novice identity determination module
- [ ] Implement profit aggregation logic from multiple sources
- [ ] Develop front-end UBI receiving dashboard