# Chapter 33: EVE Vault Wallet Overview — zkLogin Principles and Design

> **Learning Objective**: Understand what EVE Vault is, why it uses zkLogin instead of traditional private keys, and the complete cryptographic working principles of zkLogin.

---

> Status: Source code guide. Cryptographic details based on current EVE Vault implementation and Sui zkLogin mechanism; text emphasizes architectural understanding.

## Minimal Call Chain

`FusionAuth/OAuth login -> Callback get code -> Exchange token -> Derive zkLogin address -> Save login state -> Wallet can sign`

## Corresponding Code Directory

- [evevault](https://github.com/evefrontier/evevault)

## 1. What is EVE Vault?

EVE Vault is EVE Frontier's dedicated **Chrome browser extension wallet**, built on the following tech stack:

| Layer | Technology | Purpose |
|----|------|------|
| Extension Framework | WXT + Chrome MV3 | Cross-browser extension building |
| UI Framework | React + TanStack Router | Popup and approval pages |
| State Management | Zustand + Chrome Storage | Persist user state |
| Blockchain | Sui Wallet Standard | dApp discovery and interaction protocol |
| Identity Auth | EVE Frontier FusionAuth (OAuth) | EVE game account login |
| Address Derivation | Sui zkLogin + Enoki | Derive on-chain address from OAuth identity |

**Core Design Philosophy**: Players don't need to manage private keys — log in with EVE Frontier game account, automatically get Sui blockchain address.

The most important thing in this chapter isn't memorizing cryptographic terms, but first seeing clearly who it's solving what problem for:

- For players: Lower wallet barrier
- For Builders: Lower onboarding cost
- For product: Consolidate "game identity" and "on-chain identity" into one experience chain as much as possible

---

## 2. Why Not Use Traditional Private Keys?

Pain points of ordinary Sui wallets:

```
❌ Players need to safeguard mnemonic phrase (12-24 words)
❌ Mnemonic leak = total asset loss
❌ Game account and on-chain identity are two independent systems
❌ Extremely high learning curve for new users
```

EVE Vault's solution:

```
✅ Use EVE Frontier game account (email login) to directly correspond to on-chain address
✅ Address deterministically derived by zero-knowledge proof (zkLogin)
✅ Even if OAuth token stolen, needs ZK proof to sign
✅ Game account = on-chain identity, seamless user experience
```

### Real Product Significance Here

Not "more advanced," but letting vast numbers of players who wouldn't install traditional wallets also enter on-chain interactions.

For EVE Builders, this directly affects:

- How short connection flow can be
- How low first-use psychological cost is
- Whether sponsored transactions can remove last layer of friction

---

## 3. zkLogin Principles Deep Dive

###  3.1 Core Concepts

zkLogin is a signature scheme natively supported by Sui that binds OAuth identity to blockchain address:

```
【Traditional Wallet】
Private key k → Public key PK → Address A
               Signature = ed25519_sign(k, tx)

【zkLogin Wallet】
JWT (OAuth token) + Ephemeral Key → ZK Proof → Signature
                                              ↑
                  This proof proves "I hold valid JWT and JWT corresponds to address A"
```

###  3.2 zkLogin Address Formula

```
zkLogin_address = hash(
    iss,          // JWT issuer (like "https://auth.evefrontier.com")
    sub,          // User's unique ID (EVE account ID)
    aud,          // OAuth client ID
    user_salt,    // User salt saved by Enoki (prevent sub leaking link to on-chain identity)
)
```

**Key Security**: Even if attacker knows your EVE account ID, without `user_salt` cannot calculate your on-chain address. `user_salt` is kept by Enoki (Mysten Labs' zkLogin service).

### Most Important zkLogin Intuition

Not "I have a long-term private key," but:

> I use OAuth identity to prove "who I am," then use ephemeral key to prove "this operation is authorized by me."

This is why zkLogin system has simultaneously:

- JWT
- salt
- Ephemeral key
- ZK proof

They each prove different things.

###  3.3 Ephemeral Key Pair

zkLogin uses an ephemeral key pair to perform actual signing:

```
Login flow:
1. Generate ephemeral ed25519 key pair (validity = Sui Epoch, ~24h)
2. Embed ephemeral public key's nonce into OAuth request
3. OAuth server returns JWT containing nonce in token
4. Sign transaction with ephemeral private key
5. Submit ZK proof + ephemeral signature → Sui verifies
```

Ephemeral private key stored in EVE Vault's **Keeper security container** (see Chapter 34).

### Why Must Have Ephemeral Key?

Because zkLogin doesn't directly turn OAuth token into signer. Ephemeral key's role is connecting "login state" and "specific signing action," while limiting risk window to relatively short period.

###  3.4 ZK Proof Generation

```typescript
// packages/shared/src/wallet/zkProof.ts
interface ZkProofParams {
    jwtRandomness: string;      // Random salt, prevent nonce derivation
    maxEpoch: string;           // Ephemeral key's max valid Epoch
    ephemeralPublicKey: PublicKey; // Ephemeral public key (embedded in JWT nonce)
    idToken: string;            // JWT obtained from FusionAuth
    enokiApiKey: string;        // Enoki service key
    network?: string;           // devnet | testnet | mainnet
}
```

ZK Proof generation steps:
1. Collect above parameters
2. Call Sui ZK Prover endpoint (Enoki hosted)
3. Return ZK proof containing `proofPoints`, `issBase64Details`, `headerBase64`

###  3.5 JWT Nonce Construction

zkLogin's most critical design is "embedding" ephemeral public key into JWT, achieved through `nonce` field:

```typescript
// nonce = poseidon_hash(ephemeral_public_key, max_epoch, randomness)
// This step completed before requesting OAuth
const nonce = generateNonce(ephemeralPublicKey, maxEpoch, randomness);

// Pass nonce in OAuth URL
const authUrl = `${fusionAuthUrl}/oauth2/authorize?`
    + `client_id=${CLIENT_ID}`
    + `&response_type=code`
    + `&nonce=${nonce}`   // ← FusionAuth will put this nonce into JWT
    + `&scope=openid+profile+email`;
```

FusionAuth includes in returned JWT (`id_token`):
```json
{
    "iss": "https://auth.evefrontier.com",
    "sub": "user-12345",          ← EVE account unique ID
    "aud": "your-client-id",
    "nonce": "H5SmVjkG...",       ← Contains ephemeral public key info
    "exp": 1712345678
}
```

Sui's ZK verifier confirms signature truly comes from that ephemeral key pair by checking ephemeral public key embedded in `nonce`.

###  3.6 zkLogin Address TypeScript Calculation

```typescript
import { computeZkLoginAddress } from "@mysten/sui/zklogin";

// Get user_salt and address from Enoki API
const { address, salt } = await fetch("https://api.enoki.mystenlabs.com/v1/zklogin", {
    method: "POST",
    headers: { "Authorization": `Bearer ${ENOKI_API_KEY}` },
    body: JSON.stringify({ jwt: idToken }),
}).then(r => r.json());

// Verify: compute address locally (same as Enoki-returned address)
const localAddress = computeZkLoginAddress({
    claimName: "sub",
    claimValue: decodedJwt.sub,    // EVE account ID
    iss: decodedJwt.iss,
    aud: decodedJwt.aud,
    userSalt: BigInt(salt),
});

console.assert(address === localAddress);
```

---

## 4. EVE Vault Authentication Flow

```
User clicks "Sign in with EVE Vault"
    │
    ▼
Generate ephemeral Ed25519 key pair + JWT Nonce
    │
    ▼
Open FusionAuth OAuth page (chrome.identity API)
    │
    ▼
User logs in with EVE Frontier account
    │
    ▼
FusionAuth returns JWT (containing nonce)
    │
    ▼
Call Enoki API → Get user_salt + zkLogin address
    │
    ▼
Call ZK Prover → Generate ZK Proof
    │
    ▼
Popup displays zkLogin address + SUI balance
    │
    ▼
dApp calls wallet.connect() → Get address → Can send transactions
```

### Most Critical in This Flow Isn't Many Steps, But Clear Responsibilities

- FusionAuth responsible for confirming who user is
- Enoki responsible for assisting zkLogin address and salt
- Prover responsible for generating verifiable proof
- Vault responsible for organizing these into wallet capability

Once you separate each layer's responsibilities, this mechanism won't seem mysterious.

---

## 5. Multi-Network Support

EVE Vault supports connecting to multiple testnets simultaneously, can switch anytime:

```typescript
// packages/shared/src/types/wallet.ts
export class EveVaultWallet implements Wallet {
    #currentChain: SuiChain = SUI_TESTNET_CHAIN;

    get chains(): Wallet["chains"] {
        return [SUI_TESTNET_CHAIN, SUI_DEVNET_CHAIN] as `sui:${string}`[];
    }
    // ...
}
```

Network switcher in popup's bottom-left corner lets players switch between Devnet (development testing) and Testnet (demo/pre-launch), after switching address same (because derivation formula doesn't contain network parameter), but queried nodes will switch.

---

## 6. EVE Vault vs Traditional Sui Wallet Comparison

| Feature | Sui Wallet / OKX | EVE Vault |
|------|-----------------|-----------|
| Need mnemonic | ✅ Yes | ❌ No |
| Based on OAuth login | ❌ No | ✅ Yes (EVE account) |
| Private key storage location | User local | No private key (zkLogin) |
| Address determinism | Depends on private key | JWT + salt deterministic derivation |
| Signature scheme | ed25519 / secp256k1 | zkLogin (ZK Proof + ephemeral signature) |
| Sponsored transactions | Partial support | ✅ EVE Frontier native support |
| dApp discover | Wallet Standard | Wallet Standard + EVE extension features |

---

## 7. Security Model

### Keeper Mechanism

Ephemeral private key not stored in `chrome.storage` (readable by JS), but in **Keeper** (isolated hidden document):

```
┌─────────────────────────────────────────┐
│  Chrome Extension Sandbox                │
│                                          │
│  Background Service Worker               │
│      ↕ chrome.runtime.sendMessage       │
│  Keeper (hidden iframe/document)         │
│      ← Ephemeral private key only in this memory │
│      ← Not written to chrome.storage    │
│      ← Cleared when browser closes      │
└─────────────────────────────────────────┘
```

### Lock Mechanism

After browser closes or period of inactivity, Keeper automatically clears ephemeral private key ("locked" state). Unlocking requires regenerating ZK Proof (cached, usually completes in seconds).

---

## 8. Significance for Builders

As Builder, your dApp users will connect through EVE Vault, key impacts:

1. **No private key management UX**: Users directly connect with game account, lower onboarding barrier
2. **Sponsored transaction native support**: EVE Vault implements `sign_sponsored_transaction`, Builder can pay Gas for users
3. **Address stability**: Player's on-chain address bound to their EVE account, won't change due to "device change"
4. **Multi-network**: Development uses Devnet, launch uses Testnet, address unchanged

---

## Chapter Summary

| Concept | Key Points |
|------|------|
| zkLogin | Passwordless zero-knowledge signature scheme based on OAuth JWT |
| `user_salt` | Kept by Enoki, prevents OAuth ID linking to on-chain address |
| Ephemeral key pair | Regenerated each Epoch, Keeper security container storage |
| ZK Proof | Requested from Enoki, proves "legitimate JWT holder" |
| FusionAuth | EVE Frontier's OAuth identity provider |

> Next Chapter: **EVE Vault Technical Architecture and Development Deployment** — Chrome MV3's 5 script layers, message communication protocol, and how to locally build and load extension.
