#!/usr/bin/env python3
"""
Enhanced script to translate Chinese comments in Move files to English.
Preserves all code syntax, indentation, and comment formatting.
"""

import os
import re
import glob
from pathlib import Path

# Comprehensive translation dictionary - longer phrases first for better matching
TRANSLATIONS = {
    # Complete sentence translations (highest priority)
    "我们的 Witness 类型": "Our Witness type",
    "使用 VaultAuth{} 作为见证，证明这个调用是合法绑定的扩展": "Use VaultAuth{} as witness to prove this call is a legitimately bound extension",
    "任何人都可以存入物品（开放存款）": "Anyone can deposit items (open deposits)",
    "只有拥有特定 Badge（NFT）的角色才能取出物品": "Only characters with a specific Badge (NFT) can withdraw items",
    "必须持有成员勋章才能调用": "Must hold member badge to call",
    "验证调用者是否为授权赞助者": "Verify if the caller is an authorized sponsor",

    # Platform/Registry/Multi-tenant
    "平台注册表（共享对象，所有租户共用）": "Platform registry (shared object, used by all tenants)",
    "每个租户（星门）的独立配置": "Independent configuration for each tenant (stargate)",
    "租户注册（任意 Builder 都可以把自己的星门注册进来）": "Tenant registration (any Builder can register their stargate)",
    "验证 OwnerCap 和 Gate 对应": "Verify OwnerCap corresponds to Gate",
    "调整租户配置（只有自己的配置才能修改）": "Adjust tenant configuration (only own configuration can be modified)",
    "多租户跳跃（收费逻辑复用，但配置各自独立）": "Multi-tenant jump (fee logic reused, but configurations are independent)",
    "读取该星门的专属收费配置": "Read the exclusive fee configuration for this stargate",
    "转给各自的 fee_recipient": "Transfer to respective fee_recipient",
    "还回找零": "Return change",
    "发放跳跃许可": "Issue jump permit",
    "全局注册表（类似域名系统）": "Global registry (similar to domain name system)",
    "注册一个命名对象": "Register a named object",

    # Insurance/Shield/Protection
    "保险池（共享）": "Insurance pool (shared)",
    "保单 NFT": "Policy NFT",
    "购买保险": "Purchase insurance",
    "计算保费:保额 × 月费率 × 天数": "Calculate premium: coverage amount × monthly rate × days",
    "70% 进理赔池，30% 进准备金": "70% to claims pool, 30% to reserve fund",
    "理赔（需要游戏服务器签名证明物品已损毁）": "Claim (requires game server signature to prove item destroyed)",
    "验证服务器签名（即服务器确认物品已经损毁）": "Verify server signature (i.e., server confirms item destroyed)",
    "检查赔付池余额是否足够": "Check if claims pool balance is sufficient",
    "标记已理赔（防止重复理赔）": "Mark as claimed (prevent duplicate claims)",
    "管理员从准备金补充理赔池（当理赔池不足时）": "Admin replenishes claims pool from reserve fund (when claims pool insufficient)",
    "管理员从准备金补充理赔池": "Admin replenishes claims pool from reserve fund",

    # Recruitment/Membership/Voting
    "成员 NFT": "Member NFT",
    "创始人获得 MemberNFT（编号 #1）": "Founder receives MemberNFT (number #1)",
    "申请加入": "Apply to join",
    "成员投票": "Member voting",
    "若票数已足够，尝试自动结算": "If votes sufficient, attempt auto-settlement",
    "提前结算条件:赞成 >= 60% 且至少 3 票，或反对 > 40% 且覆盖全员": "Early settlement conditions: approval >= 60% and at least 3 votes, or rejection > 40% and covers all members",
    "退还押金": "Refund deposit",
    "加入成员列表并发放 NFT": "Add to member list and issue NFT",
    "没收押金入金库": "Confiscate deposit into treasury",
    "创始人一票否决": "Founder veto",
    "没收押金": "Confiscate deposit",

    # Location/Position/Distance
    "location.move（简化版）": "location.move (simplified version)",
    "更新位置（需要游戏服务器签名授权）": "Update position (requires game server signature authorization)",
    "资产只在特定位置哈希处有效": "Asset only valid at specific location hash",
    "验证玩家位置哈希与资源点匹配": "Verify player location hash matches resource point",
    "发放资源": "Issue resources",
    "星门链接时的距离验证": "Distance verification when linking stargates",
    "验证服务器签名（简化；实际实现验证 ed25519 签名）": "Verify server signature (simplified; actual implementation verifies ed25519 signature)",
    "授权组件只对在基地范围内的玩家开放": "Authorized components only open to players within base range",

    # Module/Interface patterns
    "Character 模块提供的接口": "Interfaces provided by Character module",
    "authorized_object_id 确保这个 OwnerCap 只能用于对应的那个对象": "authorized_object_id ensures this OwnerCap can only be used for the corresponding object",
    "在你的扩展合约中，维护一个操作员白名单": "In your extension contract, maintain an operator whitelist",
    "验证调用者在操作员名单中": "Verify caller is in operator list",

    # Testing/Specification
    "spec 块:形式规范": "spec block: formal specification",
    "声明:铸造后总供应量增加的精确量": "Declaration: precise amount total supply increases after minting",
    "不变量:金库余额永远不超过某个上限": "Invariant: vault balance never exceeds certain limit",
    "❌ 有竞态问题:两个交易可能同时通过检查": "❌ Has race condition: two transactions may pass check simultaneously",
    "← 另一个 TX 可能在这里同时通过同样的检查": "← Another TX may simultaneously pass same check here",
    "... 然后两个都执行购买，导致超卖": "... then both execute purchase, causing overselling",
    "✅ Sui 的解决方案:通过对共享对象的写锁确保序列化": "✅ Sui's solution: ensure serialization through write lock on shared objects",
    "Sui 的 Move 执行器保证:写同一个共享对象的交易是顺序执行的": "Sui's Move executor guarantees: transactions writing to the same shared object execute sequentially",
    "所以上面的代码在 Sui 上实际是安全的！但要确保你的逻辑正确处理负库存": "So the above code is actually safe on Sui! But ensure your logic correctly handles negative inventory",
    "这次检查是原子的，其他 TX 会等待": "This check is atomic, other TXs will wait",

    # Security best practices
    "❌ 危险:没有验证调用者": "❌ Dangerous: no caller verification",
    "✅ 安全:要求 OwnerCap": "✅ Safe: requires OwnerCap",
    "❌ 危险:u64 减法下溢会 abort，但如果逻辑错误可能算出极大值": "❌ Dangerous: u64 subtraction underflow will abort, but logic errors may compute very large values",
    "✅ 安全:在操作前检查": "✅ Safe: check before operation",
    "✅ 对于有意允许的下溢，使用检查后的计算": "✅ For intentionally allowed underflow, use checked calculation",
    "bps 最大 10000，防止 total * bps 溢出": "bps max 10000, prevent total * bps overflow",
    "❌ 不推荐:直接依赖 ctx.epoch() 作为精确时间": "❌ Not recommended: directly rely on ctx.epoch() as precise time",
    "epoch 的粒度是约 24 小时，不适合细粒度时效": "epoch granularity is about 24 hours, unsuitable for fine-grained timing",
    "✅ 推荐:使用 Clock 对象": "✅ Recommended: use Clock object",
    "❌ 危险:OwnerCap 没有验证对应的对象 ID": "❌ Dangerous: OwnerCap doesn't verify corresponding object ID",
    "任何 OwnerCap 都能控制任何 Vault！": "Any OwnerCap can control any Vault!",
    "✅ 安全:验证 OwnerCap 和对象的绑定关系": "✅ Safe: verify binding between OwnerCap and object",

    # Migration/Versioning
    "v1:旧版存储结构": "v1: old storage structure",
    "v2:新版增加字段（不能直接修改 V1）": "v2: new version adds fields (cannot directly modify V1)",
    "改为用动态字段扩展": "Instead use dynamic field extension",
    "给旧对象添加新字段（迁移脚本）": "Add new fields to old objects (migration script)",
    "这是教学示例合约（教学占位符）": "This is a teaching example contract (teaching placeholder)",
    "实际的 Vault 合约逻辑在 chapter-08 的 vault.move 中": "Actual Vault contract logic is in chapter-08 vault.move",

    # Testing templates
    "── 基础测试模板 ────────────────────────────────────────": "── Basic test template ────────────────────────────────────────",
    "── 使用 Clock 测试时间相关逻辑 ─────────────────────────": "── Use Clock to test time-related logic ─────────────────────────",
    "验证时间设置生效": "Verify time setting takes effect",

    # Subscription/Pass system
    "订阅管理器（共享对象）": "Subscription manager (shared object)",
    "订阅 NFT（可转让，持有即有权限）": "Subscription NFT (transferable, holding grants permission)",
    "购买订阅": "Purchase subscription",
    "续费（延长已有 Pass 的有效期）": "Renew (extend existing Pass validity)",
    "如果已过期从现在起算，否则在原到期时间上叠加": "If expired, count from now; otherwise add to original expiration time",
    "星门扩展:验证 Pass 有效性": "Stargate extension: verify Pass validity",
    "星门跳跃（持有有效 Pass 无限跳）": "Stargate jump (holding valid Pass grants unlimited jumps)",
    "管理员提款": "Admin withdrawal",

    # Gas optimization patterns
    "❌ 把所有数据放在一个对象（最大 250KB）": "❌ Put all data in one object (max 250KB)",
    "✅ 用动态字段或独立对象分散存储": "✅ Use dynamic fields or independent objects for distributed storage",
    "具体 Listing 用动态字段存储:df::add(id, item_id, listing)": "Specific Listing uses dynamic field storage: df::add(id, item_id, listing)",
    "❌ 浪费空间": "❌ Waste space",
    "✅ 紧凑存储": "✅ Compact storage",
    "拍卖结束后，删除 Listing 获得 Gas 退款": "After auction ends, delete Listing to receive Gas refund",
    "领取完毕后，删除 DividendClaim 对象": "After claiming, delete DividendClaim object",
    "分片路由": "Sharding routing",
    "❌ 在链上排序（极度消耗 Gas）": "❌ Sort on-chain (extremely Gas-consuming)",
    "... O(n²) 排序，每次都在链上执行": "... O(n²) sorting, executed on-chain every time",
    "✅ 链上只存原始数据，链下排序": "✅ Store only raw data on-chain, sort off-chain",
    "dApp 或后端读取所有竞价，在内存中排序，展示排行榜": "dApp or backend reads all bids, sorts in memory, displays leaderboard",

    # Capabilities and storage patterns
    "每个拥有的资产对应一个 OwnerCap": "Each owned asset corresponds to one OwnerCap",
    "owner_caps 以 dynamic field 形式存储": "owner_caps stored as dynamic field",
    "跳跃许可证:有时效性的链上对象": "Jump permit: time-limited on-chain object",
    "1. 注册扩展（Owner 调用）": "1. Register extension (Owner calls)",
    "2. 扩展存入物品": "2. Extension deposits items",
    "3. 扩展取出物品": "3. Extension withdraws items",
    "注册扩展": "Register extension",
    "发放跳跃许可（只有已注册的 Auth 类型才能调用）": "Issue jump permit (only registered Auth types can call)",
    "使用许可跳跃（消耗 JumpPermit）": "Use permit to jump (consumes JumpPermit)",

    # Hot potato pattern
    "没有任何 ability = 热土豆，必须在本次 tx 中处理掉": "No abilities = hot potato, must be handled in this tx",
    "执行检查...": "Execute checks...",
    "正式执行操作": "Formally execute operation",
    "JumpPermit:有 key + store，是真实的链上资产，不可复制": "JumpPermit: has key + store, is real on-chain asset, cannot be copied",
    "VendingAuth:只有 drop，是一次性的"凭证"（Witness Pattern）": "VendingAuth: only has drop, is one-time 'credential' (Witness Pattern)",
    "定义能力对象": "Define capability object",
    "需要 OwnerCap 才能调用的函数": "Function that requires OwnerCap to call",

    # Module structure and documentation
    "文件:sources/my_contract.move": "File: sources/my_contract.move",
    "模块声明:包名::模块名": "Module declaration: package_name::module_name",
    "导入依赖": "Import dependencies",
    "结构体定义（资产/数据）": "Struct definition (assets/data)",
    "初始化函数（合约部署时自动执行一次）": "Init function (auto-executes once on contract deployment)",
    "公开函数（可被外部调用）": "Public function (can be called externally)",
    "私有函数:只能在本模块内调用": "Private function: can only be called within this module",
    "包内可见:同一个包的其他模块可调用（Layer 1 Primitives 使用这个）": "Package-visible: other modules in same package can call (Layer 1 Primitives use this)",
    "Entry:可以直接作为交易（Transaction）的顶层调用": "Entry: can be directly used as top-level call in Transaction",
    "公开:任何模块都可以调用": "Public: any module can call",

    # Witness pattern explanations
    "Builder 在自己的包中定义一个 Witness 类型": "Builder defines a Witness type in their own package",
    "只有这个模块能创建 Auth 实例（因为它没有公开构造函数）": "Only this module can create Auth instance (because it has no public constructor)",
    "调用星门 API 时，把 Auth {} 作为凭证传入": "When calling stargate API, pass Auth {} as credential",
    "自定义逻辑（例如检查费用）": "Custom logic (e.g., check fees)",
    "用 Auth {} 证明调用来自这个已授权的模块": "Use Auth {} to prove call comes from this authorized module",

    # Future/ZK/DAO patterns
    "现在:用 AdminACL 验证服务器签名": "Now: use AdminACL to verify server signature",
    "未来（ZK 时代）:替换验证逻辑，业务代码不变": "Future (ZK era): replace verification logic, business code unchanged",
    "同一链上验证 ZK 证明": "Verify ZK proof on-chain",
    "未来:费率参数由 DAO 投票决定": "Future: fee parameters decided by DAO voting",
    "验证提案已通过且未过期": "Verify proposal passed and not expired",

    # Multi-hop routing
    "一次购买多跳路线": "Purchase multi-hop route in one transaction",
    "验证路线连续性:hop1_dest 和 hop2_source 必须是链接的星门": "Verify route continuity: hop1_dest and hop2_source must be linked stargates",
    "计算并扣除每跳费用": "Calculate and deduct fee for each hop",
    "发放两个 JumpPermit（1小时有效期）": "Issue two JumpPermits (1 hour validity)",
    "扣除收费": "Deduct fee",
    "通用 N 跳路由（接受可变长度路线）": "Generic N-hop routing (accepts variable-length routes)",
    "验证路线连续性（每对相邻目的/起点必须链接）": "Verify route continuity (each adjacent destination/origin pair must be linked)",
    "计算总费用": "Calculate total fee",
    "发放所有 Permit": "Issue all Permits",
    "退款找零": "Refund change",
    "处理 payment 到各个星门金库...": "Process payment to each stargate treasury...",
    "从星门的扩展数据读取通行费（动态字段）": "Read toll fee from stargate's extension data (dynamic field)",
    "简化版:固定费率": "Simplified version: fixed fee rate",
    "将 coin 转到星门对应的 Treasury": "Transfer coin to stargate's corresponding Treasury",

    # Mining/Admin capabilities
    "矿区通行证 NFT": "Mining area pass NFT",
    "管理员能力（只有合约部署者持有）": "Admin capability (only contract deployer holds)",
    "事件:新通行证颁发": "Event: new pass issued",
    "合约初始化:部署者获得 AdminCap": "Contract initialization: deployer receives AdminCap",
    "将 AdminCap 转给部署者地址": "Transfer AdminCap to deployer address",
    "颁发矿区通行证（只有持有 AdminCap 才能调用）": "Issue mining area pass (only holding AdminCap can call)",
    "发射事件": "Emit event",
    "将通行证转给接收者": "Transfer pass to recipient",
    "撤销通行证": "Revoke pass",
    "Owner 可以通过 admin_cap 销毁指定角色的通行证": "Owner can destroy specified character's pass via admin_cap",
    "（实际上，你可以设计成"收回+销毁"，这里简化为让持有者自行烧毁）": "(Actually, you can design as 'reclaim+destroy', simplified here to let holder self-burn)",
    "检查通行证是否属于特定矿区": "Check if pass belongs to specific mining area",

    # Auction/Bidding phrases
    "竞价历史记录（动态字段存储，避免大对象）": "Bid history record (dynamic field storage, avoid large objects)",
    "拍卖对象（使用 SUI token 竞拍）": "Auction object (bidding using SUI token)",
    "所有竞价款暂存于此": "All bid funds are held here in escrow",
    "拍卖결束事件": "Auction ended event",
    "拍卖结束事件": "Auction ended event",
    "将竞价款存入托管": "Deposit bid funds into escrow",
    "更新当前最高价": "Update current highest bid",
    "记录竞价历史（动态字段）": "Record bid history (dynamic field)",
    "将竞价款转给卖家": "Transfer bid funds to seller",
    "取消拍卖（无人出价时卖家可取消）": "Cancel auction (seller can cancel when there are no bids)",
    "已有人出价则不能取消": "Cannot cancel if someone has already bid",

    # Common phrases - medium priority
    "我们的": "our",
    "任何人都可以": "anyone can",
    "只有拥有特定": "only with specific",
    "的角色才能": "characters can",
    "必须持有": "must hold",
    "才能调用": "to call",
    "验证调用者": "verify caller",
    "是否为": "is",
    "授权赞助者": "authorized sponsor",
    "见证类型": "witness type",
    "证明这个调用是合法绑定的扩展": "prove this call is a legitimately bound extension",
    "作为见证": "as witness",
    "套餐类型": "package type",
    "共享对象": "shared object",
    "可转让": "transferable",
    "持有即有权限": "holding grants permission",
    "错误码": "error codes",
    "初始化": "initialize",
    "借款": "borrow",
    "还款": "repay",
    "清算": "liquidate",
    "赔付": "payout",
    "查询": "query",
    "提供服务": "provide services",
    "执行操作": "execute operation",

    # Single word translations - lowest priority
    "我们的": "our",
    "我的": "my",
    "只有": "only",
    "才能": "can",
    "必须": "must",
    "持有": "hold",
    "成员勋章": "member badge",
    "验证": "verify",
    "调用者": "caller",
    "授权": "authorized",
    "赞助者": "sponsor",
    "见证": "witness",
    "使用": "use",
    "作为": "as",
    "常量": "constants",
    "数据结构": "data structures",
    "对象": "object",
    "事件": "event",
    "竞价历史记录": "bid history record",
    "动态字段存储": "dynamic field storage",
    "避免大对象": "avoid large objects",
    "拍卖": "auction",
    "竞拍": "bidding",
    "拍卖对象": "auction object",
    "竞价": "bid",
    "竞价事件": "bid event",
    "创建拍卖": "create auction",
    "记录竞价历史": "record bid history",
    "动态字段": "dynamic field",
    "结束拍卖": "end auction",
    "取消拍卖": "cancel auction",
    "存入物品": "deposit items",
    "开放存款": "open deposits",
    "取出物品": "withdraw items",
    "物品": "item",
    "共享": "shared",
    "和": "and",
    "对应": "corresponds to",
    "确保这个": "ensure this",
    "只能用于对应的那个": "can only be used for the corresponding",
    "维护一个操作员白名单": "maintain an operator whitelist",
    "在操作员名单中": "in operator list",
    "简化版": "simplified version",
    "需要游戏服务器签名": "requires game server signature",
    "模块提供的接口": "interfaces provided by module",
}

