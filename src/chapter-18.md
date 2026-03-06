# Chapter 18：全栈 dApp 架构设计

> **目标：** 设计和实现生产级的 EVE Frontier dApp，涵盖状态管理、实时数据更新、错误处理、响应式设计和 CI/CD 自动化部署。

---

> 状态：架构章节。正文以全栈 dApp 组织、状态管理和部署为主。

## 18.1 全栈架构概览

```
┌─────────────────────────────────────────────────────┐
│                    用户浏览器                         │
│  ┌──────────────────────────────────────────────┐   │
│  │              React / Next.js dApp             │   │
│  │  ┌──────────┐  ┌──────────┐  ┌────────────┐  │   │
│  │  │ EVE Vault│  │React     │  │ Tanstack   │  │   │
│  │  │ Wallet   │  │ dapp-kit │  │ Query      │  │   │
│  │  └──────────┘  └──────────┘  └────────────┘  │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────┘
                          │
              ┌───────────┼────────────┐
              ▼           ▼            ▼
         Sui 全节点    你的后端      游戏服务器
         GraphQL      赞助服务      位置 / 验证 API
         事件流        索引服务
```

这张图最该传达的不是“技术栈很多”，而是：

> 一个真实可用的 EVE dApp，从来不是单页前端，而是一整套分层协同系统。

这套系统里每层都在解决不同问题：

- 浏览器负责交互和状态反馈
- 钱包负责签名与身份
- 全节点和 GraphQL 提供链上真相
- 后端负责赞助、风控、聚合
- 游戏服务器提供链下世界解释和验证

如果这些职责不分层，系统表面能跑，后面一定会越来越难维护。

---

## 18.2 项目结构（Next.js 示例）

```
dapp/
├── app/                          # Next.js App Router
│   ├── layout.tsx                # 全局布局（Provider）
│   ├── page.tsx                  # 首页
│   ├── gate/[id]/page.tsx        # 星门详情页
│   └── dashboard/page.tsx        # 管理面板
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
│   ├── useGate.ts                # 星门数据
│   ├── useMarket.ts              # 市场数据
│   ├── useSponsoredAction.ts     # 赞助交易
│   └── useEvents.ts              # 实时事件
├── lib/
│   ├── sui.ts                    # SuiClient 实例
│   ├── contracts.ts              # 合约常量
│   ├── queries.ts                # GraphQL 查询
│   └── config.ts                 # 环境配置
├── store/
│   └── useAppStore.ts            # Zustand 全局状态
└── .env.local
```

### 目录结构的真正目的不是“好看”，而是防止职责蔓延

最常见的失控方式是：

- 组件里直接塞链上请求
- Hook 里直接写业务规则
- 页面里直接拼交易细节
- 全局 store 里塞一切状态

短期能跑，长期会很难改。

一个更稳的边界通常是：

- `components/` 负责展示和交互
- `hooks/` 负责页面级数据流
- `lib/` 负责底层客户端和查询封装
- `store/` 只放真正跨页面共享的本地 UI 状态

---

## 18.3 全局 Provider 配置

```tsx
// app/layout.tsx
"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { SuiClientProvider, WalletProvider } from "@mysten/dapp-kit";
import { EveFrontierProvider } from "@evefrontier/dapp-kit";
import { getFullnodeUrl } from "@mysten/sui/client";
import { EVE_VAULT_WALLET } from "@evefrontier/dapp-kit";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,    // 30 秒内不重新请求
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
    <html lang="zh-CN">
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

### Provider 链其实是在声明整套应用的运行时依赖顺序

这不是形式问题。顺序一旦错，常见后果包括：

- 钱包上下文拿不到 client
- Query cache 失效不按预期工作
- dapp-kit 读取不到需要的环境

所以全局 Provider 最好尽量稳定，不要在业务迭代中频繁改动。

---

## 18.4 状态管理（Zustand + React Query）

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
import { useSuiClient } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";

export function useGate(gateId: string) {
  const client = useSuiClient();

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
      // 交易成功后使相关查询失效（触发重新加载）
      queryClient.invalidateQueries({ queryKey: ["gate", gateId] });
      queryClient.invalidateQueries({ queryKey: ["treasury"] });
    },
  });
}
```

