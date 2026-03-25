# 18. Border Control API

## 💡 Core Concept (Concept)
An extremely strict access control gateway. Before a player enters a certain star sector, in addition to verifying their identity, they will also automatically review the $SUI balance level in their wallet or whether they hold assets from a specific blacklisted guild.

## 🧩Pain Points Solved
- **Insert infiltration**: A simple whitelist can easily be circumvented by spies who "temporarily change jobs".
- **Resource white prostitution**: Prevent low-value, non-output "broiler" accounts from occupying core high-energy mineral areas at will.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Multiple Condition Combination Check**: Entry instructions are executed by PTB. The first step is to query the SuiNS domain name correlation, and the second step is to query the holdings of a specific Medal of Honor (Badge) in the wallet.
2. **Dynamic rejection logic**: If the address has been marked as `Treasonous` (traitor), the gateway contract automatically triggers `abort`, causing the jump transaction to fail.
3. **Asset Ticket**: Set the "position entry" mode, for example: only those with more than 1,000 SUI in the wallet are allowed to cross this core hub.

## 🛠️ Sui core feature application (Sui Features)
- [x] SuiNS (fast identity retrieval)
- [x] PTB (conditional check before jumping)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `VisaRequest`: Contains proof of authority that passes the condition.
- `BorderPolicy`: The traffic restriction strategy modified by the commander in real time.

## 📅 Development Milestones (Milestones)
- [ ] Write asset threshold review logic
- [ ] Integrated blacklist database management
- [ ] Realize emergency retreat (one-click door closing) function