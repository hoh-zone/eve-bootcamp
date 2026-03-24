# 19. Automated Ransomware Turret

## 💡 Core Concept (Concept)
After the turret locks on the threat, it does not fire immediately, but pops up the payment interface to the opponent. If the other party pays the set amount of SUI within 30 seconds, its address automatically enters the temporary 10-minute immunity whitelist for that turret.

## 🧩Pain Points Solved
- **Battle loss, lose-lose**: Some battles do not need to be fought to the death. Neither side wants to lose money by destroying the ship.
- **High threshold for bribery**: The protection fee price cannot be quickly negotiated during the battle.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Lock Alarm Linkage**: The turret component senses that the crosshair covers a specific player. The contract sends an `Incoming_Threat` event notification to the player.
2. **PTB instant life purchase**: The victim clicks on the UI to initiate a payment transaction. Once the payment is successful, the Dynamic Field is written to `{Address: Expire_Time}`.
3. **Injury Free Protocol**: In the `fire` logical header of the turret, check the above table items. If it exists and is valid, the instruction is forced to return, thus achieving "take money and let people go".

## 🛠️ Sui core feature application (Sui Features)
- [x] Dynamic Fields (high-speed storage of temporary whitelist permissions)
- [x] PTB (life money and atomicity of whitelist writing)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `RansomRegistry`: Protection fee payment record for a single turret.
- `DefensePolicy`: Manage price range and immunity duration.

## 📅 Development Milestones (Milestones)
- [ ] Write lock-payment interaction flow
- [ ] Implement automatic detection of whitelisted firepower switch
- [ ] Develop UI pop-up warning plug-in