### React Query 和 Zustand 不要混用职责

一个非常实用的分工是：

- **React Query**
  管链上数据、远程数据、缓存、失效与重取
- **Zustand**
  管本地 UI 状态，例如当前选中项、弹窗、临时输入

一旦把链上对象也塞进 Zustand，或者把纯 UI 状态硬塞进 Query cache，后面几乎一定会变乱。

### 一个成熟 dApp 至少有三层状态

1. **远程真相状态**
   链上对象、索引结果、游戏服 API 返回
2. **本地交互状态**
   表单、hover、loading、弹窗
3. **事务状态**
   正在签名、已提交、已确认、失败

这三层状态更新节奏不同，不应该揉成一层。

---

## 18.5 实时数据推送

```typescript
// hooks/useEvents.ts
import { useEffect, useRef, useState } from "react";
import { useSuiClient } from "@mysten/dapp-kit";

export function useRealtimeEvents<T>(
  eventType: string,
  options?: { maxEvents?: number }
) {
  const client = useSuiClient();
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

// 使用
function JumpFeed() {
  const jumps = useRealtimeEvents<{character_id: string; toll_paid: string}>(
    `${TOLL_PACKAGE}::toll_gate_ext::GateJumped`
  );

  return (
    <ul>
      {jumps.map((j, i) => (
        <li key={i}>
          {j.character_id.slice(0, 8)}... 支付 {Number(j.toll_paid) / 1e9} SUI
        </li>
      ))}
    </ul>
  );
}
```

### 实时流不要拿来替代完整数据加载

它更适合做：

- 增量 feed
- 提示和通知
- 局部活跃信息

而不是直接充当页面首屏数据源。更稳的策略通常是：

1. 页面先加载当前快照
2. 再接事件流补增量
3. 定时或按需做一致性刷新

---

## 18.6 错误处理与用户体验

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
    setMessage("⏳ 提交中...");
    try {
      await onClick();
      setStatus("success");
      setMessage("✅ 交易成功！");
      setTimeout(() => setStatus("idle"), 3000);
    } catch (e: any) {
      setStatus("error");
      // 解析 Move abort 错误码为人类可读信息
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
        {status === "pending" ? "⏳ 处理中..." : children}
      </button>
      {message && <p className={`message message--${status}`}>{message}</p>}
    </div>
  );
}

// 将 Move abort 错误码翻译为友好提示
function translateError(code: number | null): string | null {
  const errors: Record<number, string> = {
    0: "权限不足，请确认钱包已连接",
    1: "余额不足",
    2: "物品已售出",
    3: "星门未上线",
  };
  return code !== null ? errors[code] ?? null : null;
}

function extractAbortCode(message: string): number | null {
  const match = message.match(/abort_code: (\d+)/);
  return match ? parseInt(match[1]) : null;
}
```

---

## 18.7 CI/CD 自动部署

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

## 🔖 本章小结

| 架构组件 | 技术选择 | 职责 |
|--------|---------|------|
| UI 框架 | React + Next.js | 页面渲染、路由 |
| 链上通信 | @mysten/dapp-kit + SuiClient | 读链/签名/发交易 |
| 状态管理 | Zustand（全局） + React Query（服务端） | 缓存与同步 |
| 实时更新 | subscribeEvent（WebSocket） | 事件推送 |
| 错误处理 | abort code 翻译 + 状态机 | 用户友好提示 |
| CI/CD | GitHub Actions + Vercel | 自动测试与部署 |

## 📚 延伸阅读

- [Move Book](https://move-book.com)
- [Tanstack Query 文档](https://tanstack.com/query/latest)
- [dapp-kit React 文档](https://sdk.mystenlabs.com/dapp-kit)
