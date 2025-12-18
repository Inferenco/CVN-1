# CVN-1 Royalty Split Automation Plan (Hard Copy)

## Goal

Automatically split secondary-sale royalties by a defined ratio, and route the vault portion **into the traded NFT’s Core Vault** with minimal delay and minimal trust assumptions. A lightweight Rust backend is allowed.

This plan replaces the earlier “new fee_splitter.move + modify collection flow” plan with a design that:

- Works with Cedra’s **framework royalties** (`cedra_token_objects::royalty`)
- Avoids relying on marketplaces executing arbitrary Move code on your behalf
- Stays compatible with Cedra’s **Move package upgrade rules** (no struct layout changes under `compatible` policy)

## Key Constraints (Cedra source of truth)

- **Framework royalties** expose a single `payee_address` (collection/token royalty metadata). Marketplaces discover this via standard APIs and pay that address.
- A “fee splitter” module pattern splits payments **only when its `distribute_fees` entry is called**; it does not magically run when funds arrive.
- **Compatible package upgrades** do not allow adding/removing/modifying fields of existing structs; you can add **new structs** and **new functions**.
  - See: `https://docs.cedra.network/move-package-upgrades`
- “Instant” can mean:
  1. **Atomic** with sale settlement (same tx or tightly coupled tx sequence) — requires marketplace integration.
  2. **Near-real-time** (seconds) — achievable with a watcher + sweep transaction.

## Recommended Architecture (Hybrid, Near-Real-Time)

### High-level flow

1. **Token-level royalty payee** is set to a **per-NFT escrow address** (royalty escrow).
2. Marketplace pays royalties as usual to that escrow address (standard framework royalty behavior).
3. A lightweight Rust service detects the royalty payment and triggers an on-chain **sweep** function:
   - split amounts by configured bps
   - deposit creator share to `creator_payout_addr`
   - deposit vault share into the NFT’s **Core Vault**

This achieves “automatic” and “near-instant” vault top-ups without requiring marketplace-specific custom settlement logic for every marketplace.

### Why per-NFT escrow (not a generic fee splitter address)

- You need the vault portion to go to the **specific NFT’s vault**, not just “the project vault”.
- If all royalties go to one address, you must attribute them back to the correct NFT, which is fragile.
- Per-NFT escrow provides a deterministic “bucket” for that NFT’s royalty proceeds.

## On-chain Design (Move)

### New data (additive, upgrade-compatible)

Do **not** add fields to `VaultedCollectionConfig` (would violate compatible upgrade rules). Instead, add new resources:

- `RoyaltyEscrowRef` (stored under NFT address; keyed resource)
  - fields: `escrow_addr: address`, `shares_bps: u16` (vault share), `creator_share_bps: u16` (or compute as remainder), `creator_payout_addr: address`, `mint_price_fa: address` (optional convenience), etc.
- Optional: `RoyaltySweepConfig` (stored under collection address or module address)
  - global defaults, allowed FAs for sweep, safety limits, etc.

### Royalty payee configuration

At mint time:

- Create a dedicated “royalty escrow” account/object/address for the NFT.
- Store `RoyaltyEscrowRef` under the NFT address.
- Set **token-level royalty** payee to `escrow_addr`.

Rationale: token-level royalty overrides/precedence is supported in Cedra token objects (marketplaces are expected to read token royalty first; Cedra’s reference marketplace code computes royalty from token v2 first, then falls back to collection).

### Core entrypoint: `sweep_royalty_to_core_vault`

Add an entry function (new module or in `vault_ops`) that:

Inputs:
- `nft_object: Object<Token>`
- `asset_metadata: Object<Metadata>` (FA metadata)

Steps:
1. Derive `nft_addr` from `nft_object`.
2. Read `RoyaltyEscrowRef` for the NFT to get `escrow_addr` and split bps.
3. Read escrow balance for this FA.
4. Withdraw escrow funds.
5. Split:
   - `vault_part = mul_div(amount, vault_share_bps, 10_000)`
   - `creator_part = amount - vault_part` (or explicit bps)
6. Deposit:
   - `creator_part` to `creator_payout_addr` (primary store deposit)
   - `vault_part` into NFT **Core Vault** (use existing internal deposit path; this is already how mint seeding is done)
7. Emit `RoyaltySwept` event with `(nft_addr, fa_addr, amount, vault_part, creator_part, escrow_addr)`.

Safety/robustness notes:
- Must handle zero balances and rounding (leave dust in escrow or allocate dust to creator/vault deterministically).
- Must be idempotent in the “already swept” sense by relying on escrow balance: if balance is zero, no-op.

### Optional: `sweep_many` batching

Add `sweep_many(nft_addrs, fa_metadata)` or `sweep_for_collection(collection_addr, fa_metadata, limit)` to reduce backend costs.

### Optional: access control choices

