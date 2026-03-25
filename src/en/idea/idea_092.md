# 92. Flagship test drive and limited time borrowing shipyard

## 💡 Core Concept (Concept)
Use Borrow mode to create a "limited time borrowing" system for high-value ships and facilities. Novices can test drive expensive ships, event organizations can issue sponsored ships, and rich players can rent their flagships to others for short periods of time. The system makes the borrowing experience safer through deposit, time limit, activity scope and automatic recycling rules.

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (Programmable Transaction Block): Lending, deposit, and return are settled in one link
- [x] Sponsored Transactions: Lower the test drive threshold
- [x] Move core mechanism (Borrow, Owned): embodies limited-time borrowing and recycling

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `RentalGarage`: Rental Garage
- `BorrowTicket`: Borrowing voucher
- `DepositVault`: deposit pool

### Key functions
- `list_ship`: Borrowable ships are listed
- `borrow_ship`: Lending after paying deposit
- `return_ship`: Return and settle
- `slash_deposit`: Overdue or illegal deposit

## 💻 Frontend & Client interaction layer (Frontend & Client)
The front-end displays the shipyard, test drive package, remaining loan time and deposit status. Supports event-specific invitation codes and intra-league ship borrowing.

## 💰 Economic and Business Model (Economic Model)
- Rent
- Deposit spread
- Race sponsorship ship package
- High-end ship experience service

## 📅 Development Milestones (Milestones)
- [ ] MVP: listing and borrowing
- [ ] Deposit and violation settlement
- [ ] Tournament mode and alliance mode
- [ ] Fleet Experience Package