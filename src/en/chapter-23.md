# Chapter 23: Deployment, Maintenance, and Community Collaboration

> **Objective:** Master the complete deployment process from development to production, understand the boundaries and positioning of the Builder ecosystem, and become a sustainably active EVE Frontier builder.

---

> Status: Deployment and operations chapter. Main content focuses on launch process, maintenance, and Builder collaboration.

##  23.1 Complete Deployment Checklist

From local development to official launch, you need to go through the following phases:

```
Phase 1 —— Local Development (Localnet)
  ✅ Docker local chain running
  ✅ Move build compiles successfully
  ✅ All unit tests pass
  ✅ Functional testing (scripts simulate complete flow)

Phase 2 —— Testnet
  ✅ sui client publish to testnet
  ✅ Extension registered to test components
  ✅ dApp deployed to test URL
  ✅ Invite small group of users for testing

Phase 3 —— Mainnet Launch
  ✅ Code audit (self-audit + community review)
  ✅ Backup UpgradeCap to secure address
  ✅ sui client switch --env mainnet
  ✅ Publish contract, record Package ID
  ✅ dApp deployed to official domain
  ✅ Notify community / update announcements
```

This checklist itself is fine, but what really needs to be established is a concept:

> Deployment is not "moving code from local to chain," but "switching a real service that will be used and depended upon by people to production state."

So deployment must cover four tracks simultaneously:

- **Contract Track**
  Is the package published correctly, are permissions configured correctly
- **Frontend Track**
  Is dApp connected to correct network and objects
- **Operations Track**
  Do users know how to use the new version, are old entry points invalid
- **Emergency Track**
  Who handles when issues occur, which layer to stop first

---

##  23.2 Network Environment Configuration

Sui and EVE Frontier support three networks:

| Network | Purpose | RPC Address |
|------|------|---------|
| **localnet** | Local development, Docker startup | `http://127.0.0.1:9000` |
| **testnet** | Public testing, no real value | `https://fullnode.testnet.sui.io:443` |
| **mainnet** | Official production environment | `https://fullnode.mainnet.sui.io:443` |

```bash
# Switch to different networks
sui client switch --env testnet
sui client switch --env mainnet

# View current network
sui client envs
sui client active-env

# View account balance
sui client balance
```

### Environment Switching in dApp

```typescript
// Control which network dApp connects to via environment variables
const RPC_URL = import.meta.env.VITE_SUI_RPC_URL
  ?? 'https://fullnode.testnet.sui.io:443'

const WORLD_PACKAGE = import.meta.env.VITE_WORLD_PACKAGE
  ?? '0x...' // testnet package id

const client = new SuiClient({ url: RPC_URL })
```

The easiest error in environment switching is not the commands themselves, but "half-switching":

- CLI already switched to mainnet
- Frontend still reading testnet
- Wallet connected to another environment
- Documentation and announcements still have old Package ID

Once this half-switched state appears, superficial symptoms are usually confusing:

- Contract looks successfully published, but frontend doesn't recognize it
- User wallet can connect, but objects can't be found
- Works locally for yourself, but not in others' environments

So what really needs verification is not "something somewhere changed," but "all entry points point to the same environment."

---

##  23.3 Testnet to Mainnet Considerations

- **Package ID will change**: New Package ID after Mainnet publish, dApp config needs updating
- **Data not universal**: Objects created on Testnet (characters, components) don't exist on Mainnet, need re-initialization
- **Gas fees are real**: SUI on Mainnet has real value, publishing and operations consume real Gas
- **Irreversible**: Shared objects (`share_object`) cannot be withdrawn

### From testnet to mainnet, be most wary of "mental copying"

Many teams subconsciously think:

- Flow worked on testnet
- So mainnet is just "repeating it once"

Actually not. The biggest difference between mainnet and testnet is not just asset value, but:

- User expectations are higher
- Error costs are higher
- Rollback space is smaller
- Community trust is more fragile

So before mainnet launch, you should treat yourself as launching a product, not submitting an assignment.

---

##  23.4 Package Upgrade Best Practices

### Securely Store UpgradeCap

`UpgradeCap` is the most sensitive permission object; losing it means you cannot upgrade the contract:

```bash
# View your UpgradeCap
sui client objects --json | grep -A5 "UpgradeCap"
```

**Storage Strategy:**
1. **Multisig Address**: Transfer UpgradeCap to 2/3 multisig address, prevent single point of failure
2. **Timelock**: Can add timelock mechanism, upgrades require advance announcement
3. **Burn** (extreme case): If contract confirmed to never need upgrades, can burn UpgradeCap to completely guarantee immutability

