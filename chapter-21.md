# Chapter 21：游戏内 dApp 集成（浮层 UI 与事件通信）

> ⏱ 预计学习时间：2 小时
>
> **目标：** 掌握如何将你的 dApp 嵌入 EVE Frontier 游戏客户端作为悬浮面板，实现游戏内与链上数据的无缝交互，以及如何从游戏内发起签名请求而无需切换到外部浏览器。

---

## 21.1 两种 dApp 访问模式

EVE Frontier 支持两种访问你的 dApp 的方式：

| 模式 | 入口 | 适合场景 |
|------|------|--------|
| **外部浏览器** | 玩家手动打开网页 | 管理面板、数据分析、设置页 |
| **游戏内浮层** | 游戏客户端内嵌 WebView | 交易弹窗、实时状态、战斗辅助 |

游戏内集成提供更流畅的用户体验：玩家无需切出游戏就能完成购买、查看库存、签署交易。

---

## 21.2 游戏内 WebView 的工作原理

EVE Frontier 客户端内置一个 Chromium WebView，可以加载外部 URL：

```
游戏客户端 (Unity/Electron)
    └── WebView 组件
          └── 加载你的 dApp URL（https://your-dapp.com）
                └── 与 EVE Vault（已注入游戏内）通信
```

**关键点**：EVE Vault 被注入到游戏内 WebView 的 `window` 对象中，与外部浏览器扩展共享相同的 Wallet Standard API，因此同一套 `@mysten/dapp-kit` 代码**无需修改**即可在两种模式下运行。

---

## 21.3 检测当前运行环境

你的 dApp 需要知道自己是运行在游戏内还是外部浏览器，以便做出相应的 UI 调整：

```typescript
// lib/environment.ts

export type RunEnvironment = "in-game" | "external-browser" | "unknown";

export function detectEnvironment(): RunEnvironment {
  // EVE Frontier 客户端会在 WebView 的 navigator.userAgent 中注入标识
  const ua = navigator.userAgent;

  if (ua.includes("EVEFrontier/GameClient")) {
    return "in-game";
  }

  // 也可以通过自定义查询参数传入
  const params = new URLSearchParams(window.location.search);
  if (params.get("env") === "ingame") {
    return "in-game";
  }

  return "external-browser";
}

export const isInGame = detectEnvironment() === "in-game";
```

```tsx
// App.tsx
import { isInGame } from "./lib/environment";

export function App() {
  return (
    <div className={`app ${isInGame ? "app--ingame" : "app--external"}`}>
      {isInGame ? <InGameOverlay /> : <FullDashboard />}
    </div>
  );
}
```

---

## 21.4 游戏内浮层 UI 设计原则

游戏内 UI 与外部 Web 页面的设计要求不同：

| 外部浏览器 | 游戏内浮层 |
|----------|---------|
| 全屏布局 | **小窗口**（通常 400×600px） |
| 标准字体大小 | 更大字体，高对比度 |
| 悬停 tooltip | 避免悬停（不确定焦点在游戏还是 UI） |
| 多步骤表单 | 单步操作为主，减少输入 |
| 非流式动效 | 轻量动效（防止遮挡游戏画面） |

```css
/* ingame.css - 游戏内浮层专用样式 */
:root {
  --ingame-bg: rgba(10, 15, 25, 0.92);
  --ingame-border: rgba(80, 160, 255, 0.4);
  --ingame-text: #e0e8ff;
  --ingame-accent: #4fa3ff;
}

.app--ingame {
  width: 420px;
  min-height: 100vh;
  background: var(--ingame-bg);
  color: var(--ingame-text);
  border: 1px solid var(--ingame-border);
  backdrop-filter: blur(8px);
  font-size: 15px;      /* 比标准稍大 */
  font-family: 'Share Tech Mono', monospace;  /* EVE 风格字体 */
}

/* 确认按钮足够大，适合鼠标点击（游戏内操作精度要求） */
.ingame-btn {
  min-height: 44px;
  min-width: 140px;
  font-size: 14px;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

/* 隐藏非必要的横向导航 */
.app--ingame .sidebar-nav { display: none; }
.app--ingame .header-nav  { display: none; }
```

---

## 21.5 游戏事件监听（postMessage 桥接）

游戏客户端通过 `window.postMessage` 向 WebView 发送游戏内事件：

```typescript
// lib/gameEvents.ts

export type GameEvent =
  | { type: "PLAYER_ENTERED_RANGE"; assemblyId: string; distance: number }
  | { type: "PLAYER_LEFT_RANGE"; assemblyId: string }
  | { type: "INVENTORY_CHANGED"; characterId: string }
  | { type: "SYSTEM_CHANGED"; fromSystem: string; toSystem: string };

type GameEventHandler = (event: GameEvent) => void;

const handlers = new Set<GameEventHandler>();

// 启动监听（在应用启动时调用一次）
export function startGameEventListener() {
  window.addEventListener("message", (e) => {
    // 仅处理来自游戏客户端的消息（通过 origin 或约定的 source 字段验证）
    if (e.data?.source !== "EVEFrontierClient") return;

    const event = e.data as { source: string } & GameEvent;
    if (!event.type) return;

    for (const handler of handlers) {
      handler(event);
    }
  });
}

export function onGameEvent(handler: GameEventHandler) {
  handlers.add(handler);
  return () => handlers.delete(handler); // 返回取消订阅函数
}
```

