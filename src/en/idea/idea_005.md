# 5. Dynamic Toll Stargate

## 💡 Core Concept (Concept)
A stargate charging component that uses algorithms to automatically adjust transportation fees. The greater the traffic volume, the more expensive the tolls will be, and the profits will go to the Stargate Owners Alliance.

## 🧩Pain Points Solved
- **Strategic Cutting Difficulty**: Unable to effectively prevent enemy fleets from passing through on a large scale.
- **Inefficient commercialization**: Fixed charges cannot cope with the explosive demand during the war.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **AMM-like pricing algorithm**: simulates Uniswap’s `x*y=k` or linear growth. The more ships pass per minute, the cost of the next ship increases by `Base_Fee * (1 + 0.1^N)`.
2. **Whitelist Reduction**: Members of this guild pass Dynamic Field verification and enjoy a fixed 0 fee.
3. **Strategic Moat**: At the moment of decisive battle, the enemy's logistics material support (ammunition/fuel) faces huge economic pressure through extremely high tolls.

## 🛠️ Sui core feature application (Sui Features)
- [x] Dynamic Fields (store temporary discounts/vouchers per address)
- [x] Sponsored Transactions (pay travel expenses for friendly allies)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `GateTreasury`: Store earnings.
- `FlowController`: Dynamic parameter adjustment.

## 📅 Development Milestones (Milestones)
- [ ] Writing a pricing curve contract
- [ ] Implement whitelist management
- [ ] Front-end display of real-time land price map