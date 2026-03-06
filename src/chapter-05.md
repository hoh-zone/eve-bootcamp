# Chapter 5：dApp 前端开发与钱包集成

> ⏱ 预计学习时间：2 小时
>
> **目标：** 使用 `@evefrontier/dapp-kit` 构建一个能连接 EVE Vault 钱包、读取链上数据并执行交易的前端 dApp。

---

## 5.1 dApp 在 EVE Frontier 中的角色

当你完成了 Move 合约开发后，玩家需要一个界面来与你的设施交互。dApp（去中心化应用）就是这个界面，它可以：

- 显示你的智能组件的实时状态（库存、在线状态等）
- 让玩家连接 EVE Vault 钱包
- 通过 UI 触发链上交易（购买物品、申请跳跃许可等）
- 运行在标准 Web 浏览器中，无需下载游戏客户端

### 两种使用场景

| 场景 | 描述 |
|------|------|
| **游戏内浮窗** | 玩家在游戏内靠近组件时，游戏客户端显示你的 dApp（iframe） |
| **外部浏览器** | 独立网页，通过 EVE Vault 扩展连接钱包 |

---

## 5.2 安装 dapp-kit

```bash
# 创建 React 项目（以 Vite 为例）
npx create-vite my-dapp --template react-ts
cd my-dapp

# 安装 EVE Frontier dApp SDK 和依赖
npm install @evefrontier/dapp-kit @tanstack/react-query react
```

### SDK 核心功能一览

| 功能 | 提供内容 |
|------|--------|
| 🔌 **钱包连接** | 与 EVE Vault 和标准 Sui 钱包集成 |
| 📦 **智能对象数据** | 通过 GraphQL 获取并转换组件数据 |
| ⚡ **赞助交易** | 支持免 Gas 交易（由 EVE Frontier 后端代付） |
| 🔄 **自动轮询** | 实时刷新链上数据 |
| 🎨 **TypeScript 全类型** | 所有组件类型完整定义 |

---

## 5.3 项目基础配置

### 配置 Provider

所有 dApp 功能都必须包裹在 `EveFrontierProvider` 中：

```tsx
// src/main.tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { EveFrontierProvider } from '@evefrontier/dapp-kit'
import App from './App'

// React Query 客户端（管理缓存）
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 1000, // 5 秒后重新获取
    }
  }
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    {/* EVE Frontier SDK Provider */}
    <EveFrontierProvider queryClient={queryClient}>
      <App />
    </EveFrontierProvider>
  </React.StrictMode>
)
```

### 通过 URL 参数绑定组件

dApp 通过 URL 参数知道要显示哪个组件：

```
# 游戏内访问：
https://your-dapp.com/?tenant=utopia&itemId=0x1234abcd...

# tenant：游戏服务器实例名称（prod/testnet/dev）
# itemId：组件在链上的 ObjectID
```

SDK 会自动从 URL 读取这些参数，你无需手动处理。

---

## 5.4 核心 Hooks 详解

### Hook 1：useConnection（钱包连接状态）

```tsx
import { useConnection } from '@evefrontier/dapp-kit'

function WalletButton() {
  const {
    isConnected,          // boolean：是否已连接钱包
    currentAddress,       // string | null：当前钱包地址
    handleConnect,        // () => void：触发连接流程
    handleDisconnect,     // () => void：断开连接
  } = useConnection()

  if (!isConnected) {
    return (
      <button onClick={handleConnect} className="connect-btn">
        连接 EVE Vault 钱包
      </button>
    )
  }

  return (
    <div>
      <span>已连接：{currentAddress?.slice(0, 8)}...</span>
      <button onClick={handleDisconnect}>断开</button>
    </div>
  )
}
```

### Hook 2：useSmartObject（当前组件数据）

