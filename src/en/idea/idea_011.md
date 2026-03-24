# 11. Mercenary Firepower Renting

## 💡 Core Concept (Concept)
Players are allowed to temporarily lease the control rights (OwnerCap) of high-level turrets to others. After expiration, the control rights are automatically recovered through contract logic.

## 🧩Pain Points Solved
- **Asymmetrical Firepower**: Novices mining in dangerous areas are easily harassed by pirates, but they cannot afford frigates.
- **Waste of Asset Value**: Mercenary heavy turrets can only sit idle during non-war periods.

## 🎮 Detailed gameplay and mechanics (Gameplay Mechanics)
1. **Time-stamp limited time authorization**: The tenant pays SUI and obtains an `Temporary_Access_Token` containing the expiration time.
2. **Ownership Lock**: During the lease period, the tenant can only execute `shoot` instructions, but cannot execute `unmount` or `transfer`.
3. **Automatic recycling upon expiration**: The contract checks `Clock` before processing the instruction. If the time has elapsed, the token automatically expires and ownership is transferred back to the original owner's Kiosk.

## 🛠️ Sui core feature application (Sui Features)
- [x] Sui Kiosk (restricted ownership forwarding)
- [x] Move core mechanism (automatic expiration logic is implemented through embedded timestamps)

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)
### Core Object
- `FirepowerToken`: Temporary permission credentials with validity period.
- `RentVault`: Shared object hosting rentals.

## 📅 Development Milestones (Milestones)
- [ ] Write time-limited logic module
- [ ] Implement restricted ownership transfer API
- [ ] Develop rental market UI display