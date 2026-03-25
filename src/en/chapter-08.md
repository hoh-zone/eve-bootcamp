# Chapter 8: Sponsored Transactions & Server-Side Integration

> **Goal:** Deeply understand EVE Frontier's sponsored transaction mechanism, master how to build backend services for business logic validation and Gas payment on behalf of players, achieving frictionless gameplay experiences.

---

> Status: Engineering chapter. Main content focuses on sponsored transactions, server-side validation, and on-chain/off-chain coordination.

## 8.1 What are Sponsored Transactions?

In regular Sui transactions, the **sender** and **gas owner** are the same person. Sponsored transactions allow these two roles to be separated:

```
Regular transaction:  Player signs + Player pays Gas
Sponsored transaction:  Player signs intent + Server validates + Server pays Gas
```

**Critical for EVE Frontier** because:
- Certain operations require **game server validation** (such as proximity proofs, distance checks)
- Lowers player **entry barrier** (no need to pre-fund SUI for Gas)
- Enables **business-level risk control**: Server can reject invalid requests

The real key here isn't simply "who pays Gas for whom," but rather:

> Sponsored transactions break down a player action into three stages: "user intent + server review + on-chain execution."

This makes many product experiences possible that were previously very difficult:

- Players don't need to prepare SUI in advance
- Server can make business judgments before going on-chain
- Risk control can happen before signing, rather than remedying after asset incidents

But the cost is also clear: your system is no longer just frontend + contract, but formally becomes a "on-chain/off-chain coordinated system."

---

## 8.2 AdminACL: Game Server's Permission Object

EVE Frontier uses the `AdminACL` shared object to manage which server addresses are authorized as sponsors:

```
GovernorCap
    └──(manages) AdminACL (shared object)
                └── sponsors: vector<address>
                    ├── Game Server 1 address
                    ├── Game Server 2 address
                    └── ...
```

Operations requiring server participation (like jumping) have checks like this in the contract:

```move
public fun verify_sponsor(admin_acl: &AdminACL, ctx: &TxContext) {
    // tx_context::sponsor() returns the Gas payer's address
    let sponsor = ctx.sponsor().unwrap(); // aborts if no sponsor
    assert!(
        vector::contains(&admin_acl.sponsors, &sponsor),
        EUnauthorizedSponsor,
    );
}
```

This means: even if a player constructs a valid transaction themselves, calling functions like `jump_with_permit` will abort without an authorized server signature.

### What does `AdminACL` really express?

It doesn't express "this server can technically sign," but rather:

> This server is officially trusted by the world rules to vouch for certain sensitive actions.

This is fundamentally different from regular backend services. In many Web applications, the backend just helps you make business judgments; here, the backend is part of the on-chain permission model itself.

So once `AdminACL` management becomes chaotic, it affects not a single interface, but the entire chain of trust:

- Who can sponsor payments
- Who can vouch for proximity proofs
- Who can initiate certain restricted actions

---

## 8.3 Complete Sponsored Transaction Flow

```
   Player                    Your Backend Service                   Sui Network
    │                          │                            │
    │── 1. Build Transaction ──►│                            │
    │   (setSender = player addr)│                            │
    │                          │                            │
    │◄── 2. Backend validates ──│                            │
    │   (check proximity, balance, etc.)                     │
    │                          │                            │
    │── 3. Player signs (Sender)──►│                            │
    │                          │                            │
    │                          │── 4. Server signs (Gas) ───►│
    │                          │   (setGasOwner = server)   │
    │                          │                            │
    │◄─────────────────────────┼── 5. Transaction result ───│
```

### What does each segment in this chain protect against?

- **Player builds transaction**
  Prevents server from arbitrarily fabricating intent on user's behalf
- **Backend validates business logic**
  Prevents requests that don't meet conditions from going directly on-chain
- **Player signature**
  Proves this is indeed a user-authorized action
- **Server signature**
  Proves the platform is willing to sponsor and vouch for this action

All four segments are indispensable. Missing one leads to typical problems:

- No player signature: platform can send on behalf of users arbitrarily
- No backend validation: anyone can freeload sponsorship
- No server signature: restricted on-chain entry points fail directly

---

## 8.4 Building a Simple Backend Sponsorship Service

### Project Structure

```
backend/
├── src/
│   ├── server.ts          # Express server
│   ├── sponsor.ts          # Sponsorship transaction logic
│   ├── validators.ts       # Business validation
│   └── config.ts           # Configuration
└── package.json
```

