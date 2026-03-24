# Chapter 19: Full-Stack dApp Architecture Design

> **Goal:** Design and implement production-grade EVE Frontier dApps, covering state management, real-time data updates, error handling, responsive design, and CI/CD automated deployment.

---

> Status: Architecture chapter. Main focus on full-stack dApp organization, state management, and deployment.

## 19.1 Full-Stack Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                    User Browser                      │
│  ┌──────────────────────────────────────────────┐   │
│  │              React / Next.js dApp             │   │
│  │  ┌──────────┐  ┌──────────┐  ┌────────────┐  │   │
│  │  │ EVE Vault│  │React     │  │ Tanstack   │  │   │
│  │  │ Wallet   │  │ dapp-kit │  │ Query      │  │   │
│  │  └──────────┘  └──────────┘  └────────────┘  │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────┘
                      │
          ┌───────────┼────────────┐
          ▼           ▼            ▼
     Sui Full Node  Your Backend  Game Server
     GraphQL        Sponsor Svc   Location/Verify API
     Event Stream   Index Svc
```

What this diagram should convey most isn't "there are many tech stacks," but:

> A truly usable EVE dApp is never a single-page frontend, but an entire layered collaborative system.

Each layer in this system solves different problems:

- Browser handles interaction and state feedback
- Wallet handles signing and identity
- Full node and GraphQL provide on-chain truth
- Backend handles sponsoring, risk control, aggregation
- Game server provides off-chain world interpretation and verification

If these responsibilities aren't layered, system surface can run, but will become increasingly difficult to maintain.

---

## 19.2 Project Structure (Next.js Example)

```
dapp/
├── app/                          # Next.js App Router
│   ├── layout.tsx                # Global layout (Provider)
│   ├── page.tsx                  # Homepage
│   ├── gate/[id]/page.tsx        # Stargate detail page
│   └── dashboard/page.tsx        # Management panel
├── components/
│   ├── common/
│   │   ├── WalletButton.tsx
│   │   ├── TxStatus.tsx
│   │   └── LoadingSpinner.tsx
│   ├── gate/
│   │   ├── GateCard.tsx
│   │   ├── JumpPanel.tsx
│   │   └── TollInfo.tsx
│   └── market/
│       ├── ItemGrid.tsx
│       └── BuyButton.tsx
├── hooks/
│   ├── useGate.ts                # Stargate data
│   ├── useMarket.ts              # Market data
│   ├── useSponsoredAction.ts     # Sponsored transactions
│   └── useEvents.ts              # Real-time events
├── lib/
│   ├── sui.ts                    # SuiClient instance
│   ├── contracts.ts              # Contract constants
│   ├── queries.ts                # GraphQL queries
│   └── config.ts                 # Environment config
├── store/
│   └── useAppStore.ts            # Zustand global state
└── .env.local
```

### The Real Purpose of Directory Structure Isn't "Looking Good," But Preventing Responsibility Sprawl

Most common way to lose control is:

- Components directly stuffing on-chain requests
- Hooks directly writing business rules
- Pages directly assembling transaction details
- Global store stuffing all state

Short-term can run, long-term will be very difficult to change.

A more stable boundary is usually:

- `components/` handles display and interaction
- `hooks/` handles page-level data flow
- `lib/` handles underlying client and query encapsulation
- `store/` only puts truly cross-page shared local UI state

---

## 19.3 Global Provider Configuration

```tsx
// app/layout.tsx
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { SuiClientProvider, WalletProvider } from "@mysten/dapp-kit-react";
import { EveFrontierProvider } from "@evefrontier/dapp-kit";
import { getFullnodeUrl } from "@mysten/sui/client";
import { EVE_VAULT_WALLET } from "@evefrontier/dapp-kit";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,    // Don't re-request within 30 seconds
      refetchInterval: false,
      retry: 2,
    },
  },
});