def has_chinese(text):
    """Check if text contains Chinese characters."""
    return bool(re.search(r'[\u4e00-\u9fff]', text))

def translate_text(text):
    """
    Translate Chinese text to English using the translation dictionary.
    Handles partial matches and preserves technical terms.
    """
    if not has_chinese(text):
        return text

    result = text

    # Sort by length (longest first) to handle multi-word phrases before single words
    sorted_translations = sorted(TRANSLATIONS.items(), key=lambda x: len(x[0]), reverse=True)

    for chinese, english in sorted_translations:
        result = result.replace(chinese, english)

    # If there are still Chinese characters, note it
    if has_chinese(result):
        chinese_chars = re.findall(r'[\u4e00-\u9fff]+', result)
        print(f"  Warning: Untranslated Chinese found: {chinese_chars}")
        print(f"    Original: {text}")
        print(f"    Partial: {result}")

    return result

def process_line(line):
    """Process a single line, translating Chinese in comments while preserving code."""
    # Match single-line comments
    single_line_match = re.match(r'^(\s*//\s*)(.*)$', line)
    if single_line_match:
        prefix = single_line_match.group(1)
        comment_text = single_line_match.group(2)
        if has_chinese(comment_text):
            translated = translate_text(comment_text)
            return prefix + translated + '\n'

    return line