```typescript
// Transfer UpgradeCap to multisig address
const tx = new Transaction()
tx.transferObjects(
  [tx.object(UPGRADE_CAP_ID)],
  tx.pure.address(MULTISIG_ADDRESS)
)
```

### Why is UpgradeCap one of the most dangerous objects post-deployment?

Because it controls not a single transaction, but the entire protocol's future form.

If poorly managed, two extreme risks occur:

- **Stolen**
  Attacker can publish malicious upgrades
- **Lost**
  You permanently lose upgrade capability

Both are not ordinary business bugs, but protocol-level incidents.

### Version Management

Recommend maintaining version numbers in contracts:

```move
const CURRENT_VERSION: u64 = 2;

public struct VersionedConfig has key {
    id: UID,
    version: u64,
    // ... config fields
}

// Call migration function when upgrading
public fun migrate_v1_to_v2(
    config: &mut VersionedConfig,
    _cap: &UpgradeCap,
) {
    assert!(config.version == 1, EMigrationNotNeeded);
    // ... execute data migration
    config.version = 2;
}
```

### Version numbers are not decoration

Their real purpose is to help you clearly answer:

- Which semantic version is this object currently in
- Which set of fields should frontend and scripts interpret it by
- Whether migration logic needs to be triggered

Otherwise, once old objects and new logic coexist in production, you'll quickly fall into the debugging hell of "is the data broken or is the code broken."

---

##  23.5 dApp Deployment and Hosting

### Static Deployment (Recommended)

```bash
# Build production version
npm run build

# Deploy to Vercel (automatic CI/CD)
vercel --prod

# Or deploy to GitHub Pages
gh-pages -d dist
```

**Recommended Platforms:**
| Platform | Features |
|------|------|
| **Vercel** | Automatic CI/CD, simple config, ample free tier |
| **Cloudflare Pages** | Global CDN, supports KV storage extensions |
| **IPFS/Arweave** | Truly decentralized deployment, permanent storage |

### Environment Variable Configuration

```bash
# .env.production
VITE_SUI_RPC_URL=https://fullnode.mainnet.sui.io:443
VITE_WORLD_PACKAGE=0x_MAINNET_WORLD_PACKAGE_
VITE_MY_PACKAGE=0x_MAINNET_MY_PACKAGE_
VITE_TREASURY_ID=0x_MAINNET_TREASURY_ID_
```

### The most underestimated problem in frontend deployment: cache and old links

After on-chain code is published, the frontend won't necessarily switch over as you expect. You also need to consider:

- CDN cache
- Browser cache
- Users' bookmarked old links
- Third-party pages referencing old domains or old parameters

That is, frontend deployment isn't "upload new package and done," you also need to ensure users truly enter the new version entry point.

---

##  23.6 Builder Positioning and Constraints in EVE Frontier

Understanding Builder boundaries is critical for long-term success:

### What You Can Do (Layer 3)

- ✅ Write custom extension logic (Witness pattern)
- ✅ Build new economic mechanisms (markets, auctions, tokens)
- ✅ Create frontend dApp interfaces
- ✅ Add custom rules on existing facility types
- ✅ Compose with other Builders' contracts

### What You Cannot Change (Layer 1 & 2)

- ❌ Modify core game physics rules (location, energy system)
- ❌ Create brand new facility types (only CCP can do)
- ❌ Access unpublished Admin operations
- ❌ Bypass AdminACL's server verification requirements

### Design Technique: Find Space Within Constraints

```
Official Limitation: Stargates can only control passage via JumpPermit
Your Extension Space:
  ├── Permit validity period (time control)
  ├── Permit acquisition conditions (paid/hold NFT/quest completion)
  ├── Permit secondary market (resell passes)
  └── Permit bulk purchase discounts
```

The correct mindset for understanding constraints is not complaining "why don't you give me more permissions," but:

> Within fixed world rules, find sufficiently large product design space.

Truly mature Builders often don't want to change the world's foundation, but excel at building on existing interfaces:

- Stronger operational mechanisms
- Clearer permission design
- Better user experience
- Higher compositional value

---

##  23.7 Community Collaboration and Contribution

### Composability: Your Contracts Can Be Used by Others

When you publish a market contract, other Builders can:
- Integrate your price oracle into their pricing systems
- Add referral commissions on top of your market
- Use your token as payment for their services

**Design Recommendation**: Expose necessary read interfaces to make your contract ecosystem-friendly:

```move
// Expose query interfaces for other contracts to call
public fun get_current_price(market: &Market, item_type_id: u64): u64 {
    // Return current price, other contracts can use for pricing reference
}

public fun is_item_available(market: &Market, item_type_id: u64): bool {
    table::contains(&market.listings, item_type_id)
}
```

