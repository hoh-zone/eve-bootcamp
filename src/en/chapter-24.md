# Chapter 24: Troubleshooting Manual (Common Errors & Debugging Methods)

> **Goal:** Systematically organize the most common error types encountered in EVE Frontier Builder development, master efficient debugging workflows, and minimize time spent "stepping on landmines."

---

> Status: Engineering support chapter. The main text focuses on troubleshooting paths and debugging habits.

## 24.1 Error Classification Overview

```
EVE Frontier Development Errors
├── Contract Errors (Move)
│   ├── Compilation errors (build failures)
│   ├── On-chain Abort (runtime failures)
│   └── Logic errors (successful execution but wrong results)
├── Transaction Errors (Sui)
│   ├── Gas issues
│   ├── Object version conflicts
│   └── Permission errors
├── dApp Errors (TypeScript/React)
│   ├── Wallet connection failures
│   ├── On-chain data reading failures
│   └── Parameter construction errors
└── Environment Errors
    ├── Docker/local node issues
    ├── Sui CLI configuration issues
    └── Missing ENV variables
```

Truly efficient troubleshooting isn't about memorizing an error encyclopedia, but about first categorizing the problem to the correct layer.

A very practical approach is to ask first:

1. Did it break before compilation, or during on-chain execution?
2. Are the objects and permissions wrong, or did the frontend construct parameters incorrectly?
3. Is the environment inconsistent, or is there actually a bug in the logic?

As long as you get the first layer classification right, subsequent troubleshooting efficiency will be much higher.

---

## 24.2 Move Compilation Errors

### Error: `unbound module`

```
error[E02001]: unbound module
  ┌─ sources/my_ext.move:3:5
  │
3 │ use world::gate;
  │     ^^^^^^^^^^^ Unbound module 'world::gate'
```

**Cause**: Missing dependency declaration for the `world` package in `Move.toml`.

**Solution:**
```toml
# Move.toml
[dependencies]
World = { git = "https://github.com/evefrontier/world-contracts.git", subdir = "contracts/world", rev = "v0.0.14" }
```

---

### Error: `ability constraint not satisfied`

```
error[E05001]: ability constraint not satisfied
   ┌─ sources/market.move:42:30
   |
42 │     transfer::public_transfer(listing, recipient);
   |                               ^^^^^^^ Missing 'store' ability
```

**Cause**: The `Listing` struct is missing the `store` ability and cannot be used with `public_transfer`.

**Solution**:
```move
// Add required ability
public struct Listing has key, store { ... }
//                            ^^^^^
```

---

### Error: `unused variable` / `unused let binding`

```
warning[W09001]: unused let binding
  = 'receipt' is bound but not used
```

**Solution**: Use underscore to ignore, or confirm if a return step (Borrow-Use-Return pattern) is missing:
```move
let (_receipt) = character::borrow_owner_cap(...); // Temporarily ignore
// Better practice: confirm return
character::return_owner_cap(own_cap, receipt);
```

### Most Useful Habit for Compilation Errors

It's not about copying and pasting errors to search, but immediately determining which category it belongs to:

- **Dependency resolution issues**
  `unbound module`
- **Type / ability issues**
  `ability constraint not satisfied`
- **Resource lifecycle issues**
  `unused let binding`, unconsumed value, borrowing conflicts

Move compiler errors are often already very close to the real cause, as long as you don't treat them as pure noise.

---

## 24.3 On-chain Abort Error Interpretation

On-chain Aborts return in the following format:
```
MoveAbort(MoveLocation { module: ModuleId { address: 0x..., name: Identifier("toll_gate_ext") }, function: 2, instruction: 6, function_name: Some("pay_toll") }, 1)
```

**Key information**: `function_name` + abort code (the number at the end).

### Common Abort Code Reference Table

| Error Code | Typical Meaning | Investigation Direction |
|---------|---------|---------|
| `0` | Insufficient permissions (`assert!(ctx.sender() == owner)`) | Check caller address vs owner stored in contract |
| `1` | Insufficient balance/quantity | Check `coin::value()` vs required amount |
| `2` | Object already exists (`table::add` duplicate key) | Check if already registered/purchased |
| `3` | Object does not exist (`table::borrow` not found) | Check if key is correct |
| `4` | Time validation failed (expired / not yet valid) | Compare `clock.timestamp_ms()` with contract logic |
| `5` | Incorrect state (e.g., already settled, not started) | Check state fields like `is_settled`, `is_online` |

