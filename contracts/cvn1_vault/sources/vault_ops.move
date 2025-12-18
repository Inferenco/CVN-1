/// CVN-1: Vault Operations (v3: Dual Vault)
/// 
/// Deposit to core/rewards vaults, claim rewards, and burn/redeem operations.
module cvn1_vault::vault_ops {
    use std::signer;
    use std::vector;
    use std::option;
    
    use cedra_framework::object::{Self, Object};
    use cedra_framework::fungible_asset::{Self, Metadata, FungibleStore};
    use cedra_framework::primary_fungible_store;
    
    use cedra_token_objects::token::{Self, Token};
    
    use cedra_std::smart_table;
    
    use cvn1_vault::vault_core;
    use cvn1_vault::vault_events;

    // ============================================
    // Entry Functions - Deposits
    // ============================================

    /// Deposit to CORE vault (long-term value)
    /// 
    /// Core vault holds long-term value: staking rewards, loyalty bonuses, etc.
    /// Only redeemable via burn_and_redeem (destroys NFT).
    /// Anyone can deposit.
    public entry fun deposit_to_core_vault(
        depositor: &signer,
        nft_object: Object<Token>,
        fa_metadata: Object<Metadata>,
        amount: u64
    ) {
        assert!(amount > 0, vault_core::err_invalid_amount());
        
        let nft_addr = object::object_address(&nft_object);
        assert!(vault_core::vault_exists(nft_addr), vault_core::err_vault_not_found());
        
        let depositor_addr = signer::address_of(depositor);
        let fa_addr = object::object_address(&fa_metadata);
        
        // Get collection addr to check allowlist
        let collection = token::collection_object(nft_object);
        let collection_addr = object::object_address(&collection);
        
        // Check allowlist
        assert!(
            vault_core::check_allowlist(collection_addr, fa_addr),
            vault_core::err_asset_not_allowed()
        );
        
        // Withdraw from depositor's primary store
        let fa = primary_fungible_store::withdraw(depositor, fa_metadata, amount);
        
        // Deposit into CORE vault
        vault_core::deposit_to_core_vault(nft_addr, fa_metadata, fa);
        
        // Emit deposit event
        vault_events::emit_deposited(nft_addr, fa_addr, amount, depositor_addr);
    }

    /// Deposit to REWARDS vault (short-term value)
    /// 
    /// Rewards vault holds short-term value: gaming wins, activity rewards, etc.
    /// Claimable anytime via claim_rewards (keeps NFT).
    /// Anyone can deposit.
    public entry fun deposit_to_rewards_vault(
        depositor: &signer,
        nft_object: Object<Token>,
        fa_metadata: Object<Metadata>,
        amount: u64
    ) {
        assert!(amount > 0, vault_core::err_invalid_amount());
        
        let nft_addr = object::object_address(&nft_object);
        assert!(vault_core::vault_exists(nft_addr), vault_core::err_vault_not_found());
        
        let depositor_addr = signer::address_of(depositor);
        let fa_addr = object::object_address(&fa_metadata);
        
        // Get collection addr to check allowlist
        let collection = token::collection_object(nft_object);
        let collection_addr = object::object_address(&collection);
        
        // Check allowlist
        assert!(
            vault_core::check_allowlist(collection_addr, fa_addr),
            vault_core::err_asset_not_allowed()
        );
        
        // Withdraw from depositor's primary store
        let fa = primary_fungible_store::withdraw(depositor, fa_metadata, amount);
        
        // Deposit into REWARDS vault
        vault_core::deposit_to_rewards_vault(nft_addr, fa_metadata, fa);
        
        // Emit deposit event (TODO: separate event for rewards deposit)
        vault_events::emit_deposited(nft_addr, fa_addr, amount, depositor_addr);
    }

    // ============================================
    // Entry Functions - Rewards Claim
    // ============================================

    /// Claim all rewards from the rewards vault without burning the NFT
    /// 
    /// Only the owner can claim rewards. The NFT remains intact.
    /// Core vault contents are not affected.
    public entry fun claim_rewards(
        owner: &signer,
        nft_object: Object<Token>
    ) {
        let owner_addr = signer::address_of(owner);
        let nft_addr = object::object_address(&nft_object);
        
        // Verify ownership
        assert!(object::owner(nft_object) == owner_addr, vault_core::err_not_owner());
        
        // Verify vault exists
        assert!(vault_core::vault_exists(nft_addr), vault_core::err_vault_not_found());
        
        // Withdraw all rewards vault contents
        let claimed_assets = vault_core::withdraw_rewards_vault(nft_addr, owner_addr);
        
        // Emit claim event
        vault_events::emit_rewards_claimed(nft_addr, owner_addr, claimed_assets);
    }

