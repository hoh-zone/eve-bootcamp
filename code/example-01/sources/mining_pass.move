// sources/mining_pass.move
module mining_guard::mining_pass;

use sui::object::{Self, UID};
use sui::tx_context::TxContext;
use sui::transfer;
use sui::event;

/// 矿区通行证 NFT
public struct MiningPass has key, store {
    id: UID,
    holder_name: vector<u8>,    // 持有者名称（方便辨识）
    issued_at_ms: u64,          // 颁发时间戳
    zone_id: u64,               // 对应哪个矿区（支持多矿区）
}

/// 管理员能力（只有合约部署者持有）
public struct AdminCap has key, store {
    id: UID,
}

/// 事件：新通行证颁发
public struct PassIssued has copy, drop {
    pass_id: ID,
    recipient: address,
    zone_id: u64,
}

/// 合约初始化：部署者获得 AdminCap
fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };
    // 将 AdminCap 转给部署者地址
    transfer::transfer(admin_cap, ctx.sender());
}

/// 颁发矿区通行证（只有持有 AdminCap 才能调用）
public entry fun issue_pass(
    _admin_cap: &AdminCap,             // 验证调用者是管理员
    recipient: address,                 // 接收者地址
    holder_name: vector<u8>,
    zone_id: u64,
    ctx: &mut TxContext,
) {
    let pass = MiningPass {
        id: object::new(ctx),
        holder_name,
        issued_at_ms: ctx.epoch_timestamp_ms(),
        zone_id,
    };

    // 发射事件
    event::emit(PassIssued {
        pass_id: object::id(&pass),
        recipient,
        zone_id,
    });

    // 将通行证转给接收者
    transfer::transfer(pass, recipient);
}

/// 撤销通行证
/// Owner 可以通过 admin_cap 销毁指定角色的通行证
/// （实际上，你可以设计成"收回+销毁"，这里简化为让持有者自行烧毁）
public entry fun revoke_pass(
    _admin_cap: &AdminCap,
    pass: MiningPass,
) {
    let MiningPass { id, .. } = pass;
    id.delete();
}

/// 检查通行证是否属于特定矿区
public fun is_valid_for_zone(pass: &MiningPass, zone_id: u64): bool {
    pass.zone_id == zone_id
}
