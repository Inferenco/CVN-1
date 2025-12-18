# CVN-1 v6.0.0 Changelog

v6 adds automated secondary-sale royalty splitting so the vault portion is deposited into the traded NFT’s **Core Vault**.

## Highlights

- **Per-NFT royalty escrow**: minted tokens set token-level framework royalty payee to a dedicated escrow address.
- **Permissionless sweep**: anyone can call `cvn1_vault::vault_ops::sweep_royalty_to_core_vault` to split escrowed royalties into creator payout + Core Vault deposit.
- **Arbitrary fungible assets**: sweep operates per fungible-asset metadata address.
- **Automation**: `royalty_sweeper/` Rust CLI can poll and submit sweep transactions near-real-time.

## New / Updated On-chain Interfaces

- **New keyed resource**: `cvn1_vault::vault_core::RoyaltyEscrowRef` (stored under each NFT object address).
- **New entry functions**: `cvn1_vault::vault_ops::sweep_royalty_to_core_vault`, `cvn1_vault::vault_ops::sweep_royalty_to_core_vault_many`.
- **New view functions**: `cvn1_vault::vault_views::royalty_escrow_exists`, `cvn1_vault::vault_views::get_royalty_escrow_address`, `cvn1_vault::vault_views::get_royalty_escrow_balance`.
- **New event**: `cvn1_vault::vault_events::RoyaltySweptToCore`.