    // ============================================
    // Entry Functions - Burn and Redeem
    // ============================================

    /// Burn an NFT and redeem ALL vault contents (core + rewards) to the owner
    /// 
    /// This function:
    /// 1. Verifies ownership and redeemability
    /// 2. Withdraws ALL core vault contents to owner
    /// 3. Withdraws ALL rewards vault contents to owner
    /// 4. Burns the token
    /// 5. Cleans up all resources
    public entry fun burn_and_redeem(
        owner: &signer,
        nft_object: Object<Token>
    ) {
        let owner_addr = signer::address_of(owner);
        let nft_addr = object::object_address(&nft_object);
        
        // Verify ownership
        assert!(object::owner(nft_object) == owner_addr, vault_core::err_not_owner());
        
        // Verify vault exists and is redeemable
        assert!(vault_core::vault_exists(nft_addr), vault_core::err_vault_not_found());
        assert!(vault_core::is_vault_redeemable(nft_addr), vault_core::err_not_redeemable());
        
        // Extract vault for redemption (destructive - removes VaultInfo)
        let (extend_ref, burn_ref, delete_ref_opt, 
             core_stores, core_delete_refs, 
             rewards_stores, rewards_delete_refs) = 
            vault_core::extract_vault_for_redeem(nft_addr);
        
        // Get vault signer for withdrawals
        let vault_signer = object::generate_signer_for_extending(&extend_ref);
        
        // Collect all FA addresses for the event
        let redeemed_assets = vector::empty<address>();
        
        // ============================================
        // Withdraw from CORE vault
        // ============================================
        let core_keys = smart_table::keys(&core_stores);
        let i = 0;
        let len = vector::length(&core_keys);
        while (i < len) {
            let fa_addr = *vector::borrow(&core_keys, i);
            let store_addr = *smart_table::borrow(&core_stores, fa_addr);
            let store = object::address_to_object<FungibleStore>(store_addr);
            
            let balance = fungible_asset::balance(store);
            if (balance > 0) {
                let fa = fungible_asset::withdraw(&vault_signer, store, balance);
                primary_fungible_store::deposit(owner_addr, fa);
                vector::push_back(&mut redeemed_assets, fa_addr);
            };
            
            // Delete the empty FungibleStore object
            let store_delete_ref = smart_table::remove(&mut core_delete_refs, fa_addr);
            object::delete(store_delete_ref);
            
            i = i + 1;
        };
        
        // ============================================
        // Withdraw from REWARDS vault
        // ============================================
        let rewards_keys = smart_table::keys(&rewards_stores);
        let j = 0;
        let rewards_len = vector::length(&rewards_keys);
        while (j < rewards_len) {
            let fa_addr = *vector::borrow(&rewards_keys, j);
            let store_addr = *smart_table::borrow(&rewards_stores, fa_addr);
            let store = object::address_to_object<FungibleStore>(store_addr);
            
            let balance = fungible_asset::balance(store);
            if (balance > 0) {
                let fa = fungible_asset::withdraw(&vault_signer, store, balance);
                primary_fungible_store::deposit(owner_addr, fa);
                // Only add if not already in list (de-dup)
                if (!vector::contains(&redeemed_assets, &fa_addr)) {
                    vector::push_back(&mut redeemed_assets, fa_addr);
                };
            };
            
            // Delete the empty FungibleStore object
            let store_delete_ref = smart_table::remove(&mut rewards_delete_refs, fa_addr);
            object::delete(store_delete_ref);
            
            j = j + 1;
        };
        
        // Clean up all SmartTables
        smart_table::destroy(core_stores);
        smart_table::destroy(core_delete_refs);
        smart_table::destroy(rewards_stores);
        smart_table::destroy(rewards_delete_refs);
        
        // Emit redeem event
        vault_events::emit_redeemed(nft_addr, owner_addr, redeemed_assets);
        
        // Burn the token (this handles token resource cleanup)
        token::burn(burn_ref);
        
        // Note: We don't call object::delete here because:
        // 1. token::burn already handles the Token resource cleanup
        // 2. The object may still have other framework resources attached
        // 3. Attempting to delete causes "Failed to move resource" errors
        // Just discard the delete_ref option
        if (option::is_some(&delete_ref_opt)) {
            option::destroy_some(delete_ref_opt);
        } else {
            option::destroy_none(delete_ref_opt);
        };
    }

    // ============================================
    // Entry Functions - Distribute Royalties
    // ============================================

    /// Distribute royalties to the core vault
    public entry fun distribute_royalties(
        caller: &signer,
        collection_addr: address,
        fa_addr: address,
    ) {
        vault_core::distribute_royalties(caller, collection_addr, fa_addr);
    }
}