### `sponsor.ts`: Core Sponsorship Logic

```typescript
// src/sponsor.ts
import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import { fromBase64 } from "@mysten/sui/utils";

const client = new SuiClient({
  url: process.env.SUI_RPC_URL ?? "https://fullnode.testnet.sui.io:443",
});

// Server signing key (securely stored in environment variables)
const serverKeypair = Ed25519Keypair.fromSecretKey(
  fromBase64(process.env.SERVER_PRIVATE_KEY!)
);

export interface SponsoredTxRequest {
  txBytes: string;         // Player-built transaction (base64)
  playerSignature: string; // Player's signature on txBytes (base64)
  playerAddress: string;
}

export async function sponsorAndExecute(req: SponsoredTxRequest) {
  // 1. Deserialize player's transaction
  const txBytes = fromBase64(req.txBytes);

  // 2. Server sets Gas payer
  //    This modifies the transaction to make the server address the Gas payer
  const tx = Transaction.from(txBytes);
  tx.setGasOwner(serverKeypair.getPublicKey().toSuiAddress());

  // 3. Server signs (as Gas payer)
  const sponsoredBytes = await tx.build({ client });
  const serverSig = await serverKeypair.signTransaction(sponsoredBytes);

  // 4. Execute: submit both player signature and server signature
  const result = await client.executeTransactionBlock({
    transactionBlock: sponsoredBytes,
    signature: [
      req.playerSignature,  // Player's signature as Sender
      serverSig.signature,  // Server's signature as Gas Owner
    ],
    options: { showEvents: true, showEffects: true },
  });

  return result;
}
```

### What the server needs to guard against most isn't "request failure" but "request abuse"

A truly usable sponsorship service should at least consider these risk control points:

- Same player repeating requests in short time
- Same transaction being submitted repeatedly
- Certain high-cost operations being batch-scraped
- Players sneaking in transactions that shouldn't be sponsored

So in real projects, sponsorship services usually also add:

- Request rate limiting
- Transaction whitelists or entry whitelists
- Budget limits per action
- Request logging and audit trails

### `validators.ts`: Business Validation Logic

```typescript
// src/validators.ts
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: process.env.SUI_RPC_URL! });

// Validate proximity (simplified: check if two components' game coordinates are close enough)
export async function validateProximity(
  playerAddress: string,
  assemblyId: string,
): Promise<boolean> {
  // In real scenarios, this would query game server or on-chain location hash
  // This is just an example implementation
  try {
    const assembly = await client.getObject({
      id: assemblyId,
      options: { showContent: true },
    });

    // Check if player is near component (game physics rule validation)
    // Real implementation needs to communicate with game server
    return true; // Simplified
  } catch {
    return false;
  }
}

// Validate if player meets conditions (e.g., holds specific NFT)
export async function validatePlayerCondition(
  playerAddress: string,
  requiredNftType: string,
): Promise<boolean> {
  const objects = await client.getOwnedObjects({
    owner: playerAddress,
    filter: { StructType: requiredNftType },
  });

  return objects.data.length > 0;
}
```

### Why shouldn't validation logic be mixed with execution logic?

Because these two things change at different rates:

- Validation rules iterate frequently
- Execution pathways need to remain as stable as possible

By separating them, you get several direct benefits:

- Risk control rules are easier to update independently
- Easier to compose different validators for different actions
- Easier to do gradual rollouts and replay analysis

### `server.ts`: REST API Server

```typescript
// src/server.ts
import express from "express";
import { sponsorAndExecute, SponsoredTxRequest } from "./sponsor";
import { validateProximity, validatePlayerCondition } from "./validators";

const app = express();
app.use(express.json());

// Sponsor jump request
app.post("/api/sponsor/jump", async (req, res) => {
  const { txBytes, playerSignature, playerAddress, gateId } = req.body;

  try {
    // 1. Validate proximity (player must be near stargate)
    const isNear = await validateProximity(playerAddress, gateId);
    if (!isNear) {
      return res.status(400).json({ error: "Player not near stargate" });
    }

    // 2. Execute sponsored transaction
    const result = await sponsorAndExecute({
      txBytes,
      playerSignature,
      playerAddress,
    });

    res.json({ success: true, digest: result.digest });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// Sponsor general action (with custom validation)
app.post("/api/sponsor/action", async (req, res) => {
  const { txBytes, playerSignature, playerAddress, actionType, metadata } = req.body;

  try {
    // Different validation based on actionType
    switch (actionType) {
      case "deposit_ore": {
        // Validate near storage box
        const ok = await validateProximity(playerAddress, metadata.ssuId);
        if (!ok) return res.status(400).json({ error: "Not nearby" });
        break;
      }
      case "special_gate": {
        // Validate holding VIP NFT
        const hasNft = await validatePlayerCondition(
          playerAddress,
          `${process.env.MY_PACKAGE}::vip_pass::VipPass`
        );
        if (!hasNft) return res.status(403).json({ error: "VIP pass required" });
        break;
      }
    }

    const result = await sponsorAndExecute({ txBytes, playerSignature, playerAddress });
    res.json({ success: true, digest: result.digest });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3001, () => console.log("Sponsorship service running on :3001"));
```

