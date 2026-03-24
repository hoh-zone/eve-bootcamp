# 3. Decentralized Space Pawnshop

## 💡 Core Concept (Concept)
Players are allowed to mortgage rare NFTs (such as paints and blueprints) to smart contracts in exchange for liquidity tokens (SUI or EVE Credits). If no repayment is due, the assets will be automatically auctioned.

## 🧩Pain Points Solved
- **It is difficult to realize fixed assets**: I hold the best blueprint but urgently need money to buy ammunition. I am reluctant to sell it. If I don’t sell it, I will have no money.
- **OTC fraud risk**: Private mortgages are easy to be hacked.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Asset Custody Kiosk**: Use `Sui Kiosk` to store collateral and ensure royalty and ownership transparency.
2. **Mortgage rate calculation**: Automatically set LTV (mortgage rate, such as 50%) based on DeepBook's historical average transaction price.
3. **Liquidation Mechanism**: Introducing timestamps. If `Clock::now_ms()` exceeds the redemption period and the debt is outstanding, the contract transfers ownership of the asset to `Public Auction` mode.

## 🛠️ Sui core feature application (Sui Features)
- [x] Sui Kiosk (Secure Asset Storage)
- [x] DeepBook (price reference source)
- [ ] Move core mechanism

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `PawnTicket`: represents the mortgage warrant, including overdue time, principal, and interest.

## 📅 Development Milestones (Milestones)
- [ ] Integrate Kiosk borrowing logic
- [ ] Connect to price oracle
- [ ] Implement automatic auction switching