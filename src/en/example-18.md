# Practical Case 18: Inter-Alliance Diplomatic Treaty (Ceasefire and Resource Treaties)

> **Objective:** Build an on-chain diplomatic contract—two alliances can sign treaties (ceasefire, resource sharing, trade agreements), treaties take effect when co-signed by both Leaders, violations can be proven on-chain, and enforcement is mandatory during validity period.

---

> Status: Teaching example. The main text covers treaty state machine, complete directory is based on `book/src/code/example-18/`.

## Corresponding Code Directory

- [example-18](./code/example-18)
- [example-18/dapp](./code/example-18/dapp)

## Minimal Call Chain

`One party initiates proposal -> Both parties deposit and sign -> Treaty takes effect -> Violation/termination occurs -> Penalty deduction or deposit refund`

## Test Loop

- Initiate proposal: Confirm `TreatyProposal` created successfully with event emitted
- Co-signing takes effect: Confirm `effective_at_ms` written, both deposits equal
- Advance notice and termination: Confirm cannot terminate before notice matures, deposits refunded after maturity
- Report violation: Confirm penalty deducted from violating party's deposit and transferred to other party

## Requirements Analysis

**Scenario:** Alliance Alpha and Alliance Beta erupted in conflict, both sides decide to negotiate:

1. **Ceasefire Agreement**: Both alliance turrets do not fire on opposing members for 72 hours
2. **Passage Agreement**: Alpha members can use Beta's stargates for free (and vice versa)
3. **Resource Sharing**: Both sides transfer 100 WAR Token to each other daily
4. Either party can unilaterally terminate treaty (requires 24-hour advance notice on-chain)
5. Violations (such as illegal turret firing) can be reported via server signature, penalty deposit confiscated

---

## Contract

