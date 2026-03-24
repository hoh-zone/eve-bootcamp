# 1. Space Flash Loan

## 💡 Core Concept (Concept)
Use Sui's PTB (Programmable Transaction Blocks) to achieve "atomic level" asset lending. Players borrow high-value spaceships within a single transaction, complete mining or trade, and finally return the spaceship and pay interest.

## 🧩Pain Points Solved
- **High barrier to entry**: Novice players cannot afford expensive flagships, resulting in the inability to experience advanced content.
- **Idle Assets**: A large number of spaceships of veteran players are gathering dust in the hangar. There is a lack of safe leasing mechanism and they are worried that they will not be able to get them back after renting them out.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Hot Potato mandatory constraints**: Utilize the `Hot Potato` mode of the Move language. When a player calls `borrow_ship`, the system returns a receipt without the `drop` capability.
2. **Atomic operation loop**: In the same PTB, the second step must be to use the ship to perform some kind of profit-making behavior (such as triggering a mining contract), and the third step must call `return_ship` to destroy the certificate and return the asset ownership.
3. **Zero Risk Leasing**: If the spaceship is blown up during the transaction or the balance is insufficient to pay the interest, the entire PTB will be rolled back directly, and the spaceship will still remain safely in the lender's contract, and even time and space will "go back" to before departure.

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (atomized borrow-borrow-return loop)
- [x] Move core mechanism (Hot Potato locks transaction integrity)
- [ ] zkLogin
- [ ] sui::random

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `LoanPool`: Shared object, which stores the spacecraft Kiosk permissions that can be loaned out.
- `BorrowReceipt`: Hot Potato, ensures that it must be returned in the same transaction after being lent.

## 📅 Development Milestones (Milestones)
- [ ] Design the lending protocol interface
- [ ] Implement Hot Potato logic test
- [ ] Integrated EVE World item ownership check