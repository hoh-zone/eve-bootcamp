# 2. Automated SOS Beacon

## 💡 Core Concept (Concept)
An intelligent component integrated into the spacecraft. When the armor value of the spacecraft falls below the critical point, a distress signal is automatically broadcast to the entire network, and a bounty is locked for the first rescuer to repel the enemy.

## 🧩Pain Points Solved
- **Slow response**: Typing to ask for help from the guild is often too late, and the robbers can complete the destruction within a few seconds.
- **Lack of Trust**: Passers-by are afraid to save when they see a call for help. They are worried that the victim will not give money after saving, or even worry that they are being used as bait.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Automatic Fund Escrow**: Players deposit 10 SUI in the beacon as a "deposit" before sailing.
2. **Event-driven broadcast**: When the spacecraft `Health` component triggers the `Critical_Alert` event, the contract immediately releases the `SOS_Signal` Event.
3. **PTB real-time settlement**: The rescuer generates `Killmail` voucher after causing damage to the robber. The rescuer submits the credentials to the contract, and after the contract verifies that the killing time matches the rescue time, the bounty is instantly distributed from the hosting pool without the need for the victim to manually click.

## 🛠️ Sui core feature application (Sui Features)
- [x] Sponsored Transactions (allows victim to signal when resources are exhausted)
- [x] PTB (verify the atomicity of kills and payments)
- [ ] Dynamic Fields / Object Fields

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `SOSBeacon`: Contains ship mounts `Balance` and `Threshold`.
- `RescueReward`: Asset package to be collected.

## 📅 Development Milestones (Milestones)
- [ ] Write damage monitoring logic
- [ ] Access Killmail verification logic
- [ ] Implement automatic payment contract