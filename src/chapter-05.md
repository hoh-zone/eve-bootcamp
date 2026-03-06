# Chapter 5：dApp 前端开发与钱包集成

> **目标：** 使用 `@evefrontier/dapp-kit` 构建一个能连接 EVE Vault 钱包、读取链上数据并执行交易的前端 dApp。

---

> 状态：基础章节。正文以钱包接入、前端状态读取和交易发起为主。

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

很多人会把 dApp 误解成“给合约包一层前端皮肤”。在 EVE Frontier 里，它更准确的角色是：

> 把链上设施变成玩家真的愿意使用的服务界面。

因为同一个设施，如果只有合约，没有 dApp，玩家通常会缺少这些关键信息：

- 当前状态是什么
- 自己是否有权限操作
- 操作要花多少钱
- 点完按钮之后到底发生了什么

所以 dApp 不只是“展示层”，它还承担三类非常实际的责任：

- **解释状态**
  把对象字段翻译成玩家看得懂的业务状态
- **组织交易**
  帮用户把复杂参数、对象 ID、金额拼成一次合法交易
- **处理反馈**
  告诉用户现在是等待签名、等待上链、成功、失败还是需要重试

### 一个 dApp 的最小工作回路

无论你做的是商店、星门还是炮塔控制台，前端基本都绕不开这个循环：

```text
连接钱包
  -> 读取组件和用户状态
  -> 判断当前允许的动作
  -> 构建交易
  -> 请求签名 / 发起赞助交易
  -> 等待结果
  -> 刷新对象和界面
```

只要这个循环里有一环没做好，用户体验就会断掉。

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

`Provider` 的作用不只是“让 Hook 能用”。它实际上帮你统一管理了三类上下文：

- 钱包连接上下文
- 链上查询与缓存上下文
- dApp-kit 自己的环境信息

所以它本质上是整个 dApp 的“运行底座”。如果这层配错，后面很多看起来像业务问题的报错，其实都是上下文没初始化好。

### 通过 URL 参数绑定组件

dApp 通过 URL 参数知道要显示哪个组件：

```
# 游戏内访问：
https://your-dapp.com/?tenant=utopia&itemId=0x1234abcd...

# tenant：游戏服务器实例名称（prod/testnet/dev）
# itemId：组件在链上的 ObjectID
```

SDK 会自动从 URL 读取这些参数，你无需手动处理。

这里的核心思想是：

> 同一个前端页面，不是固定服务某一个组件，而是按 URL 动态绑定当前组件上下文。

这有两个直接好处：

- 你可以复用同一套前端去服务很多个设施
- 游戏内浮层只需要把 `tenant` 和 `itemId` 传进来，就能让页面知道“我现在在给谁服务”

### `tenant` 和 `itemId` 为什么缺一不可？

- `itemId` 解决“是哪一个对象”
- `tenant` 解决“它属于哪一个世界实例”

如果只传 `itemId`，在多租户或多环境场景下，很容易把数据读错世界；如果只传 `tenant`，你又不知道当前到底是哪个设施对象。

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

`useConnection` 解决的不是“能不能弹出钱包”这么简单，而是整个页面的第一层状态分叉：

- 没连钱包时，页面只能展示公共信息
- 已连钱包但没角色时，页面可能要提示先初始化身份
- 已连钱包且有角色时，页面才能进入真正的交互态

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

这里最重要的不是 Hook 名字，而是你要养成一个习惯：

> 页面应该始终以“链上对象状态”为中心，而不是以本地按钮状态为中心。

也就是说，用户点完按钮之后，不要只是在前端本地把 `status = success`。更稳的做法是：

1. 等交易返回
2. 重新读取对象
3. 以链上真实状态来刷新 UI

否则你很容易出现：

- 前端以为成功了
- 但链上对象没变
- 页面却还显示“操作已完成”

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

通知系统真正的价值，不是“做个弹窗”，而是把链上异步流程拆成用户能理解的几个阶段：

- 正在连接钱包
- 等待签名
- 正在上链
- 已确认
- 失败，需要重试

如果你只给用户一个“成功 / 失败”，很多复杂交易都会显得像黑盒。

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

### 一笔前端交易通常分成哪几步？

从前端视角看，一笔交易至少分成 5 个阶段：

1. **准备参数**
   组件 ID、角色 ID、金额、类型参数是否齐全
2. **构建交易**
   把对象、纯值、拆币动作和函数入口拼成 `Transaction`
3. **请求签名**
   让钱包或赞助服务确认这笔交易
