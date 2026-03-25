# Chapter 10: EVE Vault & dApp Integration Practices

> **Learning Objectives**: Master the complete process of integrating EVE Vault into Builder dApps—account discovery, connection, transaction signing, sponsored transactions, and handling zkLogin-specific Epoch refresh and disconnection scenarios.

---

> Status: Teaching example. API descriptions in the text are based on current dependency versions and example dApps in this repository. Verify against local package versions during actual integration.

## Minimal Call Chain

`dApp Provider initialization -> useConnection wallet discovery -> Build PTB -> EVE Vault approval/signing -> On-chain execution -> dApp refresh object state`

## Wallet Capability Matrix

| Capability | Standard Wallet Standard Wallet | EVE Vault |
|------|------|------|
| Discovery & Connection | Supported | Supported |
| Regular Transaction Signing | Supported | Supported |
| Sponsored Tx | Usually not supported | Supported |
| zkLogin / Epoch Handling | Depends on wallet implementation | Built-in handling |
| In-game overlay integration | Usually none | Can cooperate with EVE Frontier scenarios |

This table isn't for advertising, but to remind you: the integration layer must first detect wallet capabilities, then decide whether to show sponsored transaction entry points.

The real awareness this chapter should establish is:

> Wallet integration isn't just "connect and done," but requires designing complete interaction fallback paths according to wallet capability differences.

In other words, your dApp cannot assume all wallets are equivalent.

## Exception Handling Sequence

When users report "wallet connects but transactions won't send," check in this order:

1. First confirm if the current wallet supports Sponsored Tx
2. Then confirm network, package id, and object IDs are consistent
3. Then confirm if zkLogin proof has expired, if `maxEpoch` needs refresh
4. Finally check if frontend correctly handles disconnection and state recovery after reconnection

## Corresponding Code Directories

