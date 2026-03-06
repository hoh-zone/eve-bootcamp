module forging::forge;

use sui::object::{Self, UID, ID};
use sui::random::{Self, Random};
use sui::transfer;
use sui::event;
use std::string::{Self, String};

// ── 常量 ──────────────────────────────────────────────────

const TIER_FRAGMENT: u8 = 0;
const TIER_COMPONENT: u8 = 1;
const TIER_ARTIFACT: u8 = 2;

const FRAGMENT_TO_COMPONENT_BPS: u64 = 6_000;
const COMPONENT_TO_ARTIFACT_BPS: u64 = 3_000;

// ── 错误码 ────────────────────────────────────────────────
const EMismatchedTier: u64 = 0;
const EMaxTierReached: u64 = 1;
const ECannotDisassembleFragment: u64 = 2;

// ── 数据结构 ───────────────────────────────────────────────

public struct ForgeItem has key, store {
    id: UID,
    tier: u8,
    name: String,
    image_url: String,
    power: u64,
}

public struct ForgeAdminCap has key, store { id: UID }

// ── 事件 ──────────────────────────────────────────────────

public struct CraftAttempted has copy, drop {
    crafter: address,
    input_tier: u8,
    success: bool,
    result_tier: u8,
}

public struct ItemDisassembled has copy, drop {
    crafter: address,
    from_tier: u8,
    fragments_returned: u64,
}

// ── 初始化 ────────────────────────────────────────────────

fun init(ctx: &mut TxContext) {
    transfer::public_transfer(ForgeAdminCap { id: object::new(ctx) }, ctx.sender());
}

public fun mint_fragment(
    _cap: &ForgeAdminCap,
    recipient: address,
    ctx: &mut TxContext,
) {
    let (name, image_url, power) = tier_info(TIER_FRAGMENT);
    let item = ForgeItem {
        id: object::new(ctx),
        tier: TIER_FRAGMENT,
        name,
        image_url,
        power,
    };
    transfer::public_transfer(item, recipient);
}

// ── 合成（3 个同阶 → 1 个高阶，带链上随机成功率）────────

public fun craft(
    input1: ForgeItem,
    input2: ForgeItem,
    input3: ForgeItem,
    rng_obj: &Random,
    ctx: &mut TxContext,
) {
    assert!(input1.tier == input2.tier && input2.tier == input3.tier, EMismatchedTier);
    let input_tier = input1.tier;
    assert!(input_tier < TIER_ARTIFACT, EMaxTierReached);

    let target_tier = input_tier + 1;

    // 链上随机数
    let mut rng = random::new_generator(rng_obj, ctx);
    let roll = rng.generate_u64() % 10_000;

    let success_threshold = if (target_tier == TIER_COMPONENT) {
        FRAGMENT_TO_COMPONENT_BPS
    } else {
        COMPONENT_TO_ARTIFACT_BPS
    };

    // 销毁三个输入
    let ForgeItem { id: id1, .. } = input1;
    let ForgeItem { id: id2, .. } = input2;
    let ForgeItem { id: id3, .. } = input3;
    object::delete(id1);
    object::delete(id2);
    object::delete(id3);

    let success = roll < success_threshold;

    if (success) {
        let (name, image_url, power) = tier_info(target_tier);
        let result = ForgeItem {
            id: object::new(ctx),
            tier: target_tier,
            name,
            image_url,
            power,
        };
        transfer::public_transfer(result, ctx.sender());
    } else if (target_tier == TIER_ARTIFACT) {
        // 合成神器失败，安慰奖：返还 1 个精炼组件
        let (name, image_url, power) = tier_info(TIER_COMPONENT);
        let consolation = ForgeItem {
            id: object::new(ctx),
            tier: TIER_COMPONENT,
            name,
            image_url,
            power,
        };
        transfer::public_transfer(consolation, ctx.sender());
    };

    event::emit(CraftAttempted {
        crafter: ctx.sender(),
        input_tier,
        success,
        result_tier: if (success) { target_tier } else { input_tier },
    });
}

// ── 拆解（1 个高阶 → 2 个低阶）──────────────────────────

public fun disassemble(
    item: ForgeItem,
    ctx: &mut TxContext,
) {
    assert!(item.tier > TIER_FRAGMENT, ECannotDisassembleFragment);

    let target_tier = item.tier - 1;
    let item_tier = item.tier;
    let ForgeItem { id, .. } = item;
    object::delete(id);

    let (name, image_url, power) = tier_info(target_tier);
    let mut i = 0u64;
    while (i < 2) {
        let fragment = ForgeItem {
            id: object::new(ctx),
            tier: target_tier,
            name,
            image_url,
            power,
        };
        transfer::public_transfer(fragment, ctx.sender());
        i = i + 1;
    };

    event::emit(ItemDisassembled {
        crafter: ctx.sender(),
        from_tier: item_tier,
        fragments_returned: 2,
    });
}

fun tier_info(tier: u8): (String, String, u64) {
    if (tier == TIER_FRAGMENT) {
        (
            string::utf8(b"Plasma Fragment"),
            string::utf8(b"https://assets.example.com/fragment.png"),
            10,
        )
    } else if (tier == TIER_COMPONENT) {
        (
            string::utf8(b"Refined Component"),
            string::utf8(b"https://assets.example.com/component.png"),
            100,
        )
    } else {
        (
            string::utf8(b"Ancient Artifact"),
            string::utf8(b"https://assets.example.com/artifact.png"),
            1000,
        )
    }
}