4. **提交执行**
   交易真正进入链上执行
5. **回写界面**
   根据 digest 和最新对象状态刷新 UI

前端很多 bug 都不是出在“交易失败”，而是出在第 1 步和第 5 步：

- 参数拿错了对象
- 本地用的是旧缓存
- 交易成功了但页面没刷新
- digest 有了但对象查询还没更新

### 赞助交易（Sponsored Tx，免 Gas）

当操作需要服务器验证或由平台代付 Gas 时：

```tsx
import { signAndExecuteSponsoredTransaction } from '@evefrontier/dapp-kit'

const result = await signAndExecuteSponsoredTransaction({
  transaction: tx,
  // SDK 自动处理赞助逻辑，与 EVE Frontier 后端通信
})
```

赞助交易的体验更好，但链路也更长。它通常意味着：

1. 前端先构建交易
2. 请求后端检查是否允许赞助
3. 后端进行风控 / 补签 / 代付
4. 用户完成必要签名
5. 交易再被提交执行

所以一旦赞助交易失败，你排查时不能只盯前端，还要分辨问题出在哪一层：

- 是前端构建错了交易
- 是用户资格不满足
- 是后端拒绝赞助
- 是钱包签名阶段失败
- 是链上执行本身失败

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

### 为什么前端不能只靠事件流？

因为前端页面通常需要的是“当前状态”，而不只是“历史发生过什么”。

事件更适合回答：

- 谁在什么时候做过什么
- 某个动作有没有发生
- 用于日志、通知、时间线

对象查询更适合回答：

- 这个设施现在是什么状态
- 当前库存还有多少
- 当前所有者是谁
- 当前是否在线

所以成熟的 dApp 往往是：

- 用对象查询拿当前态
- 用事件查询补历史和时间线

只靠事件去还原当前态，通常会越来越脆弱。

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

这类工具函数看起来像边角料，但它们直接决定你的前端会不会显得“像产品而不是脚本页面”。

比如：

- 地址不缩写，页面就会难读
- 金额和体积不格式化，玩家就很难快速判断
- 没有交易链接，出问题时用户和开发者都无法追踪

前端产品感，很多时候就是靠这些小函数堆出来的。

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

这个示例虽然简单，但它已经完整展示了一个最小交互回路：

- 连接钱包
- 读取当前组件
- 构建交易
- 请求签名并执行
- 给出结果通知

### 真实项目里通常还要再补三层状态

示例能跑，但如果你要把它做成稳定产品，通常还要再补：

1. **本地 UI 状态**
   例如按钮 loading、弹窗开关、表单输入
2. **钱包状态**
   当前地址、是否已授权、是否切错网络
3. **链上对象状态**
   设施状态、库存、价格、当前拥有者

这三层状态不要混成一层。它们更新速度不同、可信度不同、排查方法也不同。

---

## 5.9 将 dApp 嵌入游戏

在游戏中靠近你的组件时，客户端会在浮窗中加载你注册的 dApp URL。配置方法：

1. 将 dApp 部署到公开 URL（如 Vercel、Netlify）
2. 在组件配置中设置你的 dApp URL
3. 游戏客户端会在玩家交互时自动打开并传入 `?itemId=...&tenant=...` 参数

相关文档：[Connecting In-Game](https://github.com/evefrontier/builder-documentation/blob/main/dapps/connecting-in-game.md) | [Customizing External dApps](https://github.com/evefrontier/builder-documentation/blob/main/dapps/customizing-external-dapps.md)

### 游戏内浮层和外部浏览器最大的差异

两者虽然都叫 dApp，但运行约束并不完全一样：

- **游戏内浮层**
  更像受宿主环境控制的嵌入页，重点是快、稳、参数明确、交互路径短
- **外部浏览器**
  更像独立 Web 应用，可以容纳更完整的页面结构和更长的交互流程

所以你在做游戏内 dApp 时，通常要额外注意：

- 页面首屏必须快
- 不能依赖太复杂的多页跳转
- 参数丢失时要有兜底提示
- 钱包未连接、角色未初始化、设施未在线时要有明确状态页

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

- [dapp-kit 完整文档](https://github.com/evefrontier/builder-documentation/blob/main/dapp-kit/dapp-kit.md)
- [TypeDoc API 文档](http://sui-docs.evefrontier.com/)
- [Connecting from an External Browser](https://github.com/evefrontier/builder-documentation/blob/main/dapps/connecting-from-an-external-browser.md)
- [@mysten/dapp-kit-react 文档](https://sdk.mystenlabs.com/dapp-kit)
