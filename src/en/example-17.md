# Practical Case 17: In-Game Overlay dApp Practice (Toll Station In-Game Version)

> **Objective:** Transform Example 2's stargate toll station dApp into an **in-game overlay version**—automatically pop up ticket purchase panel when player approaches stargate, complete signing and jumping without leaving the game.

---

> Status: Teaching example. Current case focuses on dApp overlay transformation, contract part reuses [Example 2](./example-02.md).

## Corresponding Code Directory

- [example-17/dapp](./code/example-17/dapp)

## Minimal Call Chain

`In-game event -> postMessage -> Overlay dApp updates state -> User signs -> Purchase/jump success -> Overlay closes`

## Requirements Analysis

**Scenario:** Toll station logic already exists (reuse Example 2 contract), now need to:

1. Game client detects player entering 100km range of stargate
2. Send event to WebView overlay via `postMessage`
3. Overlay pops up ticket purchase panel, displays fee and destination
4. Player clicks once, EVE Vault pops up signature confirmation
5. After signing completes, show success animation and auto-close

This case focuses on **Chapter 20 engineering practice**, with more complete code details.

---

## Project Structure

```
ingame-toll-overlay/
├── index.html
├── src/
│   ├── main.tsx                  # Entry, Provider setup
│   ├── App.tsx                   # Environment detection and routing
│   ├── overlay/
│   │   ├── TollOverlay.tsx       # In-game overlay main component
│   │   ├── JumpPanel.tsx         # Ticket purchase panel
│   │   └── SuccessAnimation.tsx  # Success animation
│   └── lib/
│       ├── gameEvents.ts         # postMessage listener
│       ├── environment.ts        # Environment detection
│       └── contracts.ts          # Contract constants
├── ingame.css                    # Overlay styles
└── vite.config.ts
```

---

## Part One: Game Event Listener

```typescript
// src/lib/gameEvents.ts

export interface GateAproachEvent {
  type: "GATE_IN_RANGE"
  gateId: string
  gateName: string
  destinationSystemName: string
  distanceKm: number
}

export interface PlayerLeftEvent {
  type: "GATE_OUT_OF_RANGE"
  gateId: string
}

export type OverlayEvent = GateAproachEvent | PlayerLeftEvent

type Listener = (event: OverlayEvent) => void
const listeners = new Set<Listener>()

let initialized = false

export function initGameEventListener() {
  if (initialized) return
  initialized = true

  window.addEventListener("message", (e: MessageEvent) => {
    if (e.data?.source !== "EVEFrontierClient") return
    const event = e.data as { source: string } & OverlayEvent
    if (!event.type) return
    listeners.forEach(fn => fn(event))
  })
}

export function addGameEventListener(fn: Listener): () => void {
  listeners.add(fn)
  return () => listeners.delete(fn)
}

// ── Development/testing: simulate game events ─────────────────────────────

export function simulateGateApproach(gateId: string) {
  const mockEvent: GateAproachEvent = {
    type: "GATE_IN_RANGE",
    gateId,
    gateName: "Alpha Gate Alpha-7",
    destinationSystemName: "Trade Hub IV",
    distanceKm: 78,
  }
  window.dispatchEvent(
    new MessageEvent("message", {
      data: { source: "EVEFrontierClient", ...mockEvent },
    })
  )
}
```

---

## Part Two: Main Overlay Component

```tsx
// src/overlay/TollOverlay.tsx
import { useEffect, useState, useCallback } from 'react'
import {
  initGameEventListener,
  addGameEventListener,
  GateAproachEvent,
} from '../lib/gameEvents'
import { JumpPanel } from './JumpPanel'
import { SuccessAnimation } from './SuccessAnimation'

type OverlayState = 'hidden' | 'visible' | 'success'

export function TollOverlay() {
  const [state, setState] = useState<OverlayState>('hidden')
  const [activeGate, setActiveGate] = useState<GateAproachEvent | null>(null)

  useEffect(() => {
    initGameEventListener()

    return addGameEventListener((event) => {
      if (event.type === 'GATE_IN_RANGE') {
        setActiveGate(event)
        setState('visible')
      } else if (event.type === 'GATE_OUT_OF_RANGE') {
        if (state !== 'success') setState('hidden')
      }
    })
  }, [state])

  const handleSuccess = useCallback(() => {
    setState('success')
    // Auto-close after 3 seconds
    setTimeout(() => {
      setState('hidden')
      setActiveGate(null)
    }, 3000)
  }, [])

  const handleDismiss = useCallback(() => {
    setState('hidden')
  }, [])

  if (state === 'hidden') return null

  return (
    <div className="overlay-container">
      <div className={`overlay-panel ${state === 'success' ? 'overlay-panel--success' : ''}`}>
        {state === 'success' ? (
          <SuccessAnimation />
        ) : (
          activeGate && (
            <JumpPanel
              gateEvent={activeGate}
              onSuccess={handleSuccess}
              onDismiss={handleDismiss}
            />
          )
        )}
      </div>
    </div>
  )
}
```

---

## Part Three: Ticket Purchase Panel