def process_file_content(content):
    """Process file content, translating all Chinese comments."""
    lines = content.split('\n')
    result_lines = []
    in_multiline_comment = False
    multiline_buffer = []

    for i, line in enumerate(lines):
        # Check for multi-line comment start
        if '/*' in line and '*/' not in line:
            in_multiline_comment = True
            multiline_buffer = [line]
            continue

        # Inside multi-line comment
        if in_multiline_comment:
            multiline_buffer.append(line)
            if '*/' in line:
                # End of multi-line comment
                in_multiline_comment = False
                full_comment = '\n'.join(multiline_buffer)
                if has_chinese(full_comment):
                    translated_block = translate_text(full_comment)
                    result_lines.append(translated_block)
                else:
                    result_lines.append(full_comment)
                multiline_buffer = []
            continue

        # Check for single-line multi-line comment (/* */ on same line)
        multiline_single = re.match(r'^(\s*/\*\s*)(.*)(\s*\*/\s*)$', line)
        if multiline_single:
            prefix = multiline_single.group(1)
            comment_text = multiline_single.group(2)
            suffix = multiline_single.group(3)
            if has_chinese(comment_text):
                translated = translate_text(comment_text)
                result_lines.append(prefix + translated + suffix)
                continue

        # Process single-line comments
        processed_line = process_line(line)
        result_lines.append(processed_line.rstrip('\n'))

    return '\n'.join(result_lines)

