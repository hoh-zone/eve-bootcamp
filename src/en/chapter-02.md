# Chapter 2: Sui and EVE Environment Configuration

> **Objective:** Complete only the two most fundamental and necessary installations for this book: `Sui CLI` and `EVE Vault`. This chapter no longer expands on common development tools like Git, Docker, Node.js, pnpm.

---

> Status: Foundation chapter. The main text only covers installations and configurations directly related to Sui and EVE Frontier.

## 2.1 What Does This Chapter Install?

This chapter only handles two types of installations directly related to this book:

| Tool | Version Requirement | Purpose |
|------|---------|------|
| **Sui CLI** | testnet version | Compile and publish Move contracts |
| **EVE Vault** | latest version | Browser wallet + identity |

---

## 2.2 Why Only Install These Two First?

Because before you continue reading, the minimum capabilities you truly need are only two:

- **Can run `sui` commands locally**
  All your Move compilation, testing, publishing, and object queries depend on it
- **Have a working EVE wallet identity in browser**
  All your dApp connections, signing, and test asset claiming depend on it

Tools like `Git`, `Docker`, `Node.js`, `pnpm` will certainly be used later, but they belong to:

- Common development tools
- Scaffolding engineering tools
- Front-end and script running tools

These are better installed when you reach [Chapter 6](./chapter-06.md) and [Chapter 7](./chapter-07.md), combining them with the project directory.

### What This Chapter Really Establishes Isn't Just Two Software Programs

More precisely, this chapter establishes two working entry points:

- **Command-line entry**
  For compilation, publishing, querying, testing
- **Browser entry**
  For wallet connection, signing, dApp interaction

Almost all your development actions later will switch back and forth between these two entry points:

- After writing contracts, use CLI to compile and publish
- Open front-end, use EVE Vault to connect and sign
- When querying objects, might use CLI, or might use front-end or GraphQL

So although this chapter seems to be just about installation, it's actually laying down the "workbench" for the entire book.

---

## 2.3 Installing Sui CLI

Recommend directly using the official `suiup` installation method. This way this chapter doesn't need to distinguish between system toolchains like Homebrew, apt, nvm.

```bash
# Install suiup
curl -sSfL https://raw.githubusercontent.com/MystenLabs/suiup/main/install.sh | sh

# Reopen terminal or reload shell, then execute
suiup install sui@testnet

# Verify
sui --version
```

If `sui --version` can output the version number normally, the first step of this chapter is complete.

---

## 2.4 Initialize Sui Client

After installing Sui CLI, you need to initialize the client and connect to the network:

```bash
# Initialize configuration (first run will prompt to select network)
sui client

# Select testnet, or connect to local node:
# localnet: http://0.0.0.0:9000

# View current address
sui client active-address

# View balance
sui client balance
```

### What Did You Actually Complete Here?

After executing `sui client`, you'll have a basic on-chain identity and network configuration locally:

- Current active address
- Current default network
- RPC configuration corresponding to that network
- Account context that local CLI will use when sending transactions and querying objects

In other words, `sui client` isn't simply a command to "check balance," but laying the foundation for all your Move development actions.

### What's the Relationship Between `sui client` and EVE Vault?

These two things are most easily confused by beginners:

- `sui client` is the identity and network configuration in the command-line environment
- `EVE Vault` is the identity and signing entry in the browser environment

They can both represent "you," but serve different scenarios:

- When you publish contracts, run tests, query objects in the terminal, you mainly rely on `sui client`
- When you connect dApps, click buttons, sign transactions in web pages, you mainly rely on `EVE Vault`

### Must They Be the Same Address?

Not necessarily.

Many developers will encounter this situation:

- CLI uses one test address
- EVE Vault has another zkLogin address

This isn't absolutely wrong, but you must be very clear about:

- Which address you're publishing packages from now
- Which address or character controls your facilities
- Which wallet address your front-end connects to

As long as these three things aren't aligned, you'll frequently encounter "I clearly published, why can't the front-end see it / operate it" problems.

### Get Test SUI from Faucet

If connected to testnet:
```bash
# Request test coins through CLI
sui client faucet

# Or visit web Faucet:
# https://faucet.testnet.sui.io
```

---

## 2.5 Install and Initialize EVE Vault

**EVE Vault** is your browser identity, used to connect to dApps and authorize transactions.

### Installation Steps

1. Download the latest Chrome extension:
   ```
   https://github.com/evefrontier/evevault/releases/download/v0.0.6/eve-vault-chrome.zip
   ```
2. Unzip the zip file
3. Open Chrome → Extension Management → Enable "Developer mode" → "Load unpacked extension" → Select unzipped folder
4. Click the extension icon, use EVE Frontier SSO account (Google/Twitch, etc.) to create your Sui wallet through **zkLogin**

> **Advantage**: zkLogin doesn't need mnemonic phrases, your Sui address is uniquely derived from your OAuth identity, secure and convenient.

