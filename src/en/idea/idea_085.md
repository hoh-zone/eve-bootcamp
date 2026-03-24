# 85. Interstellar Radio and Route Broadcasting Network

## 💡 Core Concept (Concept)
Create a broadcast network for routes and base nodes throughout the universe. Alliances, chambers of commerce, mercenary organizations and media teams can create their own channels to publish war briefings, route warnings, trade advertisements, escort recruitment and event programs. Channel ownership, charging rules, reward records and program indexes are saved on the chain, and audio or video is stored in Walrus. When players pass a certain Gate, enter a certain base or open a dApp, they will receive real-time broadcasts of the corresponding area.

## 🛠️ Sui core feature application (Sui Features)
- [x] Dynamic Fields / Object Fields: Save channel, program list, sponsorship and region tags
- [x] zkLogin: allows ordinary players to subscribe, reward and collect channels at a low threshold
- [x] Sponsored Transactions: Lower the threshold for audience subscription and interaction
- [x] SuiNS: Bind a friendly name to the channel, such as `war-room.sui`
- [x] Walrus: storage of long audio, video playback and archive programs

## 📐 Smart Contract Architecture Planning (Smart Contract Architecture)

### Core Object
- `RadioStation`: Radio station itself, recording station director, channel name, charging mode, and regional label
- `ProgramPass`: Subscription ticket or single-issue listening voucher
- `BroadcastArchive`: Program index, Walrus resource pointer, sponsorship record

### Key functions
- `create_station`: Create radio station and default channel
- `publish_program`: Publish program index and resource links
- `buy_pass`: Purchase channel subscription or single-issue listening rights
- `tip_station`: Reward the anchor or channel

## 💻 Frontend & Client interaction layer (Frontend & Client)
Create a "Galaxy Radio" page to filter programs by sector, alliance, language, and type. The in-game overlay can push local base broadcasts, road alerts and event recruitment based on the current location.

## 💰 Economic and Business Model (Economic Model)
- Subscription fee
- Single paid program
- Advertising space and sponsorship space
- Anchors’ share and channel alliance’s share

## 📅 Development Milestones (Milestones)
- [ ] MVP: single channel publish and subscribe
- [ ] Added to Walrus resource index
- [ ] In-game regional broadcast push
- [ ] Multi-channel leaderboard and sponsorship system