### 在 React 中使用游戏事件

```tsx
// hooks/useGameEvents.ts
import { useEffect } from "react";
import { onGameEvent, GameEvent } from "../lib/gameEvents";

export function useGameEvent<T extends GameEvent["type"]>(
  type: T,
  handler: (event: Extract<GameEvent, { type: T }>) => void,
) {
  useEffect(() => {
    return onGameEvent((event) => {
      if (event.type === type) {
        handler(event as Extract<GameEvent, { type: T }>);
      }
    });
  }, [type, handler]);
}

// 使用场景：玩家进入星门范围时，自动弹出购票面板
function GatePanel() {
  const [nearGate, setNearGate] = useState<string | null>(null);

  useGameEvent("PLAYER_ENTERED_RANGE", (event) => {
    setNearGate(event.assemblyId);
  });

  useGameEvent("PLAYER_LEFT_RANGE", () => {
    setNearGate(null);
  });

  if (!nearGate) return null;

  return <JumpTicketPanel gateId={nearGate} />;
}
```

---

## 21.6 从游戏内发起签名请求

由于 EVE Vault 在游戏内已注入，签名请求直接弹出游戏内的 Vault UI：

```tsx
// components/InGameMarket.tsx
import { useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

export function InGameMarket({ gateId }: { gateId: string }) {
  const dAppKit = useDAppKit();
  const [status, setStatus] = useState("");

  const handleBuy = async () => {
    setStatus("请在右上角钱包确认交易...");

    const tx = new Transaction();
    tx.moveCall({
      target: `${TOLL_PKG}::toll_gate_ext::pay_toll_and_get_permit`,
      arguments: [/* ... */],
    });

    try {
      // 签名请求会触发游戏内置的 EVE Vault 弹窗
      const result = await dAppKit.signAndExecuteTransaction({
        transaction: tx,
      });
      setStatus("✅ 通行证已发放！");
    } catch (e: any) {
      if (e.message?.includes("User rejected")) {
        setStatus("❌ 已取消");
      } else {
        setStatus(`❌ ${e.message}`);
      }
    }
  };

  return (
    <div className="ingame-market">
      <div className="gate-info">
        <span>⛽ 通行费：10 SUI</span>
        <span>⏱ 有效期：30 分钟</span>
      </div>
      <button className="ingame-btn" onClick={handleBuy}>
        🚀 购买通行证
      </button>
      {status && <p className="status">{status}</p>}
    </div>
  );
}
```

---

## 21.7 响应式切换：同一套代码适配两种场景

```tsx
// App.tsx 完整示例
import { isInGame } from "./lib/environment";
import { startGameEventListener } from "./lib/gameEvents";
import { useEffect } from "react";

export function App() {
  useEffect(() => {
    if (isInGame) startGameEventListener();
  }, []);

  return (
    <EveFrontierProvider>
      {isInGame ? (
        // 游戏内：精简的单功能浮层
        <InGameOverlay />
      ) : (
        // 外部浏览器：完整功能仪表盘
        <FullDashboard />
      )}
    </EveFrontierProvider>
  );
}
```

---

## 21.8 游戏内 dApp 的 URL 配置

向玩家提供正确的 URL，他们可以在游戏设置中添加自定义 dApp：

```
你的 dApp 地址（在游戏内 WebView 打开）：
https://your-dapp.com?env=ingame

# 或通过游戏客户端的"自定义面板"功能添加
# 游戏会在 User-Agent 中自动附加 EVEFrontier/GameClient 标识
```

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| 两种访问模式 | 外部浏览器（完整）vs 游戏内 WebView（精简） |
| 环境检测 | `navigator.userAgent` 或查询参数判断 |
| UI 适配 | 小窗口、大字体、单步操作、高对比度 |
| 游戏事件监听 | `window.postMessage` + 事件分发器 |
| 签名无缝集成 | EVE Vault 已注入游戏内，API 完全相同 |
| 响应式切换 | 同一套代码，`isInGame` 条件渲染 |

## 📚 延伸阅读

- [dapp-kit 文档](../dapp-kit/dapp-kit.md)
- [EVE Vault 介绍](../eve-vault/introduction-to-eve-vault.md)
- [Chapter 5：dApp 前端开发](./chapter-05.md)
- [Chapter 18：全栈 dApp 架构](./chapter-18.md)
