# 12. Space Customs & Tax Stargate

## 💡 Core Concept (Concept)
A mandatory deduction system deployed at key traffic chokepoints will impose a proportional asset tax on passing non-whitelist players.

## 🧩Pain Points Solved
- **Tax Evasion**: Manual charging is easy to be circumvented by players through "denial" or "hard break-in".
- **Public Infrastructure Compensation**: The guilds that control the sector need to continue to spend maintenance costs and need stable tax coverage.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Balance forced deduction mechanism**: Use Sui's $SUI balance check. If a player wants to go through the Stargate, PTB will try to withdraw a certain percentage (e.g. 1%) of $SUI from their wallet `split` in the first step.
2. **Interception Determination**: If the balance is insufficient or the balance is "hidden" in an opaque container, the Stargate Contract will not be able to generate a "Jump Ticket".
3. **White list tax exemption**: Friendly guild addresses have permanent immunity in `Stargate_config`.

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (make sure deductions and passes are atomically bound)
- [x] Dynamic Fields (storage massive whitelists and tax quotas)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `CustomsConfig`: Shared configuration object that controls tax proportions.
- `TaxRegistry`: Record the historical tax contributions of major organizations.

## 📅 Development Milestones (Milestones)
- [ ] Write a dynamic proportional deduction contract
- [ ] Implement cross-contract universal calls
- [ ] Design tax data dashboard