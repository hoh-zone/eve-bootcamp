# EVE Frontier 案例 dApp 运行指南

为了方便你在学习实战案例时能直观地与智能合约进行交互，我们在本目录为所有 18 个 Example 分别生成了配套的 React / dApp 前端工程。

为了极大地节省磁盘空间并加快安装速度，所有的 dApp 都在这个目录（`src/code/`）被配置为了一个 **pnpm workspace (Monorepo)**。

---

## 🚀 1. 首次配置与安装

在运行任何一个案例之前，你需要先在 `src/code/` 根目录下完成依赖安装。

确保你已经安装了 [Node.js](https://nodejs.org/) 和 [pnpm](https://pnpm.io/zh/installation)。

打开终端，进入 `code` 目录：
```bash
cd EVE-Builder-Course/src/code
```

安装所有项目的共享依赖：
```bash
pnpm install
```

*(提示：这个步骤可能需要1-2分钟，取决于你的网络情况，只需执行一次。)*

---

## 🎮 2. 运行指定的案例 dApp

每一个案例（如 Example 01、Example 10）都有自己专属的前端包，命名规则为 `evefrontier-example-XX-dapp`。

假设你现在正在学习 **[Example 1: 炮塔白名单 (MiningPass)](../example-01.md)**，你想启动它的交互界面。

在 `code` 目录下，运行以下指令：
```bash
pnpm run dev --filter evefrontier-example-01-dapp
```
*(你只需要把 `01` 换成你想要测试的章节编号，比如 `05`、`18` 即可)*

终端会输出类似于以下的启动信息：
```bash
  VITE v6.4.0  ready in 134 ms
  ➜  Local:   http://localhost:5173/
```

**点击或在浏览器打开 `http://localhost:5173/`**，你就能看到该案例专属的前端界面了！

---

## 🛠 3. 页面功能说明

打开案例页面后，你会看到：
1. **Connect EVE Vault** (右上角)：点击此按钮可拉起 EVE Vault 钱包浏览器扩展进行连接。
2. **案例主题标题**：显示当前正在测试的案例（例如："Example 1: 炮塔白名单 (MiningPass)"）。
3. **交互动作按钮**：点击大蓝框中的功能按钮（例如："Mint MiningPass NFT"）。
   - 如果钱包尚未连接，会提示 `Please connect your EVE Vault wallet to interact with this dApp.`
   - 按钮点击后将自动触发对应 `target` 的 Move 合约调用，你可以在弹出的 EVE Vault 扩展面板上批准/确认这笔交易。
   - 打开浏览器的“开发者工具 (F12) -> Console”可以查看详细的交易执行日志或失败报错。

---

## 🏗 (进阶) 全部项目构建检查

如果你修改了 TypeScript 源码或 `App.tsx`，想要检查是否破坏了代码，可以在 `code` 目录使用聚合构建命令：

```bash
pnpm run build
```
这会顺次编译全部 18 个案例的前端代码，如果有语法错误，TS 编译器会明确给出报错的位置。