Two viable options:
- **Permissionless sweep**: anyone can call sweep; funds always go to creator + vault anyway.
- **Permissioned sweep**: only a designated sweeper can call; reduces spam but introduces operational dependency.

Permissionless is usually preferable here because it reduces trust and improves liveness.

## Off-chain Automation (Rust)

### What it does

A small Rust service continuously watches chain activity and submits sweep transactions when it sees royalties paid into escrow addresses.

### Data sources

Use Cedra Indexer / Transaction Stream concepts:
- `https://docs.cedra.network/indexer/how-it-works`

Practical approach:
- Subscribe/stream transactions.
- Filter events / writesets to detect deposits to known `escrow_addr` (from `RoyaltyEscrowRef` mapping).

### How it stays lightweight and safe

- It does **not** custody user funds long-term; royalties sit on-chain in escrow until swept.
- It signs a sweep transaction (and pays gas), which:
  - moves escrow balance to creator and NFT core vault deterministically
- Maintain a persistent checkpoint (`last_success_version`) for restart safety.
- Maintain a dedupe key per `(txn_version, escrow_addr, fa_addr)` to avoid re-sweeping from the same observed trigger.

### SDK

Use Cedra Rust SDK reference:
- `https://docs.cedra.network/sdks/rust-sdk`

## “Instant / Atomic” Variant (Marketplace integration)

If you control or partner with a marketplace, you can get true atomicity:

1. Marketplace settles sale.
2. Marketplace pays royalty to `escrow_addr` (standard).
3. Marketplace calls `sweep_royalty_to_core_vault` immediately as part of its settlement flow (same tx if supported by their architecture, otherwise back-to-back tx with strong guarantees).

You can support both:
- “best effort near-real-time” via Rust watcher for all marketplaces
- “instant” for integrated marketplaces

## Compatibility / Migration

### New collections / newly minted NFTs

- Use the new mint flow to create `RoyaltyEscrowRef` and set token-level royalty payee to escrow.

### Existing NFTs already minted

You cannot retroactively force third-party marketplaces to pay royalties differently unless token/collection royalty can be updated.

If you can update royalties:
- Use `cedra_token_objects::royalty::update` via the correct mutator permissions for the token or collection (requires you to have stored the needed `MutatorRef` / capability or designed for it).

If you cannot update royalties:
- You can still add sweep logic, but royalties will keep going to the existing payee address; you’d need a separate mechanism (manual deposits, or marketplace integration) to fund core vaults.

## Acceptance Criteria

- For a secondary sale where the marketplace pays royalties to the standard royalty payee:
  - The royalty amount is split by configured bps.
  - Creator share lands at `creator_payout_addr`.
  - Vault share lands in the NFT’s **Core Vault**.
  - Sweep happens automatically (backend) within N seconds of observed royalty payment.
- No changes required in generic marketplaces beyond honoring Cedra framework royalties.
- Upgrade remains within “compatible” constraints: only additive structs/functions.

## Verification Plan

### Move tests

- Royalty escrow ref creation per NFT.
- Sweep math correctness (bps split, rounding).
- Sweep deposits creator portion correctly.
- Sweep deposits vault portion into core vault correctly.
- Sweep idempotency (second sweep on zero balance is no-op).
- Events emitted with correct fields.

### End-to-end (local / testnet)

1. Create collection + mint vaulted NFT with escrow payee.
2. Simulate royalty payment into escrow address in the sale currency FA.
3. Run sweeper (or call sweep entry directly).
4. Assert:
   - creator primary store increased by expected amount
   - core vault balance increased by expected amount

## Open Questions (need answers before implementation)

1. Define “instant”: atomic with sale, or seconds-later acceptable?

   - Instant is preferred for true atomicity, but may require additional complexity in the sweeper.
2. Which FA(s) should royalties be swept in (CEDRA only, or arbitrary)?
   - arbitrary is preferred for flexibility, but may require additional complexity in the sweeper.
3. Is the vault share always the same per collection, or per token, or mutable?
   -its set at collection creation and cannot be changed.
4. Do you need multi-recipient splits beyond (creator + vault)?
   - no its strictly creator + core vault.
5. Do you require permissionless sweep, or only your backend can sweep?
   - permissionless is preferred for flexibility, but may require additional complexity in the sweeper.

## Implementation Phases (suggested)

1. **Spec + interfaces**
   - Finalize “instant” definition, bps rules, event schema, and upgrade constraints.
2. **On-chain plumbing**
   - `RoyaltyEscrowRef` storage + mint integration.
   - `sweep_royalty_to_core_vault` entry + tests.
3. **Rust sweeper MVP**
   - Stream, detect escrow deposits, call sweep, checkpointing.
4. **Hardening**
   - batching, rate limiting, backoff, metrics, reorg/resume behavior.
5. **Optional marketplace integration**
   - atomic settlement for partnered marketplaces.