const networks = {
  testnet: { url: getFullnodeUrl("testnet") },
  mainnet: { url: getFullnodeUrl("mainnet") },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <QueryClientProvider client={queryClient}>
          <SuiClientProvider networks={networks} defaultNetwork="testnet">
            <WalletProvider wallets={[EVE_VAULT_WALLET]} autoConnect>
              <EveFrontierProvider>
                {children}
              </EveFrontierProvider>
            </WalletProvider>
          </SuiClientProvider>
        </QueryClientProvider>
      </body>
    </html>
  );
}
```

### Provider Chain Is Actually Declaring Entire App's Runtime Dependency Order

This isn't a formality issue. Once order is wrong, common consequences include:

- Wallet context can't get client
- Query cache invalidation doesn't work as expected
- dapp-kit can't read needed environment

So global Provider should be as stable as possible, don't frequently change during business iteration.

---

## 19.4 State Management (Zustand + React Query)

```typescript
// store/useAppStore.ts
import { create } from "zustand";

interface AppStore {
  selectedGateId: string | null;
  txPending: boolean;
  txDigest: string | null;
  setSelectedGate: (id: string | null) => void;
  setTxPending: (pending: boolean) => void;
  setTxDigest: (digest: string | null) => void;
}

export const useAppStore = create<AppStore>((set) => ({
  selectedGateId: null,
  txPending: false,
  txDigest: null,
  setSelectedGate: (id) => set({ selectedGateId: id }),
  setTxPending: (pending) => set({ txPending: pending }),
  setTxDigest: (digest) => set({ txDigest: digest }),
}));
```

```typescript
// hooks/useGate.ts
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useCurrentClient } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

export function useGate(gateId: string) {
  const client = useCurrentClient();

  return useQuery({
    queryKey: ["gate", gateId],
    queryFn: async () => {
      const obj = await client.getObject({
        id: gateId,
        options: { showContent: true },
      });
      return obj.data?.content?.dataType === "moveObject"
        ? obj.data.content.fields
        : null;
    },
    refetchInterval: 15_000,
  });
}

export function useJumpGate(gateId: string) {
  const queryClient = useQueryClient();
  const { signAndExecuteSponsoredTransaction } = useSponsoredAction();

  return useMutation({
    mutationFn: async (characterId: string) => {
      const tx = new Transaction();
      tx.moveCall({
        target: `${TOLL_PACKAGE}::toll_gate_ext::pay_toll_and_get_permit`,
        arguments: [/* ... */],
      });
      return signAndExecuteSponsoredTransaction(tx);
    },
    onSuccess: () => {
      // After successful transaction, invalidate related queries (trigger reload)
      queryClient.invalidateQueries({ queryKey: ["gate", gateId] });
      queryClient.invalidateQueries({ queryKey: ["treasury"] });
    },
  });
}
```

### React Query and Zustand Don't Mix Responsibilities

A very practical division of labor is:

- **React Query**
  Manages on-chain data, remote data, cache, invalidation and refetch
- **Zustand**
  Manages local UI state, e.g., currently selected item, modals, temporary input

Once you stuff on-chain objects into Zustand, or force pure UI state into Query cache, it will almost certainly become messy later.

### A Mature dApp Has At Least Three Layers of State

1. **Remote Truth State**
   On-chain objects, index results, game server API returns
2. **Local Interaction State**
   Forms, hover, loading, modals
3. **Transaction State**
   Signing, submitted, confirmed, failed

These three layers of state update at different rhythms, shouldn't be mixed into one layer.

---

## 19.5 Real-Time Data Push

```typescript
// hooks/useEvents.ts
import { useEffect, useRef, useState } from "react";
import { useCurrentClient } from "@mysten/dapp-kit-react";

export function useRealtimeEvents<T>(
  eventType: string,
  options?: { maxEvents?: number }
) {
  const client = useCurrentClient();
  const [events, setEvents] = useState<T[]>([]);
  const unsubRef = useRef<(() => void) | null>(null);
  const maxEvents = options?.maxEvents ?? 50;

  useEffect(() => {
    const subscribe = async () => {
      unsubRef.current = await client.subscribeEvent({
        filter: { MoveEventType: eventType },
        onMessage: (event) => {
          setEvents((prev) => [event.parsedJson as T, ...prev].slice(0, maxEvents));
        },
      });
    };

    subscribe();
    return () => { unsubRef.current?.(); };
  }, [client, eventType, maxEvents]);

  return events;
}

