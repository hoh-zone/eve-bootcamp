# Chapter 20: In-Game dApp Integration (Overlay UI and Event Communication)

> **Objective:** Master how to embed your dApp into the EVE Frontier game client as a floating panel, enabling seamless interaction between in-game and on-chain data, and initiating signing requests from within the game without switching to an external browser.

---

> Status: Integration chapter. Main content focuses on in-game WebView, overlay UI, and event communication.

##  20.1 Two dApp Access Modes

EVE Frontier supports two ways to access your dApp:

| Mode | Entry Point | Suitable Scenarios |
|------|------|--------|
| **External Browser** | Player manually opens webpage | Admin panels, data analytics, settings pages |
| **In-Game Overlay** | Embedded WebView in game client | Transaction popups, real-time status, combat assistance |

In-game integration provides a smoother user experience: players can complete purchases, check inventory, and sign transactions without leaving the game.

The most important point of this chapter is not "WebView can also open webpages," but rather:

> The same dApp actually plays different roles when accessed in-game versus in an external browser.

External browser is more like a complete backend:

- High information density
- Longer operation chains
- Suitable for management, analysis, configuration

In-game overlay is more like an instant tool:

- Must be fast
- Must be brief
- Must be strongly relevant to the current context

If you make both entry points exactly the same, typically both experiences will suffer.

---

##  20.2 How In-Game WebView Works

EVE Frontier client has a built-in Chromium WebView that can load external URLs:

```
Game Client (Unity/Electron)
    └── WebView Component
          └── Load your dApp URL (https://your-dapp.com)
                └── Communicate with EVE Vault (injected in-game)
```

**Key Point**: EVE Vault is injected into the game's WebView `window` object and shares the same Wallet Standard API as the external browser extension, so the same `@mysten/dapp-kit` code **requires no modification** to run in both modes.

### But "API compatibility" doesn't equal "experience equivalence"

Technically you can reuse the same wallet integration code, but that doesn't mean you can blindly copy-paste the entire product flow.

In-game environments typically face additional constraints:

- Smaller page space
- Shorter player attention span
- Operations may occur while in combat or moving
- Host environment decides open/close timing

So what should actually be reused is the underlying capability, not the entire interaction rhythm.

---

##  20.3 Detecting Current Runtime Environment

Your dApp needs to know whether it's running in-game or in an external browser to make appropriate UI adjustments:

```typescript
// lib/environment.ts

export type RunEnvironment = "in-game" | "external-browser" | "unknown";

export function detectEnvironment(): RunEnvironment {
  // EVE Frontier client injects an identifier in WebView's navigator.userAgent
  const ua = navigator.userAgent;

  if (ua.includes("EVEFrontier/GameClient")) {
    return "in-game";
  }

  // Can also detect via custom query parameter
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

### What does environment detection really serve?

It's not just to set an `isInGame` flag, but to help the page decide:

- Which layout should currently be rendered
- Whether certain buttons should be hidden
- Whether to listen to the game event bridge
- Whether certain complex operations should redirect to external browser

In other words, environment detection is not a presentation layer trick, but part of interaction routing.

---

##  20.4 In-Game Overlay UI Design Principles

In-game UI has different design requirements from external web pages:

| External Browser | In-Game Overlay |
|----------|---------|
| Full-screen layout | **Small window** (typically 400×600px) |
| Standard font size | Larger fonts, high contrast |
| Hover tooltips | Avoid hover (uncertain if focus is on game or UI) |
| Multi-step forms | Single-step operations, minimize input |
| Non-streaming animations | Lightweight animations (prevent blocking game view) |

```css
/* ingame.css - In-game overlay exclusive styles */
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
  font-size: 15px;      /* Slightly larger than standard */
  font-family: 'Share Tech Mono', monospace;  /* EVE style font */
}

