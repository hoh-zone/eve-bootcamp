# 99. ZK cross-chain identity mapping

## 💡 Core Concept (Concept)
Make a "multi-world identity passport" based on zero-knowledge proof. Players can prove that they have a certain identity, achievement, credibility or qualifications in other chains, other game worlds or external communities without disclosing their full account history and asset details. Recruitment, access control, blacklist exemption and high-end market in EVE Frontier can open special permissions accordingly.

## 🛠️ Sui core feature application (Sui Features)
- [x] zkLogin: Connect with EVE Vault identity system
- [x] Dynamic Fields / Object Fields: Record the proof type and validity period
- [x] Sponsored Transactions: Lower the verification threshold
- [x] Move core mechanism (Shared, Owned): Combination of public verification rules and private certificates

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `IdentityPassport`: Player ID Passport
- `ProofPolicy`: Validation rules for certain types of external qualifications
- `AccessBadge`: Local permission token minted after verification

### Key functions
- `submit_proof`: Submit proof
- `verify_policy`: Verify by rules
- `mint_badge`: Issue local access
- `revoke_badge`: Expired or revoked

## 💻 Frontend & Client interaction layer (Frontend & Client)
The front end displays bound identities, provable qualifications, unlockable permissions and privacy instructions. Suitable for access to alliance recruitment and VIP access control.

## 💰 Economic and Business Model (Economic Model)
- High-end access verification fee
- Alliance recruitment tool fee
- Identity hosting service
- Cooperation across community members

## 📅 Development Milestones (Milestones)
- [ ] MVP: single-class external proof mapping
- [ ] Local badge issuance
- [ ] Multi-strategy verification
- [ ] Alliance recruitment and gate control integration