### Quick Locate Abort Source

```bash
# Search for error code in source code
grep -n "assert!.*4\b\|abort.*4\b\|= 4;" sources/*.move
```

### When Encountering an Abort, First Reaction Shouldn't Be "Contract is Broken"

A more stable order is usually:

1. First look at `function_name`
2. Then look at abort code
3. Then compare against the objects, addresses, amounts, and time parameters passed in at that time

Many Aborts are not actually code bugs, but:

- Used the wrong object
- Current state doesn't meet preconditions
- Frontend assembled expired or incomplete parameters

---

## 24.4 Gas Related Issues

### `InsufficientGas` (Gas Exhausted)

```
TransactionExecutionError: InsufficientGas
```

**Solution: Step-by-step Investigation**

```typescript
// 1. First dryRun to estimate Gas
const estimate = await client.dryRunTransactionBlock({
  transactionBlock: await tx.build({ client }),
});
console.log("Gas estimate:", estimate.effects.gasUsed);

// 2. Set sufficient Gas Budget in actual transaction (+20% buffer)
const gasUsed = Number(estimate.effects.gasUsed.computationCost)
              + Number(estimate.effects.gasUsed.storageCost);
tx.setGasBudget(Math.ceil(gasUsed * 1.2));
```

### `GasBudgetTooHigh`

Your Gas Budget exceeds your account balance:
```typescript
// Query account SUI balance
const balance = await client.getBalance({ owner: address, coinType: "0x2::sui::SUI" });
const maxBudget = Number(balance.totalBalance) * 0.5; // Use max 50% of balance for Gas
tx.setGasBudget(Math.min(desired_budget, maxBudget));
```

### Gas Issues Are Easily Misdiagnosed as "Wallet Has No Money"

In reality, there are three common causes:

- Actually no money
- Gas budget set too conservatively
- The transaction model itself is too heavy

If you only know how to keep increasing the budget without looking at the cost structure in dry run results, you'll usually just mask structural problems.

---

## 24.5 Object Version Conflicts

```
TransactionExecutionError: ObjectVersionUnavailableForConsumption
```

**Cause**: Your code holds an old version object reference, but it has been modified by another transaction on-chain.

**Common scenario**: Simultaneously initiating multiple transactions using the same shared object (like `Market`).

**Solution**:
```typescript
// ❌ Wrong: Initiating multiple transactions using the same shared object in parallel
await Promise.all([buyTx1, buyTx2])

// ✅ Correct: Execute sequentially
for (const tx of [buyTx1, buyTx2]) {
  await client.signAndExecuteTransaction({ transaction: tx })
  // Wait for confirmation before submitting the next one
}
```

### Version Conflicts Essentially Remind You: Objects Are Alive

As long as multiple transactions need to write to the same object, you must assume it may have already changed before you submit again.

So this type of problem is often not "sporadic and mysterious," but the system design telling you:

- There's a shared hotspot here
- Serialization or object version refresh is needed here
- Sharding or object splitting may need to be reconsidered here

---

## 24.6 dApp Wallet Connection Issues

### EVE Vault Not Detected

```
WalletNotFoundError: No wallet found
```

**Investigation checklist:**
1. ✅ Is EVE Vault browser extension installed and enabled?
2. ✅ Is `VITE_SUI_NETWORK` consistent with Vault's current network (testnet/mainnet)?
3. ✅ Is `@evefrontier/dapp-kit` version compatible with Vault version?

```typescript
// List all detected wallets (for debugging)
import { getWallets } from "@mysten/wallet-standard";
const wallets = getWallets();
console.log("Detected wallets:", wallets.get().map(w => w.name));
```

### Signature Request Silently Rejected (No Popup)

**Cause**: Vault may be in locked state.

**Solution**: Check wallet status before initiating signature:
```typescript
const { currentAccount } = useCurrentAccount();
if (!currentAccount) {
  // Guide user to connect wallet instead of directly initiating signature
  showConnectModal();
  return;
}
```

### Wallet Issue Investigation Order

The most stable order is usually:

1. Is the wallet detected
2. Is the current account connected
3. Is the network correct
4. Are the objects and permissions available for the current account

Don't immediately suspect Vault itself when seeing signature failures. Many issues are actually frontend state, network, and object context misalignment.

---

## 24.7 On-chain Data Reading Issues

### `getObject` Returns `null`