```tsx
import { useSmartObject } from '@evefrontier/dapp-kit'

function AssemblyStatus() {
  const {
    assembly,    // 当前组件的完整数据（库存、状态、名称等）
    loading,     // 是否正在加载
    error,       // 错误信息
    refetch,     // 手动刷新
  } = useSmartObject()

  if (loading) return <div className="spinner">读取链上数据中...</div>
  if (error) return <div className="error">错误：{error.message}</div>

  return (
    <div className="assembly-card">
      <h2>{assembly?.name}</h2>
      <p>状态：{assembly?.status}</p>
      <p>所有者：{assembly?.owner}</p>
    </div>
  )
}
```

### Hook 3：useNotification（用户通知）

```tsx
import { useNotification } from '@evefrontier/dapp-kit'

function ActionButton() {
  const { showNotification } = useNotification()

  const handleAction = async () => {
    try {
      // ... 执行交易 ...
      showNotification({ type: 'success', message: '交易成功！' })
    } catch (e) {
      showNotification({ type: 'error', message: '交易失败：' + e.message })
    }
  }

  return <button onClick={handleAction}>执行操作</button>
}
```

---

## 5.5 执行链上交易

### 标准交易（用户付 Gas）

使用 `@mysten/dapp-kit-react` 的 `useDAppKit` 来执行：

```tsx
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

function BuyItemButton({ storageUnitId, typeId }: Props) {
  const dAppKit = useDAppKit()

  const handleBuy = async () => {
    // 构建交易
    const tx = new Transaction()

    tx.moveCall({
      // 调用你发布的扩展合约函数
      target: `${MY_PACKAGE_ID}::vending_machine::buy_item`,
      arguments: [
        tx.object(storageUnitId),
        tx.object(CHARACTER_ID),
        tx.splitCoins(tx.gas, [tx.pure.u64(100)]),  // 支付 100 SUI
        tx.pure.u64(typeId),
      ],
    })

    // 签名并执行
    try {
      const result = await dAppKit.signAndExecuteTransaction({
        transaction: tx,
      })
      console.log('交易成功！', result.digest)
    } catch (e) {
      console.error('交易失败', e)
    }
  }

  return <button onClick={handleBuy}>购买物品</button>
}
```

### 赞助交易（Sponsored Tx，免 Gas）

当操作需要服务器验证或由平台代付 Gas 时：

```tsx
import { signAndExecuteSponsoredTransaction } from '@evefrontier/dapp-kit'

const result = await signAndExecuteSponsoredTransaction({
  transaction: tx,
  // SDK 自动处理赞助逻辑，与 EVE Frontier 后端通信
})
```

---

## 5.6 读取链上数据（GraphQL）

```typescript
import {
  getAssemblyWithOwner,
  getObjectWithJson,
  executeGraphQLQuery,
} from '@evefrontier/dapp-kit'

// 获取组件及其拥有者信息
async function loadAssembly(assemblyId: string) {
  const { moveObject, character } = await getAssemblyWithOwner(assemblyId)
  console.log('组件数据：', moveObject)
  console.log('拥有者角色：', character)
}

// 自定义 GraphQL 查询
async function queryGates() {
  const query = `
    query GetGates($type: String!) {
      objects(filter: { type: $type }, first: 10) {
        nodes {
          address
          asMoveObject { contents { json } }
        }
      }
    }
  `
  const data = await executeGraphQLQuery(query, {
    type: `${WORLD_PACKAGE}::gate::Gate`
  })
  return data
}
```

---

## 5.7 实用工具函数

```typescript
import {
  abbreviateAddress,
  isOwner,
  formatM3,
  formatDuration,
  getTxUrl,
  getDatahubGameInfo,
} from '@evefrontier/dapp-kit'

// 缩短地址：0x1234...cdef
abbreviateAddress('0x1234567890abcdef')

// 检查当前连接的钱包是否是指定对象的拥有者
const isMine = isOwner(assembly, currentAddress)

// 格式化体积
formatM3(1500)  // "1.5 m³"

// 格式化时间
formatDuration(3661000)  // "1h 1m 1s"

// 获取交易浏览器链接
getTxUrl('HNFaf...')  // 返回 Sui Explorer URL

// 获取游戏物品元数据（名称、图标等）
const info = await getDatahubGameInfo(83463)
console.log(info.name, info.iconUrl)
```

