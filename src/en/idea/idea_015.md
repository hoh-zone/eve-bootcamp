# 15. Spy Network Paywall

## 💡 Core Concept (Concept)
Coordinate information such as spacecraft location and resource points detected by intelligence personnel in hostile galaxies. This information is encrypted and locked in the contract, and the buyer can only unlock it after paying SUI.

## 🧩Pain Points Solved
- **Risk of free prostitution**: The intelligence officer worked hard to detect, and the post was shared by everyone on Discord, but he received no personal reward.
- **Information expires quickly**: Extremely fast transaction confirmation is required to ensure that the purchased intelligence is still tactically timely.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Encrypted Metadata Mount**: Use `Dynamic Field` to store intelligence, but the data segments are biased encrypted with the purchaser's public key (or preset key).
2. **Unlock upon payment**: At the moment PTB executes `pay_for_intel`, the contract updates the metadata status and returns the decryptable fragment.
3. **Authenticity gambling mechanism**: If the buyer finds that the coordinates are fake (there is no target at the coordinates within 5 minutes), he can initiate a refund appeal and use the third-party reputation evaluation system to punish the scammer.

## 🛠️ Sui core feature application (Sui Features)
- [x] zkLogin (can be used as a public key basis for private communication)
- [x] Move core mechanism (high performance access to dynamic fields)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `IntelPacket`: Encrypted intelligence package.
- `ReputationRegistry`: Intelligence agent credit rating table.

## 📅 Development Milestones (Milestones)
- [ ] Write encryption/decryption logic
- [ ] Implement payment-release process
- [ ] Build a prototype of a decentralized arbitration system