/* Ensure buttons are large enough for mouse clicks (in-game precision requirements) */
.ingame-btn {
  min-height: 44px;
  min-width: 140px;
  font-size: 14px;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

/* Hide non-essential horizontal navigation */
.app--ingame .sidebar-nav { display: none; }
.app--ingame .header-nav  { display: none; }
```

### Most common mistakes with in-game overlays

#### 1. Forcing a backend page into an overlay

The result is:

- Information density too high
- Buttons too small
- User has no idea what the most important action is

#### 2. Making confirmation flows too long

In-game is suitable for:

- Single-step confirmation
- Immediate operations on current object
- Strongly context-relevant actions

Not suitable for:

- Long forms
- Multi-page setup wizards
- Complex filtering backends

#### 3. Visually too "webpage-like," not enough "embedded tool-like"

Overlays should look more like a control panel for the current facility, not an independent website homepage.

---

##  20.5 Game Event Listening (postMessage Bridge)

Game client sends in-game events to WebView via `window.postMessage`:

```typescript
// lib/gameEvents.ts

export type GameEvent =
  | { type: "PLAYER_ENTERED_RANGE"; assemblyId: string; distance: number }
  | { type: "PLAYER_LEFT_RANGE"; assemblyId: string }
  | { type: "INVENTORY_CHANGED"; characterId: string }
  | { type: "SYSTEM_CHANGED"; fromSystem: string; toSystem: string };

type GameEventHandler = (event: GameEvent) => void;

const handlers = new Set<GameEventHandler>();

// Start listener (call once at app startup)
export function startGameEventListener() {
  window.addEventListener("message", (e) => {
    // Only handle messages from game client (verify via origin or agreed source field)
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
  return () => handlers.delete(handler); // Return unsubscribe function
}
```

### The most important part of event bridge is not "can receive messages," but stable message semantics

A mature message bridge protocol should at least ensure:

- Stable event types
- Stable field names and meanings
- Frontend can safely degrade when fields are missing
- Both frontend and backend know which events are one-time triggers vs. state syncs

Otherwise, when the game client changes a field, the frontend will fail silently in the most difficult environment to debug.

### Using Game Events in React

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

// Use case: Auto-open ticket panel when player enters stargate range
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

### Don't treat game events as on-chain truth

Event bridges are best suited for:

- Current context prompts
- UI popup/close
- Current object context switching

But actions truly involving assets and permissions should still rely on on-chain objects and formal verification processes.

In other words:

- Game events tell you "the player probably wants to operate on this object now"
- On-chain data tells you "what state this object is actually in right now"

---

##  20.6 Initiating Signing Requests from In-Game

Since EVE Vault is injected in-game, signing requests directly trigger the game's built-in Vault UI:

```tsx
// components/InGameMarket.tsx
import { useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

export function InGameMarket({ gateId }: { gateId: string }) {
  const dAppKit = useDAppKit();
  const [status, setStatus] = useState("");

  const handleBuy = async () => {
    setStatus("Please confirm transaction in top-right wallet...");

    const tx = new Transaction();
    tx.moveCall({
      target: `${TOLL_PKG}::toll_gate_ext::pay_toll_and_get_permit`,
      arguments: [/* ... */],
    });

    try {
      // Signing request triggers game's built-in EVE Vault popup
      const result = await dAppKit.signAndExecuteTransaction({
        transaction: tx,
      });
      setStatus("✅ Permit issued!");
    } catch (e: any) {
      if (e.message?.includes("User rejected")) {
        setStatus("❌ Cancelled");
      } else {
        setStatus(`❌ ${e.message}`);
      }
    }
  };

  return (
    <div className="ingame-market">
      <div className="gate-info">
        <span>⛽ Toll: 10 SUI</span>
        <span>⏱ Validity: 30 minutes</span>
      </div>
      <button className="ingame-btn" onClick={handleBuy}>
        🚀 Purchase Permit
      </button>
      {status && <p className="status">{status}</p>}
    </div>
  );
}
```

### The key to in-game signing experience is not "can sign," but "don't interrupt user flow"

The best in-game signing flows typically have these characteristics:

- Clearly communicate key costs before signing
- Can quickly return to original context after failure
- Immediately show current object state change after success

If users feel like signing is suddenly switching out to do an external wallet task, the value of in-game integration drops significantly.

---

##  20.7 Responsive Switching: Same Codebase Adapts to Both Scenarios

```tsx
// App.tsx complete example
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
        // In-game: Streamlined single-function overlay
        <InGameOverlay />
      ) : (
        // External browser: Full-featured dashboard
        <FullDashboard />
      )}
    </EveFrontierProvider>
  );
}
```

---

##  20.8 In-Game dApp URL Configuration

Provide players with the correct URL to add custom dApps in game settings:

```
Your dApp address (opens in game WebView):
https://your-dapp.com?env=ingame

# Or add via game client's "Custom Panel" feature
# Game will automatically attach EVEFrontier/GameClient identifier in User-Agent
```

---

## 🔖 Chapter Summary

| Knowledge Point | Core Takeaway |
|--------|--------|
| Two access modes | External browser (complete) vs in-game WebView (streamlined) |
| Environment detection | `navigator.userAgent` or query parameter detection |
| UI adaptation | Small window, large fonts, single-step operations, high contrast |
| Game event listening | `window.postMessage` + event dispatcher |
| Seamless signing integration | EVE Vault injected in-game, identical API |
| Responsive switching | Same codebase, `isInGame` conditional rendering |

## 📚 Further Reading

- [dapp-kit documentation](https://github.com/evefrontier/builder-documentation/blob/main/dapp-kit/dapp-kit.md)
- [EVE Vault Introduction](https://github.com/evefrontier/builder-documentation/blob/main/eve-vault/introduction-to-eve-vault.md)
- [Chapter 5: dApp Frontend Development](./chapter-05.md)
- [Chapter 19: Full-Stack dApp Architecture](./chapter-19.md)
