# Chapter 9: Off-chain Indexing & GraphQL Advanced Usage

> **Goal:** Master the complete toolkit for off-chain data querying, including GraphQL, gRPC, event subscriptions, and custom indexers, to build high-performance data-driven dApps.

---

> Status: Engineering chapter. Main content focuses on GraphQL, events, and indexer design.

## 9.1 Read-Write Separation Principle

The golden rule of EVE Frontier development:

```
Write operations (modify on-chain state) → Submit via Transaction → Consume Gas
Read operations (query on-chain state) → Via GraphQL/gRPC/SuiClient → Completely free
```

**Design Guidance**: Move all possible logic to off-chain reads, and only submit transactions when you truly need to change state.

This principle seems simple, but it actually determines your entire system cost structure:

- The more you write on-chain, the higher the Gas and the greater the failure surface
- The better you read off-chain, the faster the frontend and the lighter the interaction

So a mature Builder system typically doesn't "stuff everything on-chain," but clearly divides into three layers:

- **On-chain objects**
  Store state that must be trustworthy
- **On-chain events**
  Store actions that have occurred
- **Off-chain indexes**
  Store the views that the frontend actually needs to consume

If these three layers aren't separated, your frontend will eventually become a bunch of expensive and hard-to-maintain real-time RPC calls.

---

## 9.2 SuiClient Basic Reading

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });

// ❶ Read a single object
const gate = await client.getObject({
  id: "0x...",
  options: { showContent: true, showOwner: true, showType: true },
});
console.log(gate.data?.content);

// ❲ Batch read multiple objects (one request)
const objects = await client.multiGetObjects({
  ids: ["0x...gate1", "0x...gate2", "0x...ssu"],
  options: { showContent: true },
});

// ❸ Query all objects owned by an address
const ownedObjects = await client.getOwnedObjects({
  owner: "0xALICE",
  filter: { StructType: `${WORLD_PKG}::gate::Gate` },
  options: { showContent: true },
});

// ❹ Paginated query (handling large amounts of data)
let cursor: string | null = null;
const allGates: any[] = [];

do {
  const page = await client.getOwnedObjects({
    owner: "0xALICE",
    cursor,
    limit: 50,
  });
  allGates.push(...page.data);
  cursor = page.nextCursor ?? null;
} while (cursor);
```

### What is `SuiClient` best suited for?

It's best suited for:

- Single object reads
- Small-scale batch reads
- Debugging and script validation
- Lightweight queries for the frontend

It may not be directly suitable for:

- Large-scale leaderboards
- Aggregated views across multiple object types
- High-frequency complex filtering

Once your query needs start requiring "sorting, aggregation, joining across objects," it's time to consider GraphQL or a custom indexing layer.

---

## 9.3 Deep GraphQL Usage

Sui's GraphQL interface is more powerful than JSON-RPC, supporting complex filtering, nested queries, and cursor pagination.

### Connecting to GraphQL

```typescript
import { SuiGraphQLClient, graphql } from "@mysten/sui/graphql";

const graphqlClient = new SuiGraphQLClient({
  url: "https://graphql.testnet.sui.io/graphql",
});
```

### Query all objects of a certain type

```typescript
const GET_ALL_GATES = graphql(`
  query GetAllGates($type: String!, $after: String) {
    objects(filter: { type: $type }, first: 50, after: $after) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        address
        asMoveObject {
          contents {
            json  # Return fields in JSON format
          }
        }
      }
    }
  }
`);

