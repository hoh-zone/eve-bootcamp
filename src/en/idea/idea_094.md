# 94. Server-wide countdown battle

## 💡 Core Concept (Concept)
Create a publicly verifiable countdown event based on `Clock` on the chain. A certain resource box, limited-time stargate, war window, migration opportunity or bounty pool will be settled at a fixed time point, and everyone can see the same countdown. Players must raise money, hold points, deliver goods, vote or evacuate before reaching zero. The rewards and attribution will be settled according to the rules at the end of the countdown.

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (Programmable Trading Block): organizes participation, staking and settlement together
- [x] Sponsored Transactions: Facilitate participation in large-scale events
- [x] Move core mechanism (Shared): multiple people competing for the same countdown event at the same time

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `CountdownEvent`: event ontology
- `StakePool`: Betting or entry pool
- `ResultBoard`: settlement record after zeroing

### Key functions
- `create_event`: Create countdown event
- `join_event`: Enter or place a bet
- `resolve_event`: settlement at the point
- `claim_reward`: Receive rewards

## 💻 Frontend & Client interaction layer (Frontend & Client)
The front end highlights the countdown, participating parties, current bets, event map and historical reset records. Suitable for season activity pages and world event pages.

## 💰 Economic and Business Model (Economic Model)
- Registration fee
- Bet rake
- Event sponsorship
- War zone traffic portal cooperation

## 📅 Development Milestones (Milestones)
- [ ] MVP: single event countdown
- [ ] Entries and bets
- [ ] Automatic settlement
- [ ] Seasonalization of multiple events