```typescript
const obj = await client.getObject({ id: "0x...", options: { showContent: true } });
if (!obj.data) {
  // Object doesn't exist, or ID is wrong
  console.error("Object doesn't exist, check if ID is correct (may be testnet/mainnet confusion)");
}
```

**Common causes**:
- Used testnet Object ID to query mainnet (or vice versa)
- Object has been deleted (contract called `id.delete()`)
- Typo

### `showContent: true` but `content.fields` is Empty

```typescript
const content = obj.data?.content;
if (content?.dataType !== "moveObject") {
  // This is a package object, not a Move object
  console.error("Object is not a MoveObject, ID may point to a Package");
}
```

### When Unable to Read Data, Prioritize Checking These Four Things

1. Is the ID from the correct network
2. Is this ID an object or a package
3. Has the object been deleted or migrated
4. Is the frontend parsing path consistent with the actual field structure

Many "can't read" problems aren't because the node is broken, but because you queried the wrong object.

---

## 24.8 Local Development Environment Issues

### Docker Local Chain Startup Failed

```bash
# View container logs
docker compose logs -f

# Common cause: Port occupied
lsof -i :9000
kill -9 <PID>

# Reset local chain state (clear all data and restart)
docker compose down -v
docker compose up -d
```

### `sui client publish` Failed

```bash
# Error: Package verification failed
# Cause: Dependent world-contracts address inconsistent with local node

# In Move.toml, confirm using localnet package address for local testing
[addresses]
world = "0x_LOCAL_WORLD_ADDRESS_"  # Obtain from local chain deployment results
```

### Contract Cannot Be Called After Deployment (Function Not Found)

```bash
# Check if published package ID matches ENV configuration
echo $VITE_WORLD_PACKAGE

# Verify on-chain package contains expected function
sui client object 0x_PACKAGE_ID_ --json | jq '.content.disassembled'
```

### Environment Issues Fear "Half-Right" Most

Meaning:

- Local chain is good
- CLI can also connect
- But some address, dependency or ENV is still on another environment

This type of problem is annoying because on the surface each layer "looks fine." So whenever encountering environment-type issues, it's best to print:

- Current network
- Current address
- Current package ID
- Current ENV configuration

All at once is much faster than guessing one by one.

---

## 24.9 Debugging Workflow: Systematic Investigation

```
When encountering problems, investigate in the following order:

1. Read error message (don't ignore any details)
   ├── Is it a Move abort? → Find abort code → Check contract source
   ├── Is it a Gas issue? → dryRun estimate → Adjust budget
   └── Is it a TypeScript error? → console.log parameters at each step

2. Isolate the problem
   ├── Call contract directly using Sui Explorer (bypass dApp)
   ├── Write Move unit tests to reproduce the problem
   └── Test GraphQL queries using curl/Postman

3. Align with community
   ├── Search Discord #builders channel
   ├── Paste complete error message (including Transaction Digest)
   └── Provide minimal reproducible code
```

### A More Practical Investigation Mindset

Each time, try to reduce the problem to the minimum:

- Fewest objects
- Minimum single operation
- Shortest call chain

Because once an on-chain system involves frontend, backend, wallet, indexer, and game server, problems will rapidly expand. Reduce first, then locate - highest efficiency.

---

## 24.10 Common Debugging Tools

| Tool | Purpose | Link |
|------|------|------|
| **Sui Explorer** | View transaction details, object state | https://suiexplorer.com |
| **Sui GraphQL IDE** | Manually test GraphQL queries | https://graphql.testnet.sui.io |
| **Move Prover** | Formal verification of contract properties | `sui move prove` |
| **dryRun** | Gas estimation and simulation execution | `client.dryRunTransactionBlock()` |
| **sui client call** | Call contract directly from command line | `sui client call --help` |

---

## 🔖 Chapter Summary

| Error Type | Fastest Investigation Path |
|--------|-----------|
| Move compilation errors | Check `Move.toml` dependencies + ability declarations |
| Abort (code N) | grep abort code in contract source, quick lookup table |
| Gas exhausted | `dryRun()` estimate + set 20% buffer |
| Object version conflict | Sequential execution instead of concurrent, wait for each confirm |
| Wallet not detected | Check extension installation, network consistency, version compatibility |
| Object read returns empty | Confirm network environment (testnet vs mainnet) |
| Local chain issues | `docker compose logs` + reset data volume |