```move
module diplomacy::treaty;

use sui::object::{Self, UID, ID};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::balance::{Self, Balance};
use sui::transfer;
use sui::event;
use std::string::{Self, String, utf8};

// ── Constants ──────────────────────────────────────────────────

const NOTICE_PERIOD_MS: u64 = 24 * 60 * 60 * 1000;  // 24-hour advance termination notice
const BREACH_FINE: u64 = 100_000_000_000;             // 100 SUI violation fine (from deposit)

// Treaty types
const TREATY_CEASEFIRE: u8 = 0;       // Ceasefire agreement
const TREATY_PASSAGE: u8 = 1;         // Passage rights agreement
const TREATY_RESOURCE_SHARE: u8 = 2;  // Resource sharing

// ── Data Structures ───────────────────────────────────────────────

/// Diplomatic treaty (shared object)
public struct Treaty has key {
    id: UID,
    treaty_type: u8,
    party_a: address,          // Alliance A's Leader address
    party_b: address,          // Alliance B's Leader address
    party_a_signed: bool,
    party_b_signed: bool,
    effective_at_ms: u64,      // Effective time (after co-signing)
    expires_at_ms: u64,        // Expiration time (0 = indefinite)
    termination_notice_ms: u64, // Termination notice time (0 = not notified)
    party_a_deposit: Balance<SUI>,  // Party A deposit (for violation compensation)
    party_b_deposit: Balance<SUI>,  // Party B deposit
    breach_count_a: u64,
    breach_count_b: u64,
    description: String,
}

/// Treaty proposal (initiated by one party, awaiting other party's signature)
public struct TreatyProposal has key {
    id: UID,
    proposed_by: address,
    counterparty: address,
    treaty_type: u8,
    duration_days: u64,        // Duration (days), 0 = indefinite
    deposit_required: u64,      // Required deposit from each party
    description: String,
}

// ── Events ──────────────────────────────────────────────────

public struct TreatyProposed has copy, drop { proposal_id: ID, proposer: address, counterparty: address }
public struct TreatySigned has copy, drop { treaty_id: ID, party: address }
public struct TreatyEffective has copy, drop { treaty_id: ID, treaty_type: u8 }
public struct TreatyTerminated has copy, drop { treaty_id: ID, terminated_by: address }
public struct BreachReported has copy, drop { treaty_id: ID, breaching_party: address, fine: u64 }

// ── Initiate Treaty Proposal ──────────────────────────────────────────

public fun propose_treaty(
    counterparty: address,
    treaty_type: u8,
    duration_days: u64,
    deposit_required: u64,
    description: vector<u8>,
    ctx: &mut TxContext,
) {
    let proposal = TreatyProposal {
        id: object::new(ctx),
        proposed_by: ctx.sender(),
        counterparty,
        treaty_type,
        duration_days,
        deposit_required,
        description: utf8(description),
    };
    let proposal_id = object::id(&proposal);
    transfer::share_object(proposal);
    event::emit(TreatyProposed {
        proposal_id,
        proposer: ctx.sender(),
        counterparty,
    });
}

// ── Accept Proposal (Proposer signs + deposit) ────────────────────────

public fun accept_and_sign_a(
    proposal: &TreatyProposal,
    mut deposit: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == proposal.proposed_by, ENotParty);

    let deposit_amt = coin::value(&deposit);
    assert!(deposit_amt >= proposal.deposit_required, EInsufficientDeposit);

    let deposit_coin = deposit.split(proposal.deposit_required, ctx);
    if coin::value(&deposit) > 0 {
        transfer::public_transfer(deposit, ctx.sender());
    } else { coin::destroy_zero(deposit); }

    let expires = if proposal.duration_days > 0 {
        clock.timestamp_ms() + proposal.duration_days * 86_400_000
    } else { 0 };

    let treaty = Treaty {
        id: object::new(ctx),
        treaty_type: proposal.treaty_type,
        party_a: proposal.proposed_by,
        party_b: proposal.counterparty,
        party_a_signed: true,
        party_b_signed: false,
        effective_at_ms: 0,
        expires_at_ms: expires,
        termination_notice_ms: 0,
        party_a_deposit: coin::into_balance(deposit_coin),
        party_b_deposit: balance::zero(),
        breach_count_a: 0,
        breach_count_b: 0,
        description: proposal.description,
    };
    let treaty_id = object::id(&treaty);
    transfer::share_object(treaty);
    event::emit(TreatySigned { treaty_id, party: ctx.sender() });
}

/// Counterparty alliance signs (treaty officially takes effect)
public fun countersign(
    treaty: &mut Treaty,
    mut deposit: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == treaty.party_b, ENotParty);
    assert!(treaty.party_a_signed, ENotYetSigned);
    assert!(!treaty.party_b_signed, EAlreadySigned);

    let required = balance::value(&treaty.party_a_deposit); // Equal deposit
    assert!(coin::value(&deposit) >= required, EInsufficientDeposit);

    let dep = deposit.split(required, ctx);
    balance::join(&mut treaty.party_b_deposit, coin::into_balance(dep));
    if coin::value(&deposit) > 0 {
        transfer::public_transfer(deposit, ctx.sender());
    } else { coin::destroy_zero(deposit); }

    treaty.party_b_signed = true;
    treaty.effective_at_ms = clock.timestamp_ms();

    event::emit(TreatyEffective { treaty_id: object::id(treaty), treaty_type: treaty.treaty_type });
    event::emit(TreatySigned { treaty_id: object::id(treaty), party: ctx.sender() });
}

// ── Verify treaty is in effect (called by turret/stargate extensions) ───────────────

public fun is_treaty_active(treaty: &Treaty, clock: &Clock): bool {
    if !treaty.party_a_signed || !treaty.party_b_signed { return false };
    if treaty.expires_at_ms > 0 && clock.timestamp_ms() > treaty.expires_at_ms { return false };
    // Treaty still valid during termination notice period
    true
}

/// Check if address is protected by treaty
public fun is_protected_by_treaty(
    treaty: &Treaty,
    protected_member: address, // Protected alliance member (verified through FactionNFT.owner or member list)
    aggressor_faction: address,
    clock: &Clock,
): bool {
    is_treaty_active(treaty, clock)
    // Real scenario requires additional verification of member-alliance association
}

// ── Submit Termination Notice (takes effect after 24 hours) ───────────────────────

public fun give_termination_notice(
    treaty: &mut Treaty,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert!(ctx.sender() == treaty.party_a || ctx.sender() == treaty.party_b, ENotParty);
    assert!(is_treaty_active(treaty, clock), ETreatyNotActive);
    treaty.termination_notice_ms = clock.timestamp_ms();
    event::emit(TreatyTerminated { treaty_id: object::id(treaty), terminated_by: ctx.sender() });
}

/// Officially terminate treaty after notice period matures, both parties retrieve deposits
public fun finalize_termination(
    treaty: &mut Treaty,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(treaty.termination_notice_ms > 0, ENoNoticeGiven);
    assert!(
        clock.timestamp_ms() >= treaty.termination_notice_ms + NOTICE_PERIOD_MS,
        ENoticeNotMature,
    );
    // Refund deposits
    let a_dep = balance::withdraw_all(&mut treaty.party_a_deposit);
    let b_dep = balance::withdraw_all(&mut treaty.party_b_deposit);
    if balance::value(&a_dep) > 0 {
        transfer::public_transfer(coin::from_balance(a_dep, ctx), treaty.party_a);
    } else { balance::destroy_zero(a_dep); }
    if balance::value(&b_dep) > 0 {
        transfer::public_transfer(coin::from_balance(b_dep, ctx), treaty.party_b);
    } else { balance::destroy_zero(b_dep); }
}

// ── Report Violation (verified and signed by game server) ──────────────────

public fun report_breach(
    treaty: &mut Treaty,
    breaching_party: address,  // Violating alliance's Leader address
    admin_acl: &AdminACL,
    ctx: &mut TxContext,
) {
    verify_sponsor(admin_acl, ctx);  // Server proves violation event actually occurred

    let fine = BREACH_FINE;

    if breaching_party == treaty.party_a {
        treaty.breach_count_a = treaty.breach_count_a + 1;
        // Deduct fine from A's deposit and transfer to B
        if balance::value(&treaty.party_a_deposit) >= fine {
            let fine_coin = coin::take(&mut treaty.party_a_deposit, fine, ctx);
            transfer::public_transfer(fine_coin, treaty.party_b);
        }
    } else if breaching_party == treaty.party_b {
        treaty.breach_count_b = treaty.breach_count_b + 1;
        if balance::value(&treaty.party_b_deposit) >= fine {
            let fine_coin = coin::take(&mut treaty.party_b_deposit, fine, ctx);
            transfer::public_transfer(fine_coin, treaty.party_a);
        }
    } else abort ENotParty;

    event::emit(BreachReported {
        treaty_id: object::id(treaty),
        breaching_party,
        fine,
    });
}

const ENotParty: u64 = 0;
const EInsufficientDeposit: u64 = 1;
const ENotYetSigned: u64 = 2;
const EAlreadySigned: u64 = 3;
const ETreatyNotActive: u64 = 4;
const ENoNoticeGiven: u64 = 5;
const ENoticeNotMature: u64 = 6;
```