### Contributing to Official Documentation

EVE Frontier documentation is open source:

```bash
# Clone documentation repo
git clone https://github.com/evefrontier/builder-documentation.git

# Create branch, add your tutorial or corrections
git checkout -b feat/add-auction-tutorial

# Submit PR
```

Contribution content includes:
- Find and fix documentation errors
- Supplement missing example code
- Translate documentation to other languages
- Share your best practice cases

### Why community collaboration is not "icing on cake"

Because the true compound interest of the Builder ecosystem comes from reuse:

- You expose read interfaces, others can integrate
- Others expose best practices, you avoid many pitfalls
- Once documentation is more accurate, entire ecosystem's development efficiency rises

Direct returns for yourself too:

- Easier to be integrated
- Easier to build reputation
- Easier to get early users and feedback

### Code of Conduct

All Builders must comply:
- ❌ Prohibited to harass or maliciously attack other players via programming infrastructure
- ❌ Prohibited deceptive economic behavior (like honeypot contracts)
- ✅ Encourage fair competition and transparent mechanisms
- ✅ Encourage collective knowledge and tool sharing

---

##  23.8 Sustainable Builder Strategy

### Economic Sustainability

```
Revenue Source Design:
  ├── Transaction fees (1-3% of market trades)
  ├── Subscription services (monthly LUX subscription)
  ├── Premium features (paid unlock)
  └── Alliance service contracts (B2B)

Cost Control:
  ├── Use read APIs (GraphQL/gRPC) instead of high-frequency on-chain writes
  ├── Aggregate multiple operations into single transaction
  └── Utilize sponsored transactions to reduce user friction
```

### Technical Sustainability

- **Modular Design**: Split functionality into independent modules for independent upgrades
- **Backward Compatibility**: New versions prioritize compatibility with old version data
- **Documentation-Driven**: Document your own contract APIs for easy integration by others
- **Monitoring & Alerting**: Subscribe to key events, get notified when anomalies occur

### Technical and economic sustainability must be viewed together

Many projects die not because technology can't be done or no revenue, but because the two sides disconnect:

- Many features, but maintenance costs too high
- Revenue looks decent, but relies entirely on manual operations
- Users can get in, but no retention reason

So a sustainable Builder project typically satisfies simultaneously:

- Pricing model simple and explainable
- Permissions and operations won't drag you down
- New versions can evolve smoothly
- Someone can respond quickly when critical issues appear

### What really should be recorded long-term is not "how many versions released"

But these operational facts:

- How many real users completed key actions
- Which step has highest churn
- Which types of transactions fail most
- Which features almost nobody uses

This data will ultimately decide what you should continue doing and what you shouldn't.

---

##  23.9 Future of EVE Frontier Ecosystem

According to official documentation, the following features may be opened to Builders in the future:
- **More Component Types**: Programming interfaces for industrial facilities like refineries, manufacturing plants
- **Zero-Knowledge Proofs**: Use ZK proofs to replace server signatures for proximity verification, achieve full decentralization
- **Richer Economic Interfaces**: More official LUX/EVE Token interaction interfaces

**Design Principle**: Design for extensibility. Today's contracts should be able to seamlessly integrate after tomorrow's new features launch through upgrades.

The most realistic advice here is not "bet on all future directions," but:

- First thoroughly master today's truly implementable component capabilities
- Then leave evolution space for future interface changes

That is, future-readiness shouldn't come from "writing many conceptual interfaces not yet usable," but from:

- Object structures not hardcoded
- Config and policy leave upgrade positions
- Frontend doesn't interpret on-chain fields too rigidly

---

## 🔖 Chapter Summary

| Knowledge Point | Core Takeaway |
|--------|--------|
| Deployment process | localnet → testnet → mainnet three phases |
| Network switching | `sui client switch --env mainnet` |
| UpgradeCap security | Multisig storage, consider timelock |
| dApp deployment | Vercel/Cloudflare Pages + environment variables |
| Builder constraints | Layer 3 free extension, Layer 1/2 unchangeable |
| Community collaboration | Open APIs, contribute docs, follow code of conduct |
| Sustainability strategy | Diverse revenue + modular + monitoring |

## 📚 Further Reading

- [Builder Constraints Documentation](https://github.com/evefrontier/builder-documentation/blob/main/welcome/contstraints.md)
- [Contributing Guide](https://github.com/evefrontier/builder-documentation/blob/main/CONTRIBUTING.md)
- [Sui Package Upgrades](https://docs.sui.io/guides/developer/packages/upgrade)
- [EVE Frontier Development Roadmap (community channels)]
