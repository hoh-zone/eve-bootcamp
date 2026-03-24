# Chapter 25: From Builder to Product — Commercialization Paths and Ecosystem Operations

> **Goal:** Go beyond the technical layer to understand how to transform your EVE Frontier contracts and dApps into real products with users, revenue, and community, and how to find your position in this emerging ecosystem.

---

> Status: Product chapter. Main text focuses on business models, growth, and operational mechanisms.

## 25.1 Four Business Models for Builders

In the EVE Frontier ecosystem, Builders have four main value capture methods:

```
┌─────────────────────────────────────────────────────────┐
│               Builder Business Model Spectrum            │
├─────────────────┬───────────────────────┬──────────────┤
│ Model           │ Representative Cases  │ Revenue Source│
├─────────────────┼──────────────────────┼──────────────┤
│ Infrastructure  │ Stargate tolls,       │ Usage fees    │
│ Infrastructure  │ Storage markets,      │ (automatic)   │
│                 │ General auction       │               │
├─────────────────┼──────────────────────┼──────────────┤
│ Token Economy   │ Alliance Token + DAO  │ Token         │
│ Token Economy   │ Points system         │ appreciation, │
│                 │                       │ tax           │
├─────────────────┼──────────────────────┼──────────────┤
│ Platform/SaaS   │ Multi-tenant market   │ Platform fee  │
│ Platform        │ framework,            │ Monthly/      │
│                 │ Competition system    │ registration  │
├─────────────────┼──────────────────────┼──────────────┤
│ Data Services   │ Leaderboards,         │ Ads/          │
│ Data & Tools    │ Analytics dashboards, │ subscription, │
│                 │ Price aggregators     │ Premium       │
└─────────────────┴──────────────────────┴──────────────┘
```

The most important thing about this chart isn't helping you "choose a track name," but to see clearly:

> What exactly are you selling - assets, traffic, protocol capabilities, or information advantage.

Many Builder projects fail not because of poor technology, but because they never clearly thought through what they're selling from the start.

---

## 25.2 Pricing Strategy: On-chain Automatic Revenue

The simplest Builder revenue: **automatic commission on transactions**, zero operational cost.

### Two-tier Fee Structure

```move
// Settlement: platform fee + builder fee dual structure
public fun settle_sale(
    market: &mut Market,
    sale_price: u64,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
): Coin<SUI> {
    // 1. Platform protocol fee (EVE Frontier official, if any)
    let protocol_fee = sale_price * market.protocol_fee_bps / 10_000;

    // 2. Your Builder fee
    let builder_fee = sale_price * market.builder_fee_bps / 10_000;    // e.g.: 200 = 2%

    // 3. Remainder to seller
    let seller_amount = sale_price - protocol_fee - builder_fee;

    // Distribution
    transfer::public_transfer(payment.split(builder_fee, ctx), market.fee_recipient);
    // ... protocol fee to official address, remainder to seller

    payment // Return seller_amount
}
```

### Fee Range Recommendations

| Type | Suggested Range | Notes |
|------|---------|------|
| Stargate toll | 5-50 SUI/time | Fixed fee, reflects scarcity |
| Market commission | 1-3% | Benchmark traditional markets |
| Auction platform fee | 2-5% | For matchmaking services provided |
| Multi-tenant platform monthly fee | 10-100 SUI | Other Builders using your framework |

### Why Automatic Commission Looks Best But Is Also Easiest to Overestimate

Its advantages are obvious:

- Revenue automation
- No manual billing
- Directly tied to actual usage

But it also has prerequisites:

- Users are actually willing to continue using your facilities
- Your fees won't be instantly undercut by cheaper alternatives
- Your service has clear differentiation, not pure commodity channels

So on-chain automatic revenue isn't "write a contract and money comes" - it just executes the business model more cleanly.

---

## 25.3 User Acquisition: In-game Touchpoints

Main paths for players to discover your dApp:

```
Touchpoint Priority:

1. In-game display (highest conversion)
   └── Player approaches your stargate/turret → In-game overlay pops up → Direct interaction

2. EVE Frontier official Builder directory (expected feature)
   └── Official lists certified Builder services → Player actively searches

3. Player community (Discord / Reddit)
   └── Word of mouth → Alliance recommendations → User growth

4. In-alliance promotion
   └── Partner with major alliances → Embed in their toolchain → Bulk users
```

### Growth Flywheel Design

