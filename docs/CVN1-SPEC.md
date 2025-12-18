# CVN-1: Cedra Vaulted NFT Standard (v6)

> A standard for NFTs with dual built-in fungible asset vaults on Cedra Network.

## Overview

CVN-1 v6 features a **dual vault architecture** with **framework royalties** and a **permissionless royalty sweep** into the traded NFT’s **Core Vault**:

| Vault | Purpose | Redemption |
|-------|---------|------------|
| **Core Vault** | Long-term value (mint seed, staking) | Burn NFT only |
| **Rewards Vault** | Short-term value (deposits, gaming) | Claim anytime |

### v6 Changes

- **Framework Royalties** — Royalties are set via `cedra_token_objects::royalty`
- **Per-NFT Royalty Escrow** — Token-level royalty payee is a dedicated escrow address per NFT
- **Core Vault Royalties** — `vault_royalty_bps` is used to route a share of royalties into the NFT’s Core Vault
- **Permissionless Sweep** — `vault_ops::sweep_royalty_to_core_vault` splits escrowed funds → creator payout + Core Vault

This enables:
- **Floor Value** — Core vault defines minimum intrinsic value
- **Passive Income** — Claim rewards without selling
- **Gaming Integration** — Deposit activity rewards to either vault
- **Burn-to-Redeem** — Owners burn NFT to claim both vaults
- **Automatic Royalties** — Marketplaces discover and enforce royalties automatically

## Module Architecture

```
contracts/cvn1_vault/sources/
├── vault_core.move      # Core data structures, dual vault logic
├── vault_events.move    # Event definitions
├── collection.move      # Collection initialization (with framework royalty)
├── minting.move         # NFT minting (inherits collection royalty)
├── vault_ops.move       # Dual deposit, claim_rewards, burn_and_redeem
└── vault_views.move     # Read-only view functions
```

## Data Structures

### VaultedCollectionConfig

Stored on the collection object's address:

```move
struct VaultedCollectionConfig has key {
    creator_royalty_bps: u16,      // Creator royalty (set via framework)
    vault_royalty_bps: u16,        // Core vault royalty (funds Core Vault via sweep)
    mint_vault_bps: u16,           // % of mint price to Core Vault
    mint_price: u64,
    mint_price_fa: address,
    allowed_assets: vector<address>,
    creator_payout_addr: address,
    collection_extend_ref: ExtendRef, // For collection signer
    max_supply: u64,               // 0 = unlimited
    minted_count: u64,
}
```

### VaultInfo (Dual Vault)

Stored on each NFT's object address:

```move
struct VaultInfo has key {
    // Core Vault (burn-to-redeem only)
    core_stores: SmartTable<address, address>,
    core_delete_refs: SmartTable<address, DeleteRef>,
    is_core_redeemable: bool,
    
    // Rewards Vault (claim anytime)
    rewards_stores: SmartTable<address, address>,
    rewards_delete_refs: SmartTable<address, DeleteRef>,
    
    // Object lifecycle
    extend_ref: ExtendRef,
    delete_ref: Option<DeleteRef>,
    burn_ref: BurnRef,
    
    // Metadata
    creator_addr: address,
    last_sale_compliant: bool,
}
```

### RoyaltyEscrowRef (v6)

Stored on each NFT's object address (additive v6 resource):

```move
struct RoyaltyEscrowRef has key {
    escrow_addr: address,
    escrow_extend_ref: ExtendRef,
    escrow_delete_ref: Option<DeleteRef>,
}
```

## Entry Functions

### Collection Setup

```move
public entry fun init_collection_config(
    creator: &signer,
    collection_name: String,
    collection_description: String,
    collection_uri: String,
    creator_royalty_bps: u16,      // Framework royalty (enforced by marketplaces)
    vault_royalty_bps: u16,        // Core vault royalty bps (secondary sales)
    mint_vault_bps: u16,           // % of mint to Core Vault
    mint_price: u64,
    mint_price_fa: address,
    allowed_assets: vector<address>,
    creator_payout_addr: address,
    max_supply: u64                // v4: 0 = unlimited
)
```

### Minting

```move
// All mint functions:
// 1. Seed the CORE vault with mint_vault_bps %
// 2. Create per-NFT royalty escrow and set token-level royalty payee to escrow (v6)

public entry fun creator_mint_vaulted_nft(...)
public entry fun creator_self_mint(...)
public entry fun public_mint(...)
```

### Vault Operations