---

## dApp (Diplomacy Center)

```tsx
// DiplomacyCenter.tsx
import { useState } from 'react'
import { useCurrentClient } from '@mysten/dapp-kit-react'
import { useQuery } from '@tanstack/react-query'

const DIP_PKG = "0x_DIPLOMACY_PACKAGE_"

const TREATY_TYPES = [
  { id: 0, name: 'Ceasefire Agreement', desc: 'Both parties must not attack during validity period' },
  { id: 1, name: 'Passage Rights Agreement', desc: 'Members can use opposing stargates for free' },
  { id: 2, name: 'Resource Sharing Agreement', desc: 'Periodic mutual resource transfer' },
]

export function DiplomacyCenter() {
  const client = useCurrentClient()
  const [proposing, setProposing] = useState(false)

  const { data: treaties } = useQuery({
    queryKey: ['active-treaties'],
    queryFn: async () => {
      const events = await client.queryEvents({
        query: { MoveEventType: `${DIP_PKG}::treaty::TreatyEffective` },
        limit: 20,
      })
      return events.data
    },
    refetchInterval: 30_000,
  })

  return (
    <div className="diplomacy-center">
      <header>
        <h1>Inter-Alliance Diplomacy Center</h1>
        <p>Sign legally binding alliance treaties on-chain</p>
      </header>

      <section className="treaty-types">
        <h3>Available Treaty Types</h3>
        <div className="types-grid">
          {TREATY_TYPES.map(t => (
            <div key={t.id} className="type-card">
              <h4>{t.name}</h4>
              <p>{t.desc}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="active-treaties">
        <h3>Currently Active Treaties</h3>
        {treaties?.length === 0 && <p>No treaties</p>}
        {treaties?.map(e => {
          const { treaty_id, treaty_type } = e.parsedJson as any
          const type = TREATY_TYPES[Number(treaty_type)]
          return (
            <div key={treaty_id} className="treaty-card">
              <span className="treaty-type">{type?.name}</span>
              <span className="treaty-id">{treaty_id.slice(0, 12)}...</span>
              <span className="treaty-status active">Active</span>
            </div>
          )
        })}
      </section>

      <button className="propose-btn" onClick={() => setProposing(true)}>
        Propose New Treaty
      </button>
    </div>
  )
}
```

---

## Key Design Highlights

| Mechanism | Implementation |
|------|---------|
| Co-signing takes effect | Both `party_a_signed` + `party_b_signed` must be true to take effect |
| Deposit constraint | Both disputing parties deposit, violations automatically penalized |
| Termination notice | `termination_notice_ms` + 24-hour cooling period |
| Violation proof | Game server AdminACL signature proof, auto-execute penalty |
| Treaty verification | `is_treaty_active()` for turret/stargate extension calls |

## Related Documentation
- [Chapter 8: AdminACL and Server Verification](./chapter-08.md)
- [Chapter 11: Ownership and OwnerCap](./chapter-11.md)
- [Example 12: Alliance Recruitment](./example-12.md)
