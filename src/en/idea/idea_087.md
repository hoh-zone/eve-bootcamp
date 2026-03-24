# 87. KillMail Forensic Replay Station

## 💡 Core Concept (Concept)
Build a battle damage forensics and tactical replay platform around KillMail. Kill facts, indexes, submitters and resource hashes are saved on the chain; videos, battle logs, voice clips and battlefield screenshots are saved off the chain. Insurers, alliance commanders, mercenaries and media teams can use the same replay platform to determine the authenticity of compensation, review tactics, publish battle reports and generate teaching content.

## 🛠️ Sui core feature application (Sui Features)
- [x] Dynamic Fields / Object Fields: Hook up multiple forensic materials and labels
- [x] Sponsored Transactions: Facilitate victims and third parties to quickly submit materials
- [x] Walrus: store videos, logs and large playback files
- [x] Move core mechanism (Shared, Immutable): public index and immutable evidence summary

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `EvidenceBoard`: Evidence board for a certain KillMail
- `ReplayTicket`: Paid or authorized access credential
- `VerifierNote`: Insurer or arbitrator’s annotation

### Key functions
- `attach_evidence`: Add video and log index
- `verify_case`: Write audit results
- `buy_replay_access`: Purchase replay rights
- `publish_report`: Generate summary of public battle reports

## 💻 Frontend & Client interaction layer (Frontend & Client)
Create KillMail details page, timeline, map hotspot and replay player. Supports filtering by alliance, sector, ship type and battle damage amount.

## 💰 Economic and Business Model (Economic Model)
- Replay access fee
- Insurance verification service fee
- Alliance tactics course
- Media column sponsorship

## 📅 Development Milestones (Milestones)
- [ ] MVP: KillMail with evidence link
- [ ] Playback view page
- [ ] Arbitration and Compensation Comments
- [ ] Tactical reporting and subscription services