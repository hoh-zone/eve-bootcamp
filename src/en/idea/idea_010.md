# 10. Disposable first aid kit vending machine (Emergency Medical Bay)

## 💡 Core Concept (Concept)
Vending machines deployed around the battlefield sell one-time NFT consumables that can instantly restore shields or remove debuffs.

## 🧩Pain Points Solved
- **Low combat fault tolerance**: Missing a mouthful of milk at the critical moment will cause the ship to explode.
- **Long supply cycle**: It is too far to return to the base to repair the ship.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Use and destroy mode**: Consumable NFTs will be `burn` immediately after being called to prevent fraudulent orders.
2. **Random Pack Design**: Using `sui::random`, players have a small probability of getting a "Super Repair Pack" (100% full health recovery) through the vending machine.
3. **Mobile support**: Quickly purchase by scanning the QR code in your wallet, and you can quickly complete the recharge even in the middle of a fierce battle.

## 🛠️ Sui core feature application (Sui Features)
- [x] sui::random (random gain extraction)
- [x] Move core mechanism (consumable Object destruction)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `MedKit`: Disposable consumables.
- `VendingMachine`: Vending machine inventory.

## 📅 Development Milestones (Milestones)
- [ ] Implement random drop probability
- [ ] Write instant recovery effect interface
- [ ] Added time-limited item expiration mechanism