- [builder-scaffold/dapps](https://github.com/evefrontier/builder-scaffold/tree/main/dapps)
- [book/src/code/example-17/dapp](./code/example-17/dapp)
- [evevault](https://github.com/evefrontier/evevault)

## 1. dApp Integration Overview

Because EVE Vault implements the complete **Sui Wallet Standard**, any dApp using `@mysten/dapp-kit` or `@evefrontier/dapp-kit` can discover and connect to EVE Vault with zero configuration.

Meanwhile, EVE Vault also implements EVE Frontier's proprietary **sponsored transaction extension**, allowing Builders to pay Gas for players.

So the integration layer typically needs to answer at least three things:

- Is there currently a wallet?
- Is it currently EVE Vault?
- Does the current operation require Sponsored Tx capability?

---

## 2. Install Dependencies

```bash
# EVE Frontier dedicated SDK (recommended, includes EVE Vault sponsored transaction support)
npm install @evefrontier/dapp-kit

# Or Mysten official SDK (basic Wallet Standard, no sponsored transactions)
npm install @mysten/dapp-kit
```

---

## 3. Provider Configuration

```tsx
// src/main.tsx
import { EveFrontierProvider } from "@evefrontier/dapp-kit";
import { QueryClient } from "@tanstack/react-query";
import ReactDOM from "react-dom/client";

const queryClient = new QueryClient();

ReactDOM.createRoot(document.getElementById("root")!).render(
    <EveFrontierProvider queryClient={queryClient}>
        <App />
    </EveFrontierProvider>,
);
```

`EveFrontierProvider` automatically initializes:
- **QueryClientProvider** (React Query)
- **DAppKitProvider** (Sui client + Wallet)
- **VaultProvider** (EVE Vault connection state)
- **SmartObjectProvider** (Game object GraphQL queries)
- **NotificationProvider** (On-chain operation notifications)

The key to Provider here isn't "how many layers are wrapped," but capability ordering.

Your later connection, signing, object queries, and notification experience all depend on this initialization order being correct.

---

## 4. Connect Wallet

```tsx
import { useConnection, abbreviateAddress } from "@evefrontier/dapp-kit";
import { useCurrentAccount } from "@mysten/dapp-kit-react";

function ConnectButton() {
    const { handleConnect, handleDisconnect, isConnected, walletAddress, hasEveVault } = useConnection();
    const account = useCurrentAccount();

    if (!isConnected) {
        return (
            <div>
                <button onClick={handleConnect}>Connect EVE Vault</button>
                {!hasEveVault && (
                    <p style={{ color: "orange" }}>
                        Please install <a href="https://github.com/evefrontier/evevault/releases/latest/download/eve-vault-chrome.zip">EVE Vault extension</a>
                    </p>
                )}
            </div>
        );
    }

    return (
        <div>
            <span>Connected: {abbreviateAddress(account?.address ?? "")}</span>
            <button onClick={handleDisconnect}>Disconnect</button>
        </div>
    );
}
```

### Meaning of hasEveVault

When `hasEveVault` is `true`, it means the EVE Vault extension is installed and discovered in the wallet list. This lets you provide download link guidance to users who haven't installed it.

The most easily overlooked issue in the connection flow isn't "can the button light up," but whether the page switches to the correct state immediately after connecting:

- Is the current address refreshed?
- Are needed object queries refetched?
- Do buttons that depend on wallet capabilities switch display?

---

## 5. Send Transaction (Regular Signing)

```tsx
import { useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";
import { useConnection } from "@evefrontier/dapp-kit";

function SendTxButton() {
    const { signAndExecuteTransaction } = useDAppKit();
    const { isConnected } = useConnection();

    const handleSend = async () => {
        const tx = new Transaction();

        // Call Builder contract
        tx.moveCall({
            target: `${PACKAGE_ID}::tribe_permit::issue_jump_permit`,
            arguments: [
                tx.object(EXTENSION_CONFIG_ID),
                tx.object(SOURCE_GATE_ID),
                tx.object(DEST_GATE_ID),
                tx.object(CHARACTER_ID),
                tx.object("0x6"),  // Sui Clock (fixed object ID)
            ],
        });

        try {
            const result = await signAndExecuteTransaction({ transaction: tx });
            console.log("Transaction successful, Digest:", result.digest);
        } catch (err) {
            // EVE Vault approval popup closed by user
            if (err.message?.includes("User rejected")) {
                alert("Transaction cancelled by user");
            }
        }
    };

    return <button onClick={handleSend} disabled={!isConnected}>Issue Permit</button>;
}
```

The key to regular signing flow isn't that the code can call, but that users can understand what they're signing.

So before transaction buttons, it's best to explain as clearly as possible:

- Target object
- Key costs
- Expected results

Rather than leaving everything to the wallet approval page.

---

## 6. Sponsored Transaction (Sponsored TX)—Most Important Feature

EVE Vault is the only Sui wallet that implements `sign_sponsored_transaction`. This means Builder's server can pay Gas for players, so players don't need to hold SUI to use the dApp.

```tsx
import { useSponsoredTransaction, WalletSponsoredTransactionNotSupportedError } from "@evefrontier/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";

function SponsoredTxButton() {
    const { sponsoredSignAndExecute } = useSponsoredTransaction();

    const handleSponsoredTx = async () => {
        const tx = new Transaction();
        tx.moveCall({
            target: `${PACKAGE_ID}::my_extension::some_action`,
            arguments: [/* ... */],
        });

        try {
            // Player signs, Gas sponsored by Builder server
            const result = await sponsoredSignAndExecute({ transaction: tx });
            console.log("Sponsored transaction successful!", result.digest);
        } catch (err) {
            if (err instanceof WalletSponsoredTransactionNotSupportedError) {
                // User using non-EVE Vault wallet, fallback to regular transaction
                console.warn("Current wallet doesn't support sponsored transactions, please use EVE Vault");
                // Can fallback to signAndExecuteTransaction
            }
        }
    };

    return <button onClick={handleSponsoredTx}>Gas-free Operation (EVE Vault Sponsored)</button>;
}
```

### Builder Server-side Sponsorship Configuration

Sponsored transactions require Builder to configure a Gas sponsor account on the server side:

```typescript
// Builder backend (Node.js)
import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";

const sponsorKeypair = Ed25519Keypair.fromSecretKey(SPONSOR_PRIVATE_KEY);

// Receive player's PTB, add Gas and sign back
app.post("/sponsor-tx", async (req, res) => {
    const { serializedTx } = req.body;

    const tx = Transaction.from(serializedTx);

    // Set Gas sponsor
    tx.setSender(playerAddress);
    tx.setGasOwner(sponsorKeypair.getPublicKey().toSuiAddress());

    const sponsorSignature = await tx.sign({ signer: sponsorKeypair, client });

    res.json({ sponsorSignature, serializedTx: tx.serialize() });
});
```

The key to Sponsored Tx integration isn't "saving Gas," but "frontend-backend coordination."

It requires at least three layers working correctly together:

- Frontend can identify wallet capabilities
- Backend can correctly supplement Gas and signatures
- Wallet can complete corresponding approval process

As long as one layer's calibration is inconsistent, users will see "can connect but can't send anything out."

---

## 7. Read Game Object (Smart Object)

```tsx
import { useSmartObject } from "@evefrontier/dapp-kit";

function GateStatus({ gateItemId }: { gateItemId: string }) {
    const { assembly, character, loading, error, refetch } = useSmartObject({
        itemId: gateItemId,
    });

    if (loading) return <div>Loading...</div>;
    if (error) return <div>Error: {error.message}</div>;
    if (!assembly) return <div>Gate not found</div>;

    return (
        <div>
            <h2>{assembly.name}</h2>
            <p>Type ID: {assembly.typeId}</p>
            <p>Status: {assembly.state}</p>
            <p>Owner: {character?.name ?? "Unknown"}</p>
            <button onClick={refetch}>Refresh</button>
        </div>
    );
}
```

---

## 8. zkLogin Epoch Refresh Handling

zkLogin's temporary keypair is bound to Sui Epoch (approximately 24 hours). When Epoch expires, keys and ZK Proof need to be regenerated:

```tsx
import { useConnection } from "@evefrontier/dapp-kit";
import { useDAppKit } from "@mysten/dapp-kit-react";

function TransactionButton() {
    const { isConnected, walletAddress } = useConnection();
    const { signAndExecuteTransaction } = useDAppKit();

    const handleTransaction = async () => {
        const tx = new Transaction();
        // ...build transaction...

        try {
            await signAndExecuteTransaction({ transaction: tx });
        } catch (err) {
            const errMsg = err?.message ?? "";

            if (errMsg.includes("ZK proof") || errMsg.includes("maxEpoch")) {
                // Epoch expired, ZK Proof invalid
                // EVE Vault will automatically pop up re-verification guidance
                alert("Your login has expired, please refresh login status in EVE Vault");
            } else if (errMsg.includes("User rejected")) {
                // User cancelled transaction on approval page
                console.log("User cancelled operation");
            } else {
                console.error("Transaction failed:", errMsg);
            }
        }
    };

    return <button onClick={handleTransaction} disabled={!isConnected}>Execute Operation</button>;
}
```

---

## 9. Listen for Network Switching

EVE Vault supports users switching between Devnet/Testnet. dApp needs to respond to this change:

```tsx
import { useCurrentAccount } from "@mysten/dapp-kit-react";
import { useEffect } from "react";

function NetworkAwareComponent() {
    const account = useCurrentAccount();

    useEffect(() => {
        if (!account) return;

        // account.chains contains chains current wallet supports
        const currentChain = account.chains[0]; // "sui:testnet" or "sui:devnet"
        console.log("Current network:", currentChain);

        // Switch API endpoints or contract addresses based on network
    }, [account]);

    // ...
}
```

---

## 10. Message Signing (Personal Message)

```tsx
import { useDAppKit } from "@mysten/dapp-kit-react";
import { toBase64 } from "@mysten/sui/utils";

function SignMessageButton() {
    const { signPersonalMessage } = useDAppKit();

    const handleSign = async () => {
        const message = new TextEncoder().encode("EVE Frontier Builder Auth: " + Date.now());

        const { bytes, signature } = await signPersonalMessage({
            message,
        });

        console.log("Message signature:", signature);
        // Can send signature to server to verify user identity (link game account to builder system)
    };

    return <button onClick={handleSign}>Verify Identity with EVE Vault</button>;
}
```

---

## 11. Complete Example: Gate Extension dApp

Here's a minimal complete example integrating all features:

```tsx
// src/App.tsx
import { useConnection, useSmartObject, abbreviateAddress } from "@evefrontier/dapp-kit";
import { useDAppKit } from "@mysten/dapp-kit-react";
import { useSponsoredTransaction } from "@evefrontier/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";

const GATE_ITEM_ID = import.meta.env.VITE_GATE_ITEM_ID;
const PACKAGE_ID = import.meta.env.VITE_BUILDER_PACKAGE_ID;
const EXTENSION_CONFIG_ID = import.meta.env.VITE_EXTENSION_CONFIG_ID;

export function App() {
    const { handleConnect, handleDisconnect, isConnected, hasEveVault } = useConnection();
    const { assembly, loading } = useSmartObject({ itemId: GATE_ITEM_ID });
    const { signAndExecuteTransaction } = useDAppKit();
    const { sponsoredSignAndExecute } = useSponsoredTransaction();

    const requestJumpPermit = async () => {
        const tx = new Transaction();
        tx.moveCall({
            target: `${PACKAGE_ID}::tribe_permit::issue_jump_permit`,
            arguments: [tx.object(EXTENSION_CONFIG_ID), /* ... */],
        });
        await signAndExecuteTransaction({ transaction: tx });
    };

    const requestFreeJump = async () => {
        // Sponsored transaction version (Builder pays Gas)
        const tx = new Transaction();
        tx.moveCall({ /* same as above */ });
        await sponsoredSignAndExecute({ transaction: tx });
    };

    return (
        <div>
            {/* Top bar */}
            <header>
                <h1>Star Gate Manager</h1>
                <button onClick={isConnected ? handleDisconnect : handleConnect}>
                    {isConnected ? "Disconnect Wallet" : "Connect EVE Vault"}
                </button>
            </header>

            {/* Gate status card */}
            {!loading && assembly && (
                <div>
                    <h2>{assembly.name}</h2>
                    <p>Current status: {assembly.state}</p>
                </div>
            )}

            {/* Action buttons */}
            {isConnected && (
                <div>
                    <button onClick={requestJumpPermit}>Request Permit (Pay Gas)</button>
                    <button onClick={requestFreeJump}>Free Request (Sponsored Transaction)</button>
                </div>
            )}

            {/* EVE Vault not installed prompt */}
            {!hasEveVault && (
                <div style={{ background: "#fff3cd", padding: 12, borderRadius: 8 }}>
                    ⚠️ Please install{" "}
                    <a href="https://github.com/evefrontier/evevault/releases/latest/download/eve-vault-chrome.zip">
                        EVE Vault extension
                    </a>{" "}
                    to connect your EVE Frontier account
                </div>
            )}
        </div>
    );
}
```

---

## 12. Common Integration Issues

| Issue | Cause | Solution |
|------|------|---------|
| `WalletSponsoredTransactionNotSupportedError` | User using non-EVE Vault wallet | Catch error, fallback to regular transaction |
| Approval popup doesn't appear | Chrome blocked popup | Tell user to check block notification in top-right corner |
| `maxEpoch exceeded` | ZK Proof expired | Prompt user to refresh in EVE Vault popup |
| `hasEveVault = false` | Extension not installed or activated | Show download link and installation guide |
| Network mismatch | dApp expects testnet, wallet on devnet | Listen to account.chains, prompt user to switch network |

---

## Chapter Summary

| Feature | API |
|------|-----|
| Detect wallet installation | `useConnection().hasEveVault` |
| Connect/Disconnect | `handleConnect / handleDisconnect` |
| Regular transactions | `useDAppKit().signAndExecuteTransaction` |
| Sponsored transactions | `useSponsoredTransaction().sponsoredSignAndExecute` |
| Message signing | `useDAppKit().signPersonalMessage` |
| Read game objects | `useSmartObject({ itemId })` |
| Listen for network switching | `useCurrentAccount().chains` |

---

## Further Reading

- [EVE Vault GitHub](https://github.com/evefrontier/evevault)
- [Sui zkLogin Official Documentation](https://docs.sui.io/concepts/cryptography/zklogin)
- [Enoki Documentation](https://docs.enoki.mystenlabs.com/)
- [Sui Wallet Standard](https://docs.sui.io/standards/wallet-standard)
- [@evefrontier/dapp-kit SDK Documentation](https://sui-docs.evefrontier.com/)

> You now have mastered the complete knowledge system of the EVE Frontier Builder course: from Move 2024 basics to deep analysis of World contracts, from Builder Scaffold engineering practices to EVE Vault wallet integration. It's time to leave your mark in the stars.