```move
// Deposit to CORE vault (long-term value)
public entry fun deposit_to_core_vault(
    depositor: &signer,
    nft_object: Object<Token>,
    fa_metadata: Object<Metadata>,
    amount: u64
)

// Deposit to REWARDS vault (short-term value)
public entry fun deposit_to_rewards_vault(
    depositor: &signer,
    nft_object: Object<Token>,
    fa_metadata: Object<Metadata>,
    amount: u64
)

// Permissionlessly sweep escrowed royalties → creator payout + Core Vault (v6)
public entry fun sweep_royalty_to_core_vault(
    caller: &signer,
    nft_object: Object<Token>,
    fa_metadata: Object<Metadata>,
)

// Batch sweep royalties for many NFTs in one transaction (v6)
public entry fun sweep_royalty_to_core_vault_many(
    caller: &signer,
    nft_addrs: vector<address>,
    fa_metadata: Object<Metadata>,
)

// Claim rewards without burning NFT
public entry fun claim_rewards(
    owner: &signer,
    nft_object: Object<Token>
)

// Burn NFT and claim BOTH vaults
public entry fun burn_and_redeem(
    owner: &signer,
    nft_object: Object<Token>
)
```

## Royalty Model (v6)

### Framework Royalties

CVN-1 v6 uses **Cedra Framework royalties** (`cedra_token_objects::royalty`) with a per-NFT escrow payee:

| Royalty Type | Recipient | Enforcement |
|--------------|-----------|-------------|
| **Creator Royalty** | `creator_payout_addr` | Paid on sweep |
| **Core Vault Royalty** | NFT Core Vault | Paid on sweep |

Marketplaces supporting Cedra’s standard royalty API will:
1. Discover the royalty rate from the token (preferred) or collection
2. Pay the royalty amount to the discovered `payee_address`

In CVN-1 v6, minted tokens set token-level royalty to:
- `numerator = creator_royalty_bps + vault_royalty_bps`
- `denominator = 10000`
- `payee_address = per-NFT escrow address`

Then anyone can call `vault_ops::sweep_royalty_to_core_vault` to split the escrow balance proportionally by `creator_royalty_bps` and `vault_royalty_bps`, depositing the vault cut into the NFT’s Core Vault.

### Vault Value Sources

Vaults receive value from:

| Source | Destination |
|--------|-------------|
| Mint seed (% of mint price) | Core Vault |
| Staking rewards | Core Vault |
| Gaming wins/activities | Rewards Vault |
| Manual deposits | Either (depositor chooses) |

## View Functions

| Function | Returns |
|----------|---------|
| `get_vault_balances(nft_addr)` | Combined core + rewards |
| `get_core_vault_balances(nft_addr)` | Core vault only |
| `get_rewards_vault_balances(nft_addr)` | Rewards vault only |
| `get_vault_config(collection_addr)` | Config tuple |
| `vault_exists(nft_addr)` | `bool` |
| `royalty_escrow_exists(nft_addr)` | `bool` |
| `get_royalty_escrow_address(nft_addr)` | `address` |
| `get_royalty_escrow_balance(nft_addr, fa_metadata)` | `u64` |
| `get_vault_info(nft_addr)` | `(is_redeemable, creator, compliant)` |
| `get_token_metadata(nft_object)` | `(name, description, uri)` |
| `get_collection_address(creator, name)` | `address` |

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| 1 | `ENOT_CREATOR` | Caller is not the collection creator |
| 2 | `ENOT_OWNER` | Caller is not the NFT owner |
| 3 | `ENOT_REDEEMABLE` | Core vault is not redeemable |
| 4 | `EINVALID_AMOUNT` | Invalid amount (must be > 0) |
| 5 | `EASSET_NOT_ALLOWED` | FA not in allowlist |
| 6 | `EINSUFFICIENT_BALANCE` | Insufficient balance |
| 7 | `ECOLLECTION_ALREADY_EXISTS` | Collection already initialized |
| 8 | `EVAULT_NOT_FOUND` | No vault exists at address |
| 9 | `EINVALID_ROYALTY_BPS` | Royalty BPS > 10000 |
| 10 | `ECONFIG_NOT_FOUND` | Collection config not found |
| 11 | `EMAX_SUPPLY_REACHED` | Max supply reached |
| 12 | `EROYALTY_ESCROW_NOT_FOUND` | Royalty escrow not found for NFT |

## Events

```move
#[event] struct VaultedNFTMinted { nft_addr, collection_addr, creator, to, is_redeemable }
#[event] struct VaultDeposited { nft_addr, fa_type, amount, depositor }
#[event] struct VaultRedeemed { nft_addr, redeemer, redeemed_assets }
#[event] struct RoyaltySweptToCore { nft_addr, fa_type, gross_amount, creator_cut, core_vault_cut, escrow_addr, sweeper }
#[event] struct RewardsClaimed { nft_addr, claimer, assets_claimed }
```

## Migration Notes

If upgrading from earlier versions:

1. **Royalties** — No custom settlement function is required; royalties are enforced via the Cedra framework
2. **`vault_royalty_bps`** — Used again in v6 to fund the NFT Core Vault via sweep
3. **Existing NFTs** — NFTs minted before v6 won’t have a per-NFT escrow unless re-minted or explicitly upgraded (if possible)

## License

Proprietary - Singularity Shift Ltd.
