# 100. Battle to recover governance fragments

## 💡 Core Concept (Concept)
Don’t make `AdminCap` a dangerous design that “makes you invincible when you pick it up”, but make it a safe and active management event. The system abstracts governance rights into a number of "governance rights fragments" or "simulation control keys", which are distributed in different regions, task chains and alliance competitions. Players collect enough fragments through occupying points, escorting, solving puzzles, auctions or diplomatic exchanges to obtain the qualifications to govern a certain limited-time event, such as opening war monuments, determining season tax rates, and unlocking neutral port activities.

## 🛠️ Sui core feature application (Sui Features)
- [x] PTB (Programmable Transaction Block): shard collection, synthesis and vote settlement
- [x] Dynamic Fields / Object Fields: Save fragment distribution, event rules and governance results
- [x] Sponsored Transactions: Lower the threshold for participation in large-scale events
- [x] Move core mechanism (Shared, Immutable): governance results leave traces and are publicly auditable

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `GovernanceShard`: Governance fragments
- `SeasonEvent`: Season governance events
- `CouncilResult`: Result of this round of resolution

### Key functions
- `claim_shard`: Get fragments
- `combine_shards`: Synthetic effective governance qualifications
- `vote_event`: Vote on limited time events
- `finalize_result`: Publish the results and write records

## 💻 Frontend & Client interaction layer (Frontend & Client)
The front end displays the fragment map, holder list, event status, voting panel and season report. Suitable for hosting large-scale events.

## 💰 Economic and Business Model (Economic Model)
- Event tickets
- Alliance sponsorship
- Season Pass
- Pay for battle report content

## 📅 Development Milestones (Milestones)
- [ ] MVP: Fragment competition and synthesis
- [ ] Limited time event voting
- [ ] Result traces and display
- [ ] Multi-season governance campaign