```
Players use service
    ↓
Receive rewards (tokens/NFT/privileges)
    ↓
Value is visible and tradable
    ↓
Show off/sell to other players
    ↓
More players learn about and join
    ↓
(Back to top)
```

### Most Easily Overlooked Point in User Acquisition

It's not "how to get more people to click the first time," but "why users stay after clicking."

Especially in EVE scenarios, many features naturally have strong context:

- Will use when needed right now
- Will immediately leave when not needed

So what really needs to be designed is:

- Is first use smooth enough
- Will they come back a second time
- Will it form alliance-level or group-level dependency

---

## 25.4 Community Building: Builder's Moat

In EVE Frontier, **community is your most uncopyable asset**. Technology can be copied, but relationships cannot.

### Community Building Levels

```
1. Discord Server
   ├── #announcements (version updates, new features)
   ├── #support (user Q&A)
   ├── #feedback (collect opinions)
   └── #governance (important decision voting)

2. Regular Communication
   ├── Monthly AMA (Ask Me Anything)
   ├── Transparent financial reports (show Treasury balance and dividend plans)
   └── Public roadmap updates

3. Community Incentives
   ├── Early user NFT badges (see Example 8)
   ├── Feedback rewards (report bugs get tokens)
   └── Referral rewards (bring new users to register alliance)
```

The true value of community isn't in numbers, but in relationship strength and feedback quality.

A small but active Builder community is often more useful than a large but silent channel because it provides:

- Real demand feedback
- Problem reproduction samples
- First wave of evangelists
- Early co-builders

---

## 25.5 Transparency: Trustworthy On-chain Operations

On-chain data is naturally transparent - turn it into a competitive advantage:

```typescript
// Generate monthly public financial report
async function generateMonthlyReport(treasuryId: string) {
  const treasury = await client.getObject({
    id: treasuryId,
    options: { showContent: true },
  });
  const fields = (treasury.data?.content as any)?.fields;

  const events = await client.queryEvents({
    query: { MoveEventType: `${PKG}::treasury::FeeCollected` },
    // Filter for this month's time range...
  });

  const totalCollected = events.data.reduce(
    (sum, e) => sum + Number((e.parsedJson as any).amount), 0
  );

  return {
    date: new Date().toISOString().slice(0, 7),  // "2026-03"
    totalRevenueSUI: totalCollected / 1e9,
    currentBalanceSUI: Number(fields.balance) / 1e9,
    totalUserTransactions: events.data.length,
    topServices: calculateTopServices(events.data),
  };
}
```

Transparency isn't just "making data public" - it's making users understand:

- Where money comes from
- Where money goes
- Which rules are fixed
- Which adjustments were changed later

As long as these can be understood by users, your protocol's trust cost will significantly decrease.

---

## 25.6 Compliance and Risk Management

Although EVE Frontier is decentralized, Builders still need to be aware:

### Technical Risks

| Risk | Mitigation Measures |
|------|---------|
| Contract vulnerabilities causing asset loss | Pre-launch audit; TimeLock upgrades; Set single transaction limits |
| Package upgrades breaking users | Versioned API; Announcement period; Migration subsidies |
| Sui network failures | Manage user expectations well; Set time-based protections |
| Dependent World Contracts upgrades | Follow official changelog; Testnet validation |

### Community Risks

| Risk | Mitigation Measures |
|------|---------|
| User churn | Continuously deliver value; Listen to feedback |
| Competitor copying | Accelerate iteration; Build user relationship moat |
| Negative sentiment | Quick public response; Transparent communication |

### Most Important in Risk Management Is Actually "Contingency Plans"

Not thinking about what to say when something happens, but knowing in advance:

- Which layer to stop first during vulnerabilities
- Whether frontend needs to hide certain entry points first
- Whether sponsored services need to be paused
- Which states and assets need protection first

---

## 25.7 Long-term Sustainability: Progressive Decentralization

The healthiest Builder projects should move toward progressive decentralization:

```
Stage 1 (Launch): Builder centralized control
  • Rapid iteration, flexible adjustments
  • Build initial user base and cash flow

Stage 2 (Growth): Introduce community governance
  • Important parameters (fees, new features) DAO voting
  • Token holders gain proposal rights

Stage 3 (Maturity): Full community autonomy
  • All key decisions via on-chain governance
  • Builder transitions to contributor role
  • Protocol revenue fully distributed to token holders
```

The most important restraint here is: not every project must reach "full community autonomy."

A more realistic question should be:

- Does this project really need governance tokens
- Is the community mature enough to bear governance responsibility
- Which powers are suitable for delegation, which should remain at execution layer

---

## 25.8 EVE Frontier Ecosystem Collaboration Opportunities

Don't go it alone - seek synergies:

```
Horizontal collaboration (similar Builders):
  ├── Share technical standards (interface protocols)
  ├── Joint marketing
  └── Mutual user referrals (your users → my service)

Vertical collaboration (different tier Builders):
  ├── Infrastructure Builders provide APIs
  ├── Application Builders build on top
  └── User experience Builders create portal aggregations

Collaborate with CCP:
  ├── Apply for official Featured Builder certification
  ├── Participate in official testing and feedback projects
  └── Showcase your tools at official events
```

True value of collaboration usually has three types:

- **Distribution**
  Let more people know about you faster
- **Complementarity**
  Don't have to build the full stack from scratch yourself
- **Legitimacy**
  Make users more confident using your service

---

## 25.9 Core Traits of Successful Builders

From technology to product, you need more than just Move code:

```
Technical Capabilities (you already have)    Strategic Capabilities (equally important)
─────────────────────────                  ─────────────────────────────
✅ Move contract development                 ✅ User needs insight
✅ Full-stack dApp development               ✅ Rapid product iteration
✅ Security & testing                        ✅ Community building & communication
✅ Performance optimization                  ✅ Business model design
✅ Upgrades & maintenance                    ✅ Competitive analysis & differentiation
```

Truly long-term successful Builders are usually not "the best code writers," but those who can hold technology, product, community and timing together.

---

## 25.10 Your Builder Journey Roadmap

```
Month 0-1 (Learning):
  ├── Complete all chapters and examples in this course
  ├── Deploy Example 1-2 on testnet
  └── Join Builder Discord, meet the community

Month 1-3 (Experimentation):
  ├── Release testnet version of first product
  ├── Invite test users, collect feedback
  └── Iterate 2-3 rounds

Month 3-6 (Validation):
  ├── Mainnet launch (small scale, cautious testing)
  ├── Achieve first on-chain revenue
  └── Build initial community (Discord 100+ members)

Month 6-12 (Growth):
  ├── Monthly active users 1000+
  ├── Introduce token economy (if suitable)
  └── Establish first cross-Builder collaboration

Year 2+ (Ecosystem):
  ├── Become "infrastructure" in the ecosystem
  ├── Progressive community governance
  └── Sustainable self-operation
```

This roadmap should be treated as a "stage judgment framework" rather than a KPI checklist.

Because different products will have very different paces, but one judgment always holds:

> Prove people are actually using it first, then scale; prove the model works first, then complexify.

---

## 🔖 Chapter Summary

| Dimension | Key Points |
|------|--------|
| Business models | Four models: infrastructure/token/platform/data |
| Pricing strategy | On-chain automatic commission, zero operational cost |
| User acquisition | In-game touchpoints first, community word-of-mouth second |
| Community building | Discord + transparent reports + incentive mechanisms |
| Risk management | Technical audit + upgrade time locks + rapid response |
| Long-term sustainability | Progressive decentralization, eventual community autonomy |

---

## 🎓 Course Complete! You Are Now an EVE Frontier Builder

Congratulations on completing all **23 chapters + 10 practical examples** of this course.

You now have mastered:
- ✅ Move smart contracts from beginner to advanced
- ✅ Complete development and deployment of four smart component types
- ✅ Full-stack dApp development and production-grade architecture
- ✅ On-chain economics, NFTs, DAO governance design
- ✅ Security audits, performance optimization, upgrade strategies
- ✅ Commercialization paths and ecosystem operations

**In this universe, code is the laws of physics. Go build your universe.** 🚀

---

## 📚 Bookmark These Resources

| Resource | Purpose |
|------|------|
| [EVE Frontier Official Site](https://evefrontier.com) | Latest official announcements |
| [builder-documentation](https://github.com/evefrontier/builder-documentation) | Official technical documentation |
| [world-contracts](https://github.com/evefrontier/world-contracts) | World contract source code |
| [builder-scaffold](https://github.com/evefrontier/builder-scaffold) | Project scaffold |
| [Sui Documentation](https://docs.sui.io) | Sui blockchain documentation |
| [Move Book](https://move-book.com) | Move language reference |
| [EVE Frontier Discord](https://discord.com/invite/evefrontier) | Builder community |
| [Sui GraphQL IDE](https://graphql.testnet.sui.io) | On-chain data queries |
