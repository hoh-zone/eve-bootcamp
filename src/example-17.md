# 实战案例 17：游戏内浮层 dApp 实战（收费站游戏内版）

> ⏱ 预计练习时间：2 小时
>
> **目标：** 将 Example 2 的星门收费站 dApp 改造为**游戏内浮层版本**——玩家靠近星门时自动弹出购票面板，可在不离开游戏的情况下完成签名和跳跃。

---

> 状态：教学示例。当前案例以 dApp 浮层改造为主，合约部分沿用 [Example 2](./example-02.md)。

## 前置依赖

- 需要先完成 [Example 2](./example-02.md)
- 建议先读 [Chapter 21](./chapter-21.md) 与 [Chapter 35](./chapter-35.md)
- 需要本地 `pnpm`、WebView/浏览器调试环境、EVE Vault

## 对应代码目录

- [example-17/dapp](./code/example-17/dapp)

## 源码位置

- [dapp/readme.md](./code/example-17/dapp/readme.md)
- [src/main.tsx](./code/example-17/dapp/src/main.tsx)
- [src/App.tsx](./code/example-17/dapp/src/App.tsx)
- [src/AssemblyInfo.tsx](./code/example-17/dapp/src/AssemblyInfo.tsx)
- 合约侧沿用 [Example 2](./example-02.md) 与 [example-02 code](./code/example-02)

## 关键测试文件

- 当前目录未附独立自动化测试；建议至少补一条 `postMessage -> 浮层渲染` 的前端测试

## 推荐阅读顺序

1. 先看 [Example 2](./example-02.md) 的收费站逻辑
2. 再读 [example-17 dapp/App.tsx](./code/example-17/dapp/src/App.tsx)
3. 最后验证 `postMessage` 与钱包签名协作

## 最小调用链

`游戏内事件 -> postMessage -> 浮层 dApp 更新状态 -> 用户签名 -> 购票/跳跃成功 -> 浮层关闭`

## 验证步骤

1. 在 [example-17/dapp](./code/example-17/dapp) 运行 `pnpm install && pnpm dev`
2. 模拟 `postMessage` 输入，确认面板自动打开
3. 用 EVE Vault 完成购票与跳跃闭环

## 常见报错

- `postMessage` 来源校验过松或过严
- 浮层状态和钱包连接状态不同步
- 游戏事件发生后未做幂等处理，导致重复弹窗

## 需求分析

**场景：** 收费站逻辑已经存在（重用 Example 2 的合约），现在要：

1. 游戏客户端检测到玩家进入星门 100km 范围
2. 通过 `postMessage` 发送事件至 WebView 浮层
3. 浮层弹出购票面板，显示费用和目的地
4. 玩家一键点击，EVE Vault 弹出签名确认
5. 签名完成后，显示成功动画并自动关闭

这个案例聚焦于 **Chapter 21 的工程实践**，代码细节更完整。

---

## 项目结构

```
ingame-toll-overlay/
├── index.html
├── src/
│   ├── main.tsx                  # 入口，Provider 设置
│   ├── App.tsx                   # 环境检测和路由
│   ├── overlay/
│   │   ├── TollOverlay.tsx       # 游戏内浮层主组件
│   │   ├── JumpPanel.tsx         # 购票面板
│   │   └── SuccessAnimation.tsx  # 成功动画
│   └── lib/
│       ├── gameEvents.ts         # postMessage 监听
│       ├── environment.ts        # 环境检测
│       └── contracts.ts          # 合约常量
├── ingame.css                    # 浮层样式
└── vite.config.ts
```

---

## 第一部分：游戏事件监听

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

// ── 开发/测试用：模拟游戏事件 ─────────────────────────────

export function simulateGateApproach(gateId: string) {
  const mockEvent: GateAproachEvent = {
    type: "GATE_IN_RANGE",
    gateId,
    gateName: "Alpha Gate Alpha-7",
    destinationSystemName: "贸易枢纽 IV",
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

## 第二部分：主浮层组件

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
    // 3 秒后自动关闭
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

## 第三部分：购票面板

```tsx
// src/overlay/JumpPanel.tsx
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useSuiClient } from '@mysten/dapp-kit'
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
  const client = useSuiClient()
  const dAppKit = useDAppKit()
  const [buying, setBuying] = useState(false)

  // 读取该星门的通行费
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
        tx.object(gateEvent.gateId),      // 源星门
        tx.object(tollInfo.destinationGateId), // 目的星门
        tx.object(CHARACTER_ID),          // 角色对象
        payment,
        tx.object(ADMIN_ACL_ID),
        tx.object('0x6'),                 // Clock
      ],
    })

    try {
      // 调用赞助交易（服务器验证临近性后代付 Gas）
      await dAppKit.signAndExecuteSponsoredTransaction({ transaction: tx })
      onSuccess()
    } catch (e: any) {
      console.error(e)
      setBuying(false)
    }
  }

  return (
    <div className="jump-panel">
      {/* 关闭按钮 */}
      <button className="dismiss-btn" onClick={onDismiss} aria-label="关闭">✕</button>

      {/* 星门信息 */}
      <div className="gate-icon">🌀</div>
      <h2 className="gate-name">{gateEvent.gateName}</h2>
      <p className="destination">
        目的地：<strong>{gateEvent.destinationSystemName}</strong>
      </p>
      <p className="distance">📡 距离：{gateEvent.distanceKm} km</p>

      {/* 费用 */}
      <div className="toll-display">
        <span className="toll-label">通行费</span>
        <span className="toll-amount">{tollSUI} SUI</span>
      </div>

      {/* 购票按钮 */}
      <button
        className="jump-btn"
        onClick={handleBuy}
        disabled={buying || !tollInfo}
      >
        {buying ? '⏳ 签名中...' : '🚀 购票并跳跃'}
      </button>

      <p className="jump-hint">通行证有效期 30 分钟</p>
    </div>
  )
}
```

---

## 第四部分：成功动画

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
      <h2>跳跃成功！</h2>
      <p>正在传送至目的地...</p>
    </div>
  )
}
```

---

## 游戏内专用 CSS

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

## 📚 关联文档
- [Chapter 21：游戏内 dApp 集成](./chapter-21.md)
- [Chapter 11：赞助交易](./chapter-11.md)
- [Example 2：星门收费站（合约层）](./example-02.md)