async function getAllGates(): Promise<any[]> {
  const results: any[] = [];
  let after: string | null = null;

  do {
    const data = await graphqlClient.query({
      query: GET_ALL_GATES,
      variables: {
        type: `${WORLD_PKG}::gate::Gate`,
        after,
      },
    });

    const objects = data.data?.objects;
    if (!objects) break;

    results.push(...objects.nodes.map(n => n.asMoveObject?.contents?.json));
    after = objects.pageInfo.hasNextPage ? objects.pageInfo.endCursor : null;
  } while (after);

  return results;
}
```

### The real value of GraphQL isn't just "more elegant syntax"

Its more important value is allowing you to organize queries according to frontend views, rather than being led by single-object RPC interfaces.

This is very important in actual products, because pages often don't need "what a certain object originally looks like," but rather:

- Current object + associated object summary
- A page list + pagination information
- Multiple object types combined into one dashboard

### GraphQL is not omnipotent either

If you treat it like a database and fetch data without limits, you'll still run into problems:

- Queries too large, frontend first screen becomes slow
- Too many nested objects in one page, debugging becomes difficult
- Complex queries change once, both frontend and backend explode together

So the best use of GraphQL is usually:

- Split queries by page
- Each query serves only one clear view type
- When aggregation statistics are needed, let custom indexers take on more responsibility

### Query multiple related objects (nested)

```typescript
// Query star gate and its associated network node information
const GET_GATE_WITH_NODE = graphql(`
  query GetGateWithNode($gateId: SuiAddress!) {
    object(address: $gateId) {
      address
      asMoveObject {
        contents { json }
      }
    }
  }
`);

// Batch: query multiple different types at once
const GET_ASSEMBLY_OVERVIEW = graphql(`
  query AssemblyOverview($gateId: SuiAddress!, $ssuId: SuiAddress!) {
    gate: object(address: $gateId) {
      asMoveObject { contents { json } }
    }
    ssu: object(address: $ssuId) {
      asMoveObject { contents { json } }
    }
  }
`);
```

### Query by dynamic field (Table content)

```typescript
// Query specific entry in Market's listings Table
const GET_LISTING = graphql(`
  query GetListing($marketId: SuiAddress!, $typeId: String!) {
    object(address: $marketId) {
      dynamicField(name: { type: "u64", bcs: $typeId }) {
        value {
          ... on MoveValue {
            json
          }
        }
      }
    }
  }
`);
```

### Why are dynamic field queries more troublesome than normal object fields?

Because dynamic fields are naturally closer to "index structures that grow at runtime" rather than fixed schemas.

This means:

- You must be very clear about the key encoding method
- Frontend and indexing layer must use the same key rules
- Once the key design changes, the read path will fail entirely

So the design of dynamic fields is not just an internal contract issue, it will directly spill over to the query and frontend layers.

---

## 9.4 Real-time Event Subscription

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });

// Subscribe to all events from a specific package
const unsubscribe = await client.subscribeEvent({
  filter: { Package: MY_PACKAGE },
  onMessage: (event) => {
    switch (event.type) {
      case `${MY_PACKAGE}::toll_gate_ext::GateJumped`:
        handleGateJump(event.parsedJson);
        break;

      case `${MY_PACKAGE}::market::ItemSold`:
        handleItemSold(event.parsedJson);
        break;
    }
  },
});

// Unsubscribe after 90 seconds
setTimeout(unsubscribe, 90_000);

// Query historical events (with filtering)
const history = await client.queryEvents({
  query: {
    And: [
      { MoveEventType: `${MY_PACKAGE}::toll_gate_ext::GateJumped` },
      { Sender: "0xPlayerAddress..." },
    ],
  },
  order: "descending",
  limit: 100,
});
```

### What problems are event subscriptions best suited to solve?

Best suited for:

- Real-time notifications
- Activity streams
- Lightweight incremental updates
- Indexer consuming new transactions

Not suitable as:

- The sole source of current state
- Complete business list interface
- Highly reliable historical database

Because event streams naturally have two real-world issues:

- You might disconnect and miss messages
- You always need a historical backfill mechanism

So mature indexers usually:

- First replay history
- Then subscribe to incremental changes
- Periodically perform consistency checks

---

## 9.5 gRPC: High-throughput Data Streams

For scenarios requiring processing large amounts of real-time data (such as leaderboards, full network state snapshots), gRPC is more efficient than GraphQL:

```typescript
// Use gRPC to stream read latest Checkpoints
import { SuiHTTPTransport } from "@mysten/sui/client";

// gRPC is suitable for monitoring state changes across the entire chain
// For example: each Checkpoint contains a summary of all transactions during that period
// Advanced usage: used when building custom indexers
```