```tsx
// src/overlay/JumpPanel.tsx
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useCurrentClient } from '@mysten/dapp-kit-react'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'
import { GateAproachEvent } from '../lib/gameEvents'
import { TOLL_PKG, ADMIN_ACL_ID, CHARACTER_ID } from '../lib/contracts'

interface JumpPanelProps {
  gateEvent: GateAproachEvent
  onSuccess: () => void
  onDismiss: () => void
}

export function JumpPanel({ gateEvent, onSuccess, onDismiss }: JumpPanelProps) {
  const client = useCurrentClient()
  const dAppKit = useDAppKit()
  const [buying, setBuying] = useState(false)

  // Read toll for this stargate
  const { data: tollInfo } = useQuery({
    queryKey: ['gate-toll', gateEvent.gateId],
    queryFn: async () => {
      const obj = await client.getObject({
        id: gateEvent.gateId,
        options: { showContent: true },
      })
      const fields = (obj.data?.content as any)?.fields
      return {
        tollAmount: Number(fields?.toll_amount ?? 0),
        destinationGateId: fields?.linked_gate_id,
      }
    },
  })

  const tollSUI = ((tollInfo?.tollAmount ?? 0) / 1e9).toFixed(2)

  const handleBuy = async () => {
    if (!tollInfo) return
    setBuying(true)

    const tx = new Transaction()
    const [payment] = tx.splitCoins(tx.gas, [tx.pure.u64(tollInfo.tollAmount)])
    tx.moveCall({
      target: `${TOLL_PKG}::toll_gate_ext::pay_toll_and_get_permit`,
      arguments: [
        tx.object(gateEvent.gateId),      // Source stargate
        tx.object(tollInfo.destinationGateId), // Destination stargate
        tx.object(CHARACTER_ID),          // Character object
        payment,
        tx.object(ADMIN_ACL_ID),
        tx.object('0x6'),                 // Clock
      ],
    })

    try {
      // Call sponsored transaction (server verifies proximity then sponsors gas)
      await dAppKit.signAndExecuteSponsoredTransaction({ transaction: tx })
      onSuccess()
    } catch (e: any) {
      console.error(e)
      setBuying(false)
    }
  }

  return (
    <div className="jump-panel">
      {/* Close button */}
      <button className="dismiss-btn" onClick={onDismiss} aria-label="Close">✕</button>

      {/* Stargate info */}
      <div className="gate-icon">🌀</div>
      <h2 className="gate-name">{gateEvent.gateName}</h2>
      <p className="destination">
        Destination: <strong>{gateEvent.destinationSystemName}</strong>
      </p>
      <p className="distance">Distance: {gateEvent.distanceKm} km</p>

      {/* Fee */}
      <div className="toll-display">
        <span className="toll-label">Toll Fee</span>
        <span className="toll-amount">{tollSUI} SUI</span>
      </div>

      {/* Purchase button */}
      <button
        className="jump-btn"
        onClick={handleBuy}
        disabled={buying || !tollInfo}
      >
        {buying ? 'Signing...' : 'Purchase Ticket & Jump'}
      </button>

      <p className="jump-hint">Permit valid for 30 minutes</p>
    </div>
  )
}
```

---

## Part Four: Success Animation

```tsx
// src/overlay/SuccessAnimation.tsx
import { useEffect, useState } from 'react'

export function SuccessAnimation() {
  const [frame, setFrame] = useState(0)
  const frames = ['🌌', '⚡', '🌀', '✨', '🚀']

  useEffect(() => {
    const timer = setInterval(() => {
      setFrame(f => (f + 1) % frames.length)
    }, 200)
    return () => clearInterval(timer)
  }, [])

  return (
    <div className="success-animation">
      <div className="animation-icon">{frames[frame]}</div>
      <h2>Jump Successful!</h2>
      <p>Warping to destination...</p>
    </div>
  )
}
```

---

## In-Game Specific CSS

```css
/* ingame.css */
.overlay-container {
  position: fixed;
  right: 16px;
  top: 50%;
  transform: translateY(-50%);
  z-index: 9999;
  width: 320px;
}

.overlay-panel {
  background: rgba(8, 12, 24, 0.95);
  border: 1px solid rgba(96, 180, 255, 0.5);
  border-radius: 12px;
  padding: 20px;
  color: #d0e8ff;
  font-family: 'Share Tech Mono', monospace;
  backdrop-filter: blur(12px);
  animation: slideIn 0.25s ease;
  box-shadow: 0 0 30px rgba(96, 180, 255, 0.15);
}

@keyframes slideIn {
  from { opacity: 0; transform: translateX(30px); }
  to   { opacity: 1; transform: translateX(0); }
}

.jump-btn {
  width: 100%;
  padding: 14px;
  background: linear-gradient(135deg, #1a5cff, #0a3acc);
  border: none;
  border-radius: 8px;
  color: white;
  font-size: 15px;
  font-family: inherit;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  cursor: pointer;
  transition: all 0.2s;
}

.jump-btn:hover:not(:disabled) {
  background: linear-gradient(135deg, #2a6cff, #1a4aee);
  box-shadow: 0 0 20px rgba(26, 92, 255, 0.4);
}

.toll-display {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: rgba(255,255,255,0.05);
  border-radius: 8px;
  padding: 12px 16px;
  margin: 16px 0;
}

.toll-amount {
  font-size: 24px;
  font-weight: bold;
  color: #4fa3ff;
}

.success-animation {
  text-align: center;
  padding: 24px 0;
  animation-icon { font-size: 48px; }
}
```

---

## Related Documentation
- [Chapter 20: In-Game dApp Integration](./chapter-20.md)
- [Chapter 8: Sponsored Transactions](./chapter-08.md)
- [Example 2: Stargate Toll Station (Contract Layer)](./example-02.md)
