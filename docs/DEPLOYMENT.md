# CVN-1 Testnet Deployment

## Current Version: 6.0.0

> **Note:** This repo uses a modular Move package. Use your configured Cedra CLI profile.

## Deployment Command

```bash
# Using the cvn1_v2 profile
cedra move publish --profile cvn1_v2 --named-addresses cvn1_vault=cvn1_v2
```

## Modules

The CVN-1 Move package is split into focused modules:

| Module | Description |
|--------|-------------|
| `vault_core` | Core data structures, constants, errors |
| `vault_events` | Event definitions and emission |
| `collection` | Collection initialization |
| `minting` | All mint variants |
| `vault_ops` | Deposit, burn/redeem operations |
| `vault_views` | Read-only view functions |

## Entry Functions

| Module | Function |
|--------|----------|
| `collection` | `init_collection_config` |
| `minting` | `creator_mint_vaulted_nft`, `creator_self_mint`, `public_mint` |
| `vault_ops` | `deposit_to_core_vault`, `deposit_to_rewards_vault`, `claim_rewards`, `burn_and_redeem`, `sweep_royalty_to_core_vault` |

## View Functions

| Module | Function |
|--------|----------|
| `collection` | `get_collection_address` |
| `vault_views` | `get_vault_balances`, `get_core_vault_balances`, `get_rewards_vault_balances`, `get_vault_config`, `vault_exists`, `royalty_escrow_exists`, `get_royalty_escrow_address`, `get_royalty_escrow_balance`, `last_sale_used_vault_royalty`, `get_vault_info`, `get_token_metadata`, `get_vault_summary`, `get_collection_supply`, `can_mint` |

---

## Previous Deployment (v1.0.0)

| Field | Value |
|-------|-------|
| **Network** | Cedra Testnet |
| **Module Address** | `0x87e87b2f6ca01a0a02d68e18305f700435fdb76e445db9d24c84a121f2d5cd2c` |
| **Module Name** | `vaulted_collection` (monolithic) |
| **Transaction Hash** | `0x10cbf3c19484338437fbbdd143a2aef104bd6949b6b881e8172e42beeb6d813f` |
| **Deployed At** | 2025-12-08 |

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 2.0.0 | 2025-12-09 | Modular architecture (7 modules), resource cleanup, new views |
| 1.0.0 | 2025-12-08 | Initial testnet deployment (monolithic) |