---

## 5.8 完整的 dApp 示例

```tsx
// src/App.tsx
import { useConnection, useSmartObject, useNotification } from '@evefrontier/dapp-kit'
import { useDAppKit } from '@mysten/dapp-kit-react'
import { Transaction } from '@mysten/sui/transactions'

export default function App() {
  const { isConnected, handleConnect, currentAddress } = useConnection()
  const { assembly, loading } = useSmartObject()
  const { showNotification } = useNotification()
  const dAppKit = useDAppKit()

  const handleJump = async () => {
    if (!isConnected) {
      showNotification({ type: 'warning', message: '请先连接钱包' })
      return
    }

    const tx = new Transaction()
    tx.moveCall({
      target: `${MY_PACKAGE}::toll_gate::pay_and_jump`,
      arguments: [
        tx.object(GATE_ID),
        tx.object(DEST_GATE_ID),
        tx.object(CHARACTER_ID),
        tx.splitCoins(tx.gas, [tx.pure.u64(100)]),
      ],
    })

    try {
      await dAppKit.signAndExecuteTransaction({ transaction: tx })
      showNotification({ type: 'success', message: '跃迁成功！' })
    } catch (e: any) {
      showNotification({ type: 'error', message: e.message })
    }
  }

  if (loading) return <div>Loading...</div>

  return (
    <div className="app">
      <header>
        <h1>🌀 星门控制台</h1>
        {!isConnected
          ? <button onClick={handleConnect}>连接钱包</button>
          : <span>✅ {currentAddress?.slice(0, 8)}...</span>
        }
      </header>

      <main>
        <div className="gate-info">
          <h2>{assembly?.name ?? 'Unknown Gate'}</h2>
          <p>状态：{assembly?.status}</p>
        </div>

        <button
          className="jump-btn"
          onClick={handleJump}
          disabled={!isConnected}
        >
          💳 支付 100 SUI 并跃迁
        </button>
      </main>
    </div>
  )
}
```

---

## 5.9 将 dApp 嵌入游戏

在游戏中靠近你的组件时，客户端会在浮窗中加载你注册的 dApp URL。配置方法：

1. 将 dApp 部署到公开 URL（如 Vercel、Netlify）
2. 在组件配置中设置你的 dApp URL
3. 游戏客户端会在玩家交互时自动打开并传入 `?itemId=...&tenant=...` 参数

相关文档：[Connecting In-Game](../dapps/connecting-in-game.md) | [Customizing External dApps](../dapps/customizing-external-dapps.md)

---

## 🔖 本章小结

| 知识点 | 核心要点 |
|--------|--------|
| Provider 配置 | `<EveFrontierProvider>` 包裹整个应用 |
| URL 参数 | `?tenant=&itemId=` 绑定链上组件 |
| `useConnection` | 钱包连接状态与操作 |
| `useSmartObject` | 自动轮询的组件链上数据 |
| 执行交易 | `dAppKit.signAndExecuteTransaction()` |
| 赞助交易 | `signAndExecuteSponsoredTransaction()` 免 Gas |
| 读取数据 | GraphQL / `getAssemblyWithOwner()` |

## 📚 延伸阅读

- [dapp-kit 完整文档](../dapp-kit/dapp-kit.md)
- [TypeDoc API 文档](http://sui-docs.evefrontier.com/)
- [Connecting from an External Browser](../dapps/connecting-from-an-external-browser.md)
- [@mysten/dapp-kit-react 文档](https://sdk.mystenlabs.com/dapp-kit)
