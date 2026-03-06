# Chapter 12：链下索引与 GraphQL 进阶

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握链下数据查询的完整工具链，包括 GraphQL、gRPC、事件订阅和自定义索引器，构建高性能的数据驱动 dApp。

---

> 状态：工程章节。正文以 GraphQL、事件和索引器设计为主。

## 前置依赖

- 建议先读 [Chapter 5](./chapter-05.md)
- 建议先读 [Chapter 11](./chapter-11.md)

## 源码位置

- 当前章无独立代码目录；建议结合案例 dApp 和后续 [Chapter 18](./chapter-18.md) 阅读。

## 关键测试文件

- 本章以读取链路设计为主，无独立测试文件。

## 推荐阅读顺序

1. 先读读写分离原则
2. 再通读 GraphQL/事件/索引器章节
3. 最后结合具体案例验证查询模型

## 验证步骤

1. 能区分事件流、对象查询和自建索引器的适用场景
2. 能给某个案例选出合适的数据读取方案
3. 能识别“把事件当列表状态”的设计错误

## 常见报错

- 直接用事件重建当前状态，忽略对象才是权威数据源

---

## 12.1 读写分离原则

EVE Frontier 开发的黄金法则：

```
写操作（改变链上状态）→ 通过 Transaction 提交 → 消耗 Gas
读操作（查询链上状态）→ 通过 GraphQL/gRPC/SuiClient → 完全免费
```

**设计指导**：将所有可能的逻辑移到链下读取，只在真正需要改变状态时才提交交易。

---

## 12.2 SuiClient 基础读取

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });

// ❶ 读取单个对象
const gate = await client.getObject({
  id: "0x...",
  options: { showContent: true, showOwner: true, showType: true },
});
console.log(gate.data?.content);

// ❷ 批量读取多个对象（一次请求）
const objects = await client.multiGetObjects({
  ids: ["0x...gate1", "0x...gate2", "0x...ssu"],
  options: { showContent: true },
});

// ❸ 查询某地址拥有的所有对象
const ownedObjects = await client.getOwnedObjects({
  owner: "0xALICE",
  filter: { StructType: `${WORLD_PKG}::gate::Gate` },
  options: { showContent: true },
});

// ❹ 分页查询（处理大量数据）
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

---

## 12.3 GraphQL 深度使用

Sui 的 GraphQL 接口比 JSON-RPC 更强大，支持复杂过滤、嵌套查询和游标分页。

### 连接 GraphQL

```typescript
import { SuiGraphQLClient, graphql } from "@mysten/sui/graphql";

const graphqlClient = new SuiGraphQLClient({
  url: "https://graphql.testnet.sui.io/graphql",
});
```

### 查询某类型的所有对象

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
            json  # 以 JSON 格式返回字段
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

### 查询多个关联对象（嵌套）

```typescript
// 查询星门及其关联的网络节点信息
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

// 批量: 一次查询多个不同类型
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

### 按动态字段查询（Table 内容）

```typescript
// 查询 Market 的 listings Table 中特定条目
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

---

## 12.4 事件实时订阅

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });

// 订阅特定包的所有事件
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

// 90 秒后取消订阅
setTimeout(unsubscribe, 90_000);

// 查询历史事件（带过滤）
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

---

## 12.5 gRPC：高吞吐量数据流

对于需要处理大量实时数据的场景（如排行榜、全网状态快照），gRPC 比 GraphQL 更高效：

```typescript
// 使用 gRPC 流式读取最新 Checkpoints
import { SuiHTTPTransport } from "@mysten/sui/client";

// gRPC 适合监控整个链的状态变化
// 例如：每个 Checkpoint 包含该期间内所有交易的摘要
// 高级用法：构建自定义索引器时使用
```

---

## 12.6 构建自定义链下索引器

对于复杂的查询需求（如排行榜、聚合统计），可以构建自己的索引服务：

```typescript
// server/indexer.ts
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: process.env.SUI_RPC! });

// 内存索引（小规模；生产环境用 Redis 或 PostgreSQL）
const jumpLeaderboard = new Map<string, number>(); // address → jump count

// 启动索引：监听事件并更新本地状态
async function startIndexer() {
  console.log("索引器启动...");

  // 先载入历史数据
  await loadHistoricalEvents();

  // 然后订阅新事件
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
  } while (cursor && !cursor.startsWith("0x00")); // 简化终止条件
}

// API：提供排行榜数据
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

## 12.7 在 dApp 中高效展示链上数据

### 使用 React Query 缓存与自动刷新

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
    refetchInterval: 30_000,  // 每 30 秒刷新
    staleTime: 25_000,        // 25 秒内不重新请求
  });
}

// 使用
function Leaderboard() {
  const { data, isLoading } = useLeaderboard();

  return (
    <table>
      <thead><tr><th>#</th><th>玩家</th><th>跳跃次数</th></tr></thead>
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

## 🔖 本章小结

| 工具 | 场景 | 特点 |
|------|------|------|
| `SuiClient.getObject()` | 读取单个/多个对象 | 简单直接 |
| `GraphQL` | 复杂过滤、嵌套查询 | 灵活，TypeScript 类型生成 |
| `subscribeEvent` | 实时事件推送 | WebSocket，适合 dApp |
| `queryEvents` | 历史事件分页查询 | 适合数据分析 |
| 自定义索引器 | 复杂聚合、排行榜 | 全控制，需要自己维护 |

## 📚 延伸阅读

- [Interfacing with the World](https://github.com/evefrontier/builder-documentation/blob/main/smart-contracts/interfacing-with-the-eve-frontier-world.md)
- [Sui GraphQL 文档](https://docs.sui.io/guides/developer/accessing-data/query-with-graphql)
- [Sui Events 文档](https://docs.sui.io/guides/developer/accessing-data/using-events)
