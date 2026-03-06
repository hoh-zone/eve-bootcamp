# 术语表

本页统一解释课程中高频出现、且容易在不同章节里重复出现的术语。阅读 Chapter 24-35 与 Example 11-18 时，建议把本页当作速查表。

## AdminACL

World 合约中的服务端授权控制对象。游戏服务器或 Builder 后端会把被允许的 sponsor 地址写入 `AdminACL`，链上逻辑通过 `verify_sponsor` 等校验函数确认调用者是否具备“服务器代表”身份。

## OwnerCap

对象或设施的所有权凭证。很多 World 侧权限检查并不只看 `ctx.sender()`，而是要求调用方显式持有与目标对象关联的 `OwnerCap`。

## AdminCap

Builder 自己模块中的管理员能力对象。它通常在 `init` 时发给发布者，用来写配置、修改规则、暂停功能或提取资金。

## Typed Witness

一种通过类型系统收紧授权边界的模式。EVE Frontier 的 Gate / Turret / Storage Unit 扩展经常用它约束“只有特定模块、特定入口”才能调用敏感 API。

## Shared Object

Sui 上可被多方并发访问的共享对象。World 里的 Gate、Storage Unit、Registry 这一类设施经常采用该模型。

## Derived Object

基于父对象和业务键确定性派生出的对象 ID。KillMail、注册表子对象等场景用它来保证 `业务 ID -> 链上对象 ID` 是稳定且不可重复的。

## Sponsored Transaction

玩家发起、但由 Builder 或服务器代付 Gas 的交易。EVE Vault 支持赞助交易扩展，这也是“用户没有 SUI 也能用 dApp”的核心基础。

## zkLogin

Sui 的无助记词登录方案。用户用 Web2 身份完成 OAuth 登录后，钱包再基于临时密钥、salt、proof 派生链上地址。

## Epoch

Sui 的纪元单位。zkLogin 的临时证明和部分缓存都与 Epoch 绑定，过期后需要重新签发或刷新登录态。

## `0x6`

Sui `Clock` 系统对象的固定对象 ID。文中许多时间相关示例会把 `0x6` 作为参数传入。

## `0x8`

Sui `Random` 系统对象的固定对象 ID。需要链上随机数的示例中通常会传入该对象。

## LUX 与 SUI

课程中的不少案例会“用 `SUI` 代替 `LUX` 演示”，方便在公开环境和标准 SDK 中说明资金流。实际接入 EVE Frontier 时，需以游戏内真实资产与 World/钱包接口为准。

## GraphQL / Indexer

本书里提到的 GraphQL，多数指 Sui 索引层提供的查询入口；Indexer 指围绕事件和对象状态建立的链下检索服务。它们主要负责“读”，而不是“写”。
