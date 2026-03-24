# 14. Dead-Man's Switch Inheritor

## 💡 Core Concept (Concept)
If the player does not have any on-chain interaction within a set period of time (such as 30 days), control of the properties, spaceships, and resources under his name will automatically be transferred to the designated heir.

## 🧩Pain Points Solved
- **Assets sunk**: The boss suddenly retired (sold his account/forgot his private key), and hundreds of millions of assets under his name became dead objects that could not be used.
- **Inheritance Interruption**: When the leader of a small guild withdraws from the guild, he cannot smoothly hand over the guild authority card to the vice-leader.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Heartbeat packet monitoring**: The contract records the `Timestamp` signed by the player each time.
2. **Activation Determination**: When an outsider (heir) initiates an inheritance request, the contract checks `Current_Time - Last_Active_Time > Threshold`.
3. **Ownership cascade transfer**: Use the `transfer` function of Move to forcefully reset the ownership of the `Kiosk` or control object originally bound to the name of the recipient.

## 🛠️ Sui core feature application (Sui Features)
- [x] Move core mechanism (forced transfer of ownership through timestamp)
- [x] Sui Kiosk (batch transfer of asset packages)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `WillBook`: A mapping table that specifies inheritance relationships and activation conditions.
- `InheritanceCapsule`: Container containing legacy assets.

## 📅 Development Milestones (Milestones)
- [ ] Write interaction time recording module
- [ ] Implement inheritance rights activation verification
- [ ] Asset batch transfer logic stress test