// Usage
function JumpFeed() {
  const jumps = useRealtimeEvents<{character_id: string; toll_paid: string}>(
    `${TOLL_PACKAGE}::toll_gate_ext::GateJumped`
  );

  return (
    <ul>
      {jumps.map((j, i) => (
        <li key={i}>
          {j.character_id.slice(0, 8)}... paid {Number(j.toll_paid) / 1e9} SUI
        </li>
      ))}
    </ul>
  );
}
```

### Don't Use Real-Time Streams to Replace Complete Data Loading

It's better suited for:

- Incremental feeds
- Notifications and alerts
- Partial activity information

Rather than directly serving as page initial data source. More stable strategy is usually:

1. Page first loads current snapshot
2. Then receives event stream for incremental updates
3. Periodically or on-demand do consistency refresh

---

## 19.6 Error Handling and User Experience

```tsx
// components/common/TxButton.tsx
import { useState } from "react";

interface TxButtonProps {
  onClick: () => Promise<void>;
  children: React.ReactNode;
  disabled?: boolean;
}

export function TxButton({ onClick, children, disabled }: TxButtonProps) {
  const [status, setStatus] = useState<"idle" | "pending" | "success" | "error">("idle");
  const [message, setMessage] = useState("");

  const handleClick = async () => {
    setStatus("pending");
    setMessage("⏳ Submitting...");
    try {
      await onClick();
      setStatus("success");
      setMessage("✅ Transaction successful!");
      setTimeout(() => setStatus("idle"), 3000);
    } catch (e: any) {
      setStatus("error");
      // Parse Move abort error code to human-readable message
      const abortCode = extractAbortCode(e.message);
      setMessage(`❌ ${translateError(abortCode) ?? e.message}`);
    }
  };

  return (
    <div>
      <button
        onClick={handleClick}
        disabled={disabled || status === "pending"}
        className={`tx-btn tx-btn--${status}`}
      >
        {status === "pending" ? "⏳ Processing..." : children}
      </button>
      {message && <p className={`message message--${status}`}>{message}</p>}
    </div>
  );
}

// Translate Move abort error code to friendly message
function translateError(code: number | null): string | null {
  const errors: Record<number, string> = {
    0: "Insufficient permissions, please confirm wallet is connected",
    1: "Insufficient balance",
    2: "Item already sold",
    3: "Stargate offline",
  };
  return code !== null ? errors[code] ?? null : null;
}

function extractAbortCode(message: string): number | null {
  const match = message.match(/abort_code: (\d+)/);
  return match ? parseInt(match[1]) : null;
}
```

---

## 19.7 CI/CD Automated Deployment

```yaml
# .github/workflows/deploy.yml
name: Deploy dApp

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "20" }
      - run: npm ci
      - run: npm run test
      - run: npm run build

  deploy-preview:
    if: github.event_name == 'pull_request'
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
        env:
          VITE_SUI_RPC_URL: ${{ vars.TESTNET_RPC_URL }}
          VITE_WORLD_PACKAGE: ${{ vars.TESTNET_WORLD_PACKAGE }}
      - uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
        env:
          VITE_SUI_RPC_URL: ${{ vars.MAINNET_RPC_URL }}
          VITE_WORLD_PACKAGE: ${{ vars.MAINNET_WORLD_PACKAGE }}
      - uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-args: "--prod"
```

---

## 🔖 Chapter Summary

| Architecture Component | Tech Choice | Responsibility |
|--------|---------|------|
| UI Framework | React + Next.js | Page rendering, routing |
| On-Chain Communication | @mysten/dapp-kit + SuiClient | Read chain/sign/send transactions |
| State Management | Zustand (global) + React Query (server) | Cache and sync |
| Real-Time Updates | subscribeEvent (WebSocket) | Event push |
| Error Handling | abort code translation + state machine | User-friendly prompts |
| CI/CD | GitHub Actions + Vercel | Automated testing and deployment |

## 📚 Further Reading

- [Move Book](https://move-book.com)
- [Tanstack Query Documentation](https://tanstack.com/query/latest)
- [dapp-kit React Documentation](https://sdk.mystenlabs.com/dapp-kit)