### Idempotency is the most easily overlooked issue in sponsorship services

Player network jitter, frontend retries, users frantically clicking buttons—all can cause the same request to be sent multiple times.

If your backend doesn't have idempotency design, you'll see:

- Same business request being sponsored repeatedly
- Users think they clicked once, but two transactions went on-chain
- Budgets and statistics all become distorted

In real projects, you should at least give each business action a stable request ID and record server-side whether "this request has already been processed."

---

## 8.5 Frontend Integration with Sponsored Transactions

```tsx
// src/hooks/useSponsoredAction.ts
import { useWallet } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";
import { toBase64 } from "@mysten/sui/utils";

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL ?? "http://localhost:3001";

export function useSponsoredAction() {
  const wallet = useWallet();

  const executeSponsoredJump = async (
    tx: Transaction,
    gateId: string,
  ) => {
    if (!wallet.currentAccount) throw new Error("Please connect wallet");

    const playerAddress = wallet.currentAccount.address;

    // 1. Player only signs, doesn't submit
    const txBytes = await tx.build({ client: suiClient });
    const { signature: playerSig } = await wallet.signTransaction({
      transaction: tx,
    });

    // 2. Send to backend, let server validate and sponsor Gas
    const response = await fetch(`${BACKEND_URL}/api/sponsor/jump`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        txBytes: toBase64(txBytes),
        playerSignature: playerSig,
        playerAddress,
        gateId,
      }),
    });

    if (!response.ok) {
      const { error } = await response.json();
      throw new Error(error);
    }

    return response.json();
  };

  return { executeSponsoredJump };
}
```

---

## 8.6 Security Considerations for Sponsored Transactions

| Risk | Defense Measures |
|------|--------|
| Server private key leak | Use HSM or KMS to store private keys; rotate regularly |
| Malicious players replaying transactions | Sui's TransactionDigest is unique, cannot be replayed |
| DDoS attacks on backend | Rate limiting + IP blocking + require player auth |
| Bypassing validation to submit directly | On-chain contract's `verify_sponsor` enforces authorized address requirement |
| Gas depletion | Monitor server account balance, set alert thresholds |

---

## 8.7 `@evefrontier/dapp-kit` Built-in Sponsorship Support

The official SDK has built-in support for sponsored transactions:

```typescript
import { signAndExecuteSponsoredTransaction } from "@evefrontier/dapp-kit";

// SDK automatically communicates with EVE Frontier backend to complete sponsorship
const result = await signAndExecuteSponsoredTransaction({
  transaction: tx,
  // No need to manually handle signatures and backend communication
});
```

**Applicable scenarios**: Official game operations (like component online/offline, warehouse transfers) can typically use the official sponsorship service.

**When you need to build your own backend**: When your extension contracts need custom business validation (like checking NFT holdings, in-game conditions), you need to deploy your own sponsorship service.

---

## Summary

| Knowledge Point | Core Concept |
|--------|--------|
| Sponsored transaction essence | Sender (player) and Gas Owner (server) are separated |
| AdminACL | Game contract verifies `ctx.sponsor()` must be in authorized list |
| Backend service responsibilities | Business validation + server signature + merged signature submission |
| Security essentials | Private key protection + Rate Limiting + contract-level safeguards |
| SDK support | `signAndExecuteSponsoredTransaction()` handles official scenarios |

## Further Reading

- [Interfacing with the World](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [Sui Sponsored Transactions Documentation](https://docs.sui.io/guides/developer/advanced/sponsored-transactions)
- [ownership-model.md](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/ownership-model.md)