def translate_move_files(directory):
    """Find and translate all .move files in the given directory."""
    move_files = glob.glob(os.path.join(directory, '**/*.move'), recursive=True)

    stats = {
        'total_files': 0,
        'files_with_chinese': 0,
        'files_translated': 0,
        'errors': 0
    }

    samples = []

    for filepath in move_files:
        stats['total_files'] += 1

        try:
            # Read file
            with open(filepath, 'r', encoding='utf-8') as f:
                original_content = f.read()

            # Check if file has Chinese
            if not has_chinese(original_content):
                continue

            stats['files_with_chinese'] += 1
            print(f"\nProcessing: {filepath}")

            # Translate
            translated_content = process_file_content(original_content)

            # Write back
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(translated_content)

            stats['files_translated'] += 1

            # Save sample for first few files
            if len(samples) < 3:
                samples.append({
                    'file': filepath,
                    'original': original_content[:500],
                    'translated': translated_content[:500]
                })

        except Exception as e:
            print(f"Error processing {filepath}: {e}")
            stats['errors'] += 1

    return stats, samples

def main():
    directory = "/Users/henryduong/Documents/workspace/eve-bootcamp/src/code/en/"

    print("=" * 80)
    print("Move File Chinese Comment Translator v2")
    print("=" * 80)
    print(f"\nScanning directory: {directory}")

    stats, samples = translate_move_files(directory)

    print("\n" + "=" * 80)
    print("TRANSLATION SUMMARY")
    print("=" * 80)
    print(f"Total files scanned: {stats['total_files']}")
    print(f"Files with Chinese comments: {stats['files_with_chinese']}")
    print(f"Files successfully translated: {stats['files_translated']}")
    print(f"Errors: {stats['errors']}")

    if samples:
        print("\n" + "=" * 80)
        print("SAMPLE TRANSLATIONS")
        print("=" * 80)
        for i, sample in enumerate(samples, 1):
            print(f"\nSample {i}: {sample['file']}")
            print("-" * 80)
            print("BEFORE:")
            print(sample['original'])
            print("\nAFTER:")
            print(sample['translated'])
            print("-" * 80)

    print("\n" + "=" * 80)
    print("Translation complete!")
    print("=" * 80)

if __name__ == "__main__":
    main()