What's most worth understanding here isn't the "installation method," but why it greatly lowers the barrier for new users:

- No need to first educate users about saving mnemonic phrases
- No need to first install a set of traditional wallet mindset
- Users can directly enter on-chain interactions using familiar account systems

For Builders, this means your dApp doesn't have to assume users are "already experienced crypto users." This will directly affect your product design approach:

- Login and connection flow can be shorter
- Gas experience can be further optimized with sponsored transactions
- You can focus on facility experience rather than wallet education

---

## 2.6 What Does EVE Vault Specifically Handle in This Book?

After installing EVE Vault, it will undertake three types of responsibilities in subsequent chapters:

- **Wallet**
  Hold LUX, SUI, NFTs, permission credentials
- **Identity**
  Use EVE Frontier account to enter on-chain interaction system
- **Authorization Entry**
  Provide dApps with connection, signing, sponsored transaction capabilities

You can understand it first as:

> `sui client` is the on-chain identity in command line, `EVE Vault` is the on-chain identity in browser and dApps.

The two aren't necessarily the same address, but they must both work properly.

### When Should You Check CLI First, When Should You Check Wallet First?

This can help you locate problems faster:

- **Contract compilation failure**
  Check CLI first
- **Publishing transaction failure**
  Check CLI current network and address first
- **Front-end can't connect wallet**
  Check EVE Vault first
- **Front-end can connect wallet but buttons report permission errors**
  Verify wallet address, character attribution, and object permissions first

Don't attribute all on-chain problems to "wallet broken" or "CLI misconfigured." Most of the time, you haven't first distinguished which layer the problem occurs in.

---

## 2.7 EVE Vault Faucet: Get Test Assets

During development and testing phases, you'll encounter at least two types of test assets:

- **Test SUI**
  Used for on-chain transaction Gas
- **Test LUX**
  Used to simulate EVE Frontier in-game economic interactions

How to get LUX:

1. After installing EVE Vault, find **GAS Faucet** in the extension interface
2. Enter your Sui address to request test tokens
3. LUX will appear in your EVE Vault balance

Detailed instructions: [GAS Faucet Documentation](https://github.com/evefrontier/builder-documentation/blob/main/eve-vault/gas-faucet.md)

### Why Do You Need Both SUI and LUX During Testing?

Because they play different roles:

- **SUI**
  Is the Gas resource for on-chain transactions, without it many transactions can't even be sent
- **LUX**
  Is more like an economic asset in the EVE Frontier business environment, many tutorials and cases use it to simulate in-game fees, settlements, permit purchases

If you only have SUI, no LUX:

- You can send transactions
- But many business processes can't be practiced according to the book

If you only have LUX, no SUI:

- You'll find it hard to complete even the most basic on-chain interactions

---

## 2.8 Minimum Acceptance Checklist

At this point, you don't need to run scaffolding immediately, nor install front-end dependencies first. First confirm these four things:

1. `sui --version` can output the version
2. `sui client active-address` can return the current address
3. `EVE Vault` has completed zkLogin initialization
4. At least you can see test assets in wallet or can request from Faucet

If all four things are true, it means you already have the minimum environment to continue learning the first half of this book.

### Three Most Common Environment Misalignments

#### 1. CLI on testnet, wallet switched to a different network

Manifestation:

- Can query objects in terminal
- Can't see corresponding assets or components in front-end

#### 2. CLI address and wallet address aren't the same, but you didn't realize it

Manifestation:

- Contract published from one address
- dApp connected to another address
- Front-end operations prompt no permission

#### 3. Faucet tokens received, but received to "another identity set"

Manifestation:

- You clearly claimed test coins
- But current wallet or CLI address balance is still 0

Once you encounter "I clearly did it, but the system says I didn't" problems, don't rush to doubt the tutorial. Verify these three things again first.

### When to Install Other Tools?

- By [Chapter 6](./chapter-06.md): Install and use `builder-scaffold`
- By [Chapter 7](./chapter-07.md): Handle script and dApp dependencies
- By specific case chapters: Supplement front-end running environment as needed

## 🔖 Chapter Summary

| Step | Operation |
|------|------|
| Install Sui CLI | `suiup install sui@testnet` |
| Configure Sui Client | `sui client` select network and create address |
| Install EVE Vault | Chrome extension + zkLogin create on-chain identity |
| Get Test Assets | SUI Faucet + EVE Vault GAS Faucet |
| Verify Environment | CLI address, wallet address, network, balance all visible |

## 📚 Extended Reading

- [Sui CLI Complete Documentation](https://docs.sui.io/references/cli)
- [Sui Client Configuration Guide](https://docs.sui.io/guides/developer/getting-started/configure-sui-client)
- [EVE Vault](https://github.com/evefrontier/evevault)
- [EVE Vault GAS Faucet Documentation](https://github.com/evefrontier/builder-documentation/blob/main/eve-vault/gas-faucet.md)
