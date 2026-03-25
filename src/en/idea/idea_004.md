# 4. Guild Attendance Tracker

## 💡 Core Concept (Concept)
An intelligent gateway deployed at a stargate or rally point. Automatically record members participating in Convergence Action (CTA) and issue non-transferable certificates of honor in real time.

## 🧩Pain Points Solved
- **High statistical cost**: Traditional legions require dedicated personnel to take screenshots to check attendance, which is time-consuming and labor-intensive.
- **Opacity of contributions**: It is difficult to establish a fair military merit reward system.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Geofence Verification**: Only when the player's signature position is within a specific stargate range, the player can interact with the contract.
2. **SBT (Soul Binding Token)**: Issue non-transferable NFT with `Combat_Log` metadata as a points voucher.
3. **Intelligent Accounting**: After the battle, the commander will transfer the spoils SUI to the treasury. According to the treasury contract's holdings of SBT during the week, PTB distributes dividends in batches.

## 🛠️ Sui core feature application (Sui Features)
- [x] Move core mechanics (implement SBT by disabling `transfer`)
- [x] PTB (distribute rewards in batches, support hundreds of people in a single transaction)
- [ ] SuiNS (displays human-readable player names)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `AttendanceBook`: List of addresses stored for check-ins in a specific Epoch.
- `MeritPoint`: SBT.

## 📅 Development Milestones (Milestones)
- [ ] Implement non-transferable token logic
- [ ] Write commander management panel
- [ ] Test batch airdrop performance