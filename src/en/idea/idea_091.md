# 91. Only recognize the captain’s private flagship

## 💡 Core Concept (Concept)
Design a high-value flagship system with strong identity binding. Ship control rights, key modules and driving permissions are tied to specific roles or authorized rosters. Even if the enemy captures the hull, they cannot directly drive away or take over the core functions. It is suitable as an alliance flagship, command ship, family heritage ship and high-end event ship.

## 🛠️ Sui core feature application (Sui Features)
- [x] Dynamic Fields / Object Fields: Save module slots and authorization rosters
- [x] Sponsored Transactions: Lower authorization and maintenance thresholds
- [x] Move core mechanism (Owned, Shared): distinguish between private hull and public status

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `PrivateFlagship`: flagship body
- `CaptainLicense`: Captain’s permission
- `LockdownRule`: Emergency ship locking rules

### Key functions
- `assign_captain`: Set captain
- `grant_delegate`: Grants permission to an adjutant or fleet member
- `lockdown_ship`: Lock core functions when exception occurs
- `transfer_heritage`: Inherit or sell flagship

## 💻 Frontend & Client interaction layer (Frontend & Client)
Provides flagship panel, authorization tree, maintenance log and inheritance process page. Suitable for alliance backend and fleet management tools.

## 💰 Economic and Business Model (Economic Model)
- High-end ship service fee
- Authorization change fee
- Inheritance and sequestration fees
- Alliance level maintenance subscription

## 📅 Development Milestones (Milestones)
- [ ] MVP: Captain binding and authorization
- [ ] Emergency ship locking logic
- [ ] Delegation and inheritance process
- [ ] Alliance backend access