### When is it worth using gRPC instead of continuing to pile on RPC / GraphQL?

When you start encountering these scenarios:

- Need to consume checkpoints long-term
- Need to maintain your own near real-time index
- Need high-throughput, low-latency on-chain data streams

If you're just building a regular dApp page, you usually don't need to start with gRPC. It's more like an "infrastructure building tool," not a page query tool.

---

## 9.6 Building Custom Off-chain Indexers

For complex query needs (such as leaderboards, aggregate statistics), you can build your own indexing service:

```typescript
// server/indexer.ts
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: process.env.SUI_RPC! });

// In-memory index (small scale; use Redis or PostgreSQL for production)
const jumpLeaderboard = new Map<string, number>(); // address → jump count

// Start indexer: listen to events and update local state
async function startIndexer() {
  console.log("Indexer starting...");

  // First load historical data
  await loadHistoricalEvents();

  // Then subscribe to new events
  await client.subscribeEvent({
    filter: { Package: MY_PACKAGE },
    onMessage: (event) => {
      if (event.type.includes("GateJumped")) {
        const { character_id } = event.parsedJson as any;
        const count = jumpLeaderboard.get(character_id) ?? 0;
        jumpLeaderboard.set(character_id, count + 1);
      }
    },
  });
}

async function loadHistoricalEvents() {
  let cursor = null;
  do {
    const page = await client.queryEvents({
      query: { MoveEventType: `${MY_PACKAGE}::toll_gate_ext::GateJumped` },
      cursor,
      limit: 200,
    });

    for (const event of page.data) {
      const { character_id } = event.parsedJson as any;
      const count = jumpLeaderboard.get(character_id) ?? 0;
      jumpLeaderboard.set(character_id, count + 1);
    }

    cursor = page.nextCursor;
  } while (cursor && !cursor.startsWith("0x00")); // Simplified termination condition
}

// API: Provide leaderboard data
import express from "express";
const app = express();

app.get("/api/leaderboard", (req, res) => {
  const sorted = [...jumpLeaderboard.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 50)
    .map(([address, count], rank) => ({ rank: rank + 1, address, count }));

  res.json(sorted);
});

startIndexer().then(() => app.listen(3002));
```

---

## 9.7 Efficiently Displaying On-chain Data in dApps

### Using React Query for Caching & Auto-refresh

```tsx
// src/hooks/useLeaderboard.ts
import { useQuery } from "@tanstack/react-query";

export function useLeaderboard() {
  return useQuery({
    queryKey: ["leaderboard"],
    queryFn: async () => {
      const res = await fetch("/api/leaderboard");
      return res.json();
    },
    refetchInterval: 30_000,  // Refresh every 30 seconds
    staleTime: 25_000,        // Don't re-request within 25 seconds
  });
}

// Usage
function Leaderboard() {
  const { data, isLoading } = useLeaderboard();

  return (
    <table>
      <thead><tr><th>#</th><th>Player</th><th>Jump Count</th></tr></thead>
      <tbody>
        {data?.map(({ rank, address, count }) => (
          <tr key={address}>
            <td>{rank}</td>
            <td>{address.slice(0, 8)}...</td>
            <td>{count}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

---

## Chapter Summary

| Tool | Scenario | Features |
|------|------|------|
| `SuiClient.getObject()` | Read single/multiple objects | Simple and direct |
| `GraphQL` | Complex filtering, nested queries | Flexible, TypeScript type generation |
| `subscribeEvent` | Real-time event push | WebSocket, suitable for dApps |
| `queryEvents` | Historical event pagination query | Suitable for data analysis |
| Custom indexer | Complex aggregation, leaderboards | Full control, need to maintain yourself |

## Further Reading

- [Interfacing with the World](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [Sui GraphQL Documentation](https://docs.sui.io/guides/developer/accessing-data/query-with-graphql)
- [Sui Events Documentation](https://docs.sui.io/guides/developer/accessing-data/using-events)
