/// CVN-1: View Functions
/// 
/// All read-only view functions for querying vault and collection state.
module cvn1_vault::vault_views {
    use std::string::String;
    
    use cedra_framework::object::Object;
    use cedra_token_objects::token::{Self, Token};
    
    use cvn1_vault::vault_core::{Self, VaultBalance};

    // ============================================
    // View Functions
    // ============================================

    #[view]
    /// Get all vault balances for an NFT (combined core + rewards)
    /// Returns vector of VaultBalance structs with fa_metadata_address and balance
    public fun get_vault_balances(nft_addr: address): vector<VaultBalance> {
        vault_core::get_vault_balances(nft_addr)
    }

    #[view]
    /// Get CORE vault balances for an NFT (long-term value)
    /// Only redeemable via burn_and_redeem
    public fun get_core_vault_balances(nft_addr: address): vector<VaultBalance> {
        vault_core::get_core_vault_balances(nft_addr)
    }

    #[view]
    /// Get REWARDS vault balances for an NFT (short-term value)
    /// Claimable anytime via claim_rewards
    public fun get_rewards_vault_balances(nft_addr: address): vector<VaultBalance> {
        vault_core::get_rewards_vault_balances(nft_addr)
    }

    #[view]
    /// Get collection configuration
    /// Returns (creator_royalty_bps, vault_royalty_bps, allowed_assets, creator_payout_addr)
    public fun get_vault_config(collection_addr: address): (u16, u16, vector<address>, address) {
        assert!(vault_core::config_exists(collection_addr), vault_core::err_config_not_found());
        vault_core::get_config_for_view(collection_addr)
    }

    #[view]
    /// Check if a vault exists for an NFT
    public fun vault_exists(nft_addr: address): bool {
        vault_core::vault_exists(nft_addr)
    }

    #[view]
    /// Get vault info details
    /// Returns (is_redeemable, creator_addr, last_sale_compliant)
    public fun get_vault_info(nft_addr: address): (bool, address) {
        assert!(vault_core::vault_exists(nft_addr), vault_core::err_vault_not_found());
        vault_core::get_vault_info_for_view(nft_addr)
    }

    #[view]
    /// Get token metadata for a vaulted NFT
    /// Returns (name, description, uri)
    /// 
    /// This is a convenience function that wraps the token module's getters.
    public fun get_token_metadata(nft_object: Object<Token>): (String, String, String) {
        (
            token::name(nft_object),
            token::description(nft_object),
            token::uri(nft_object)
        )
    }

    #[view]
    /// Get a summary of an NFT's vault
    /// Returns (asset_count, total_asset_types, is_redeemable, is_compliant)
    /// 
    /// Useful for displaying vault status at a glance.
    public fun get_vault_summary(nft_addr: address): (u64, u64, bool) {
        assert!(vault_core::vault_exists(nft_addr), vault_core::err_vault_not_found());
        
        let balances = vault_core::get_vault_balances(nft_addr);
        let (is_redeemable, _creator_addr) = vault_core::get_vault_info_for_view(nft_addr);
        
        // Count total assets and non-zero balances
        let total_types = std::vector::length(&balances);
        let non_zero_count = 0u64;
        let i = 0u64;
        while (i < total_types) {
            let balance = std::vector::borrow(&balances, i);
            if (vault_core::get_balance_amount(balance) > 0) {
                non_zero_count = non_zero_count + 1;
            };
            i = i + 1;
        };
        
        (non_zero_count, total_types, is_redeemable)
    }

    // ============================================
    // v4: Supply View Functions
    // ============================================

    #[view]
    /// Get collection supply info (v4)
    /// Returns (minted_count, max_supply)
    /// If max_supply == 0, the collection has unlimited supply.
    public fun get_collection_supply(collection_addr: address): (u64, u64) {
        assert!(vault_core::config_exists(collection_addr), vault_core::err_config_not_found());
        vault_core::get_supply(collection_addr)
    }

    #[view]
    /// Check if collection can still mint (v4)
    /// Returns true if minted_count < max_supply OR max_supply == 0 (unlimited)
    public fun can_mint(collection_addr: address): bool {
        if (!vault_core::config_exists(collection_addr)) {
            return false
        };
        vault_core::can_mint(collection_addr)
    }
}
