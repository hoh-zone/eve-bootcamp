# Chapter 21：游戏内 dApp 集成（浮层 UI 与事件通信）

> **目标：** 掌握如何将你的 dApp 嵌入 EVE Frontier 游戏客户端作为悬浮面板，实现游戏内与链上数据的无缝交互，以及如何从游戏内发起签名请求而无需切换到外部浏览器。

---

> 状态：集成章节。正文以游戏内 WebView、浮层 UI 和事件通信为主。

## 21.1 两种 dApp 访问模式

EVE Frontier 支持两种访问你的 dApp 的方式：

| 模式 | 入口 | 适合场景 |
|------|------|--------|
| **外部浏览器** | 玩家手动打开网页 | 管理面板、数据分析、设置页 |
| **游戏内浮层** | 游戏客户端内嵌 WebView | 交易弹窗、实时状态、战斗辅助 |

游戏内集成提供更流畅的用户体验：玩家无需切出游戏就能完成购买、查看库存、签署交易。

这章最重要的不是“WebView 里也能打开网页”，而是：

> 同一套 dApp，在游戏内和外部浏览器里扮演的角色其实不一样。

外部浏览器更像完整后台：

- 信息量大
- 操作链更长
- 适合管理、分析、配置

游戏内浮层更像即时工具：

- 必须快
- 必须短
- 必须对当前场景强相关

如果你把两种入口做成完全一样，通常两边体验都会打折。

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

### 但“API 兼容”不等于“体验等价”

技术上可以复用同一套钱包接入代码，不代表你可以无脑照搬整个产品流。

游戏内环境通常会额外受到这些约束：

- 页面空间更小
- 玩家注意力更短
- 操作时可能仍在战斗或移动
- 宿主环境会决定打开/关闭时机

所以真正该复用的是底层能力，而不是整套交互节奏。

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

### 环境检测真正要服务什么？

不是为了打一个 `isInGame` 标记，而是为了让页面决定：

- 当前该渲染哪套布局
- 某些按钮是否应该隐藏
- 是否要监听游戏事件桥
- 某些复杂操作是否该引导到外部浏览器完成

也就是说，环境检测不是展示层小技巧，而是交互路由的一部分。

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

### 游戏内浮层最容易犯的错

#### 1. 把后台页面硬塞进浮层

结果就是：

- 信息密度过高
- 按钮太小
- 用户根本不知道当前最重要的动作是什么

#### 2. 把确认流程做得过长

游戏内适合：

- 单步确认
- 当前对象的即时操作
- 强场景相关动作

不太适合：

- 长表单
- 多页设置向导
- 复杂筛选后台

#### 3. 视觉上太“网页”，不够“嵌入式工具”

浮层更应该像一个面向当前设施的控制面板，而不是独立网站首页。

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

### 事件桥最重要的不是“能收到消息”，而是消息语义稳定

一个成熟的消息桥接协议，至少应该保证：

- 事件类型稳定
- 字段名和字段含义稳定
- 缺失字段时前端能安全降级
- 前后端都知道哪些事件是一次性触发、哪些是状态同步

否则游戏客户端一改字段，前端会在最难排查的环境里静默出错。

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

### 游戏事件不要直接当作链上真相

事件桥最适合做：

- 当前场景提示
- UI 弹出/关闭
- 当前对象上下文切换

但真正涉及资产和权限的动作，仍然应该回到链上对象和正式验证流程上来。

换句话说：

- 游戏事件告诉你“玩家现在可能想操作谁”
- 链上数据告诉你“这个对象现在到底处于什么状态”

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

### 游戏内签名体验的关键不是“能签”，而是“别打断用户节奏”

最好的游戏内签名流程通常具备这些特征：

- 签名前就把关键成本讲清楚
- 失败后能快速回到原场景
- 成功后立刻给出当前对象状态变化

如果用户每次签名都像突然切出去做一件外部钱包任务，那游戏内集成价值会大幅下降。

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

- [dapp-kit 文档](https://github.com/evefrontier/builder-documentation/blob/main/dapp-kit/dapp-kit.md)
- [EVE Vault 介绍](https://github.com/evefrontier/builder-documentation/blob/main/eve-vault/introduction-to-eve-vault.md)
- [Chapter 5：dApp 前端开发](./chapter-05.md)
- [Chapter 18：全栈 dApp 架构](./chapter-18.md)
