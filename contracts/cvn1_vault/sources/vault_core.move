/// CVN-1: Core Data Structures and Constants
/// 
/// This module contains the foundational types, error codes, and constants
/// used across all CVN-1 modules.
/// 
/// NOTE: Due to Move's reference rules, we cannot return references from
/// borrow_global. Each module must do its own borrowing. This module
/// provides constructors, move operations, and helper functions.
module cvn1_vault::vault_core {
    use std::option::Option;
    use std::vector;
    use std::signer;
    use cedra_framework::object::{Self, ExtendRef, DeleteRef, Object};
    use cedra_framework::fungible_asset::{Self, Metadata, FungibleStore, FungibleAsset};
    use cedra_framework::primary_fungible_store;
    use cedra_token_objects::token::BurnRef;
    use cedra_std::math64;
    use cedra_std::smart_table::{Self, SmartTable};

    // ============================================
    // Friend Declarations
    // ============================================
    
    friend cvn1_vault::collection;
    friend cvn1_vault::minting;
    friend cvn1_vault::vault_ops;
    friend cvn1_vault::vault_views;

    // ============================================
    // Error Codes
    // ============================================
    
    /// Caller is not the collection creator
    const ENOT_CREATOR: u64 = 1;
    /// Caller is not the current NFT owner
    const ENOT_OWNER: u64 = 2;
    /// NFT vault is not redeemable
    const ENOT_REDEEMABLE: u64 = 3;
    /// Amount must be greater than zero
    const EINVALID_AMOUNT: u64 = 4;
    /// Asset type not in allowlist
    const EASSET_NOT_ALLOWED: u64 = 5;
    /// Insufficient balance in vault
    const EINSUFFICIENT_BALANCE: u64 = 6;
    /// Collection already exists for this creator
    const ECOLLECTION_ALREADY_EXISTS: u64 = 7;
    /// Vault not found for NFT
    const EVAULT_NOT_FOUND: u64 = 8;
    /// Invalid royalty basis points (exceeds 10000)
    const EINVALID_ROYALTY_BPS: u64 = 9;
    /// Config not found for collection
    const ECONFIG_NOT_FOUND: u64 = 10;
    /// Max supply reached for collection
    const EMAX_SUPPLY_REACHED: u64 = 11;
    /// Royalty escrow not found for NFT
    const EROYALTY_ESCROW_NOT_FOUND: u64 = 12;
    /// NFT not found in collection
    const ENFT_NOT_FOUND: u64 = 13;
    
    /// Maximum basis points (100%)
    const MAX_BPS: u64 = 10000;

    // ============================================
    // Public Getters for Constants/Errors
    // ============================================

    public fun max_bps(): u64 { MAX_BPS }
    public fun err_not_creator(): u64 { ENOT_CREATOR }
    public fun err_not_owner(): u64 { ENOT_OWNER }
    public fun err_not_redeemable(): u64 { ENOT_REDEEMABLE }
    public fun err_invalid_amount(): u64 { EINVALID_AMOUNT }
    public fun err_asset_not_allowed(): u64 { EASSET_NOT_ALLOWED }
    public fun err_insufficient_balance(): u64 { EINSUFFICIENT_BALANCE }
    public fun err_collection_already_exists(): u64 { ECOLLECTION_ALREADY_EXISTS }
    public fun err_vault_not_found(): u64 { EVAULT_NOT_FOUND }
    public fun err_invalid_royalty_bps(): u64 { EINVALID_ROYALTY_BPS }
    public fun err_config_not_found(): u64 { ECONFIG_NOT_FOUND }
    public fun err_max_supply_reached(): u64 { EMAX_SUPPLY_REACHED }
    public fun err_royalty_escrow_not_found(): u64 { EROYALTY_ESCROW_NOT_FOUND }
    public fun err_nft_not_found(): u64 { ENFT_NOT_FOUND }

    // ============================================
    // Data Structures
    // ============================================

    /// Configuration for a vaulted NFT collection (v4)
    /// Stored under the collection object's address
    struct VaultedCollectionConfig has key {
        /// Creator royalty in basis points (10000 = 100%)
        creator_royalty_bps: u16,
        /// Vault top-up royalty in basis points (from secondary sales)
        vault_royalty_bps: u16,
        /// Percentage of mint fee to seed into vault (0-10000 = 0-100%)
        mint_vault_bps: u16,
        /// Mint price in smallest units (0 = free mint)
        mint_price: u64,
        /// FA metadata address for mint payments (only needed if mint_price > 0)
        mint_price_fa: address,
        /// Allowed FA types for deposits (empty = any FA allowed)
        allowed_assets: vector<address>,
        /// ExtendRef for collection signer (enables public minting)
        collection_extend_ref: ExtendRef,
        /// Maximum tokens that can be minted (0 = unlimited)
        max_supply: u64,
        /// Current count of minted tokens
        minted_count: u64,
        /// Address to receive creator payments
        creator_payout_addr: address,
        /// Nft Addresses minted belonging to this collection
        nft_addresses: vector<address>,
    }

    /// Per-NFT vault information (v3: Dual Vault Architecture)
    /// Stored under the NFT's object address
    /// 
    /// Core Vault: Long-term value (mint seed, staking rewards, loyalty)
    ///             - Only accessible via burn_and_redeem
    /// Rewards Vault: Short-term value (royalties, gaming wins, activities)
    ///             - Accessible via claim_rewards (keeps NFT) or burn_and_redeem
    struct VaultInfo has key {
        // ============================================
        // Core Vault (burn-to-redeem only)
        // ============================================
        /// Maps FA metadata address -> store object address for core vault
        core_stores: SmartTable<address, address>,
        /// Maps FA metadata address -> store DeleteRef for core vault cleanup
        core_delete_refs: SmartTable<address, DeleteRef>,
        /// Whether the core vault can be burned and redeemed
        is_core_redeemable: bool,
        
        // ============================================
        // Rewards Vault (claim anytime)
        // ============================================
        /// Maps FA metadata address -> store object address for rewards vault
        rewards_stores: SmartTable<address, address>,
        /// Maps FA metadata address -> store DeleteRef for rewards vault cleanup
        rewards_delete_refs: SmartTable<address, DeleteRef>,
        
        // ============================================
        // Object Lifecycle References
        // ============================================
        /// Reference for extending vault object capabilities
        extend_ref: ExtendRef,
        /// Reference for cleanup on burn+redeem (optional - named tokens may not support deletion)
        delete_ref: Option<DeleteRef>,
        /// Reference for burning the token
        burn_ref: BurnRef,
        
        // ============================================
        // Metadata
        // ============================================
        /// Address of the collection creator (for config lookup)
        creator_addr: address,
    }

    /// Struct for returning vault balance info in views
    struct VaultBalance has copy, drop {
        fa_metadata_addr: address,
        balance: u64,
    }

    /// Get the balance amount from a VaultBalance struct
    public fun get_balance_amount(vb: &VaultBalance): u64 {
        vb.balance
    }

    /// Get the FA metadata address from a VaultBalance struct
    public fun get_balance_fa_addr(vb: &VaultBalance): address {
        vb.fa_metadata_addr
    }

    // ============================================
    // Existence Checks
    // ============================================

    /// Check if config exists at address
    public fun config_exists(addr: address): bool {
        exists<VaultedCollectionConfig>(addr)
    }

    /// Check if vault exists at address
    public fun vault_exists(addr: address): bool {
        exists<VaultInfo>(addr)
    }

    // ============================================
    // Config Read Functions (return copied values)
    // ============================================

    /// Get all config values at once (avoids multiple borrows)
    public fun get_config_values(addr: address): (u16, u16, u16, u64, address, vector<address>, address, vector<address>) 
    acquires VaultedCollectionConfig {
        let config = borrow_global<VaultedCollectionConfig>(addr);
        (
            config.creator_royalty_bps,
            config.vault_royalty_bps,
            config.mint_vault_bps,
            config.mint_price,
            config.mint_price_fa,
            config.allowed_assets,
            config.creator_payout_addr,
            config.nft_addresses,
        )
    }

    /// Get config for views (subset of fields)
    public fun get_config_for_view(addr: address): (u16, u16, vector<address>, address)
    acquires VaultedCollectionConfig {
        let config = borrow_global<VaultedCollectionConfig>(addr);
        (
            config.creator_royalty_bps,
            config.vault_royalty_bps,
            config.allowed_assets,
            config.creator_payout_addr,
        )
    }

    /// ============================================
    /// v6: Setter Function
    /// ============================================
    
    /// add the nft_address to the nft_addresses vector for a collection
    public(friend) fun add_nft_addresses(collection_addr: address, nft_address: address)
    acquires VaultedCollectionConfig {
        let config = borrow_global_mut<VaultedCollectionConfig>(collection_addr);
        vector::push_back(&mut config.nft_addresses, nft_address);
    }

    /// remove the nft_address from the nft_addresses vector for a collection
    public(friend) fun remove_nft_addresses(collection_addr: address, nft_address: address)
    acquires VaultedCollectionConfig {
        let config = borrow_global_mut<VaultedCollectionConfig>(collection_addr);
        let (found, index) = vector::find(&config.nft_addresses, |addr| addr == &nft_address);
        assert!(found, err_nft_not_found());
        
        vector::remove(&mut config.nft_addresses, index);
    }


    // ============================================
    // v4: Supply Tracking Functions
    // ============================================

    /// Generate collection signer for public minting
    public(friend) fun get_collection_signer(collection_addr: address): signer
    acquires VaultedCollectionConfig {
        let config = borrow_global<VaultedCollectionConfig>(collection_addr);
        object::generate_signer_for_extending(&config.collection_extend_ref)
    }

    /// Check if more tokens can be minted (max_supply == 0 means unlimited)
    public fun can_mint(collection_addr: address): bool
    acquires VaultedCollectionConfig {
        let config = borrow_global<VaultedCollectionConfig>(collection_addr);
        config.max_supply == 0 || config.minted_count < config.max_supply
    }

    /// Increment minted count after successful mint
    public(friend) fun increment_minted_count(collection_addr: address)
    acquires VaultedCollectionConfig {
        let config = borrow_global_mut<VaultedCollectionConfig>(collection_addr);
        config.minted_count = config.minted_count + 1;
    }

    /// Get supply info (minted_count, max_supply)
    public fun get_supply(collection_addr: address): (u64, u64)
    acquires VaultedCollectionConfig {
        let config = borrow_global<VaultedCollectionConfig>(collection_addr);
        (config.minted_count, config.max_supply)
    }

    // ============================================
    // Vault Read Functions (return copied values)
    // ============================================

    /// Get vault info for views (v3: returns core redeemable status)
    public fun get_vault_info_for_view(addr: address): (bool, address)
    acquires VaultInfo {
        let vault = borrow_global<VaultInfo>(addr);
        (vault.is_core_redeemable, vault.creator_addr)
    }

    /// Check if core vault is redeemable
    public fun is_vault_redeemable(addr: address): bool acquires VaultInfo {
        let vault = borrow_global<VaultInfo>(addr);
        vault.is_core_redeemable
    }

    /// Get CORE vault balances for views
    public fun get_core_vault_balances(nft_addr: address): vector<VaultBalance> acquires VaultInfo {
        let balances = vector::empty<VaultBalance>();
        
        if (!exists<VaultInfo>(nft_addr)) {
            return balances
        };
        
        let vault_info = borrow_global<VaultInfo>(nft_addr);
        let keys = smart_table::keys(&vault_info.core_stores);
        let i = 0;
        let len = vector::length(&keys);
        
        while (i < len) {
            let fa_addr = *vector::borrow(&keys, i);
            let store_addr = *smart_table::borrow(&vault_info.core_stores, fa_addr);
            let store = object::address_to_object<FungibleStore>(store_addr);
            let balance = fungible_asset::balance(store);
            
            vector::push_back(&mut balances, VaultBalance {
                fa_metadata_addr: fa_addr,
                balance,
            });
            i = i + 1;
        };
        
        balances
    }

    /// Get REWARDS vault balances for views
    public fun get_rewards_vault_balances(nft_addr: address): vector<VaultBalance> acquires VaultInfo {
        let balances = vector::empty<VaultBalance>();
        
        if (!exists<VaultInfo>(nft_addr)) {
            return balances
        };
        
        let vault_info = borrow_global<VaultInfo>(nft_addr);
        let keys = smart_table::keys(&vault_info.rewards_stores);
        let i = 0;
        let len = vector::length(&keys);
        
        while (i < len) {
            let fa_addr = *vector::borrow(&keys, i);
            let store_addr = *smart_table::borrow(&vault_info.rewards_stores, fa_addr);
            let store = object::address_to_object<FungibleStore>(store_addr);
            let balance = fungible_asset::balance(store);
            
            vector::push_back(&mut balances, VaultBalance {
                fa_metadata_addr: fa_addr,
                balance,
            });
            i = i + 1;
        };
        
        balances
    }

    /// Get combined vault balances (core + rewards) for backwards compatibility
    public fun get_vault_balances(nft_addr: address): vector<VaultBalance> acquires VaultInfo {
        let core = get_core_vault_balances(nft_addr);
        let rewards = get_rewards_vault_balances(nft_addr);
        
        // Append rewards to core
        let i = 0;
        let len = vector::length(&rewards);
        while (i < len) {
            vector::push_back(&mut core, *vector::borrow(&rewards, i));
            i = i + 1;
        };
        
        core
    }

    // ============================================
    // VaultBalance Accessors
    // ============================================

    public fun new_vault_balance(fa_metadata_addr: address, balance: u64): VaultBalance {
        VaultBalance { fa_metadata_addr, balance }
    }

    public fun balance_fa_addr(balance: &VaultBalance): address {
        balance.fa_metadata_addr
    }

    public fun balance_amount(balance: &VaultBalance): u64 {
        balance.balance
    }

    // ============================================
    // Constructor Functions (friend-only)
    // ============================================

    /// Create and store a new VaultedCollectionConfig (v4)
    public(friend) fun create_and_store_config(
        signer: &signer,
        creator_royalty_bps: u16,
        vault_royalty_bps: u16,
        mint_vault_bps: u16,
        mint_price: u64,
        mint_price_fa: address,
        allowed_assets: vector<address>,
        creator_payout_addr: address,
        collection_extend_ref: ExtendRef,
        max_supply: u64,
    ) {
        move_to(signer, VaultedCollectionConfig {
            creator_royalty_bps,
            vault_royalty_bps,
            mint_vault_bps,
            mint_price,
            mint_price_fa,
            allowed_assets,
            creator_payout_addr,
            collection_extend_ref,
            max_supply,
            minted_count: 0,
            nft_addresses: vector::empty(),
        });
    }

    /// Create and store a new VaultInfo (v3: Dual Vault)
    public(friend) fun create_and_store_vault(
        signer: &signer,
        is_core_redeemable: bool,
        extend_ref: ExtendRef,
        delete_ref: Option<DeleteRef>,
        burn_ref: BurnRef,
        creator_addr: address,
    ) {
        move_to(signer, VaultInfo {
            // Core vault (long-term, burn-to-redeem)
            core_stores: smart_table::new(),
            core_delete_refs: smart_table::new(),
            is_core_redeemable,
            
            // Rewards vault (short-term, claim anytime)
            rewards_stores: smart_table::new(),
            rewards_delete_refs: smart_table::new(),
            
            // Object lifecycle
            extend_ref,
            delete_ref,
            burn_ref,
            
            // Metadata
            creator_addr,
        });
    }

    // ============================================
    // Vault Mutation Functions (friend-only)
    // ============================================

    /// Deposit FA into CORE vault (creates store if needed)
    /// 
    /// Core vault is for long-term value: mint seed, staking rewards, loyalty.
    /// Only redeemable via burn_and_redeem (destroys NFT).
    /// 
    /// This is an INTERNAL function - allowlist check handled by vault_ops.
    public(friend) fun deposit_to_core_vault(
        nft_addr: address,
        fa_metadata: Object<Metadata>,
        fa: FungibleAsset
    ) acquires VaultInfo {
        let fa_addr = object::object_address(&fa_metadata);
        let vault_info = borrow_global_mut<VaultInfo>(nft_addr);
        
        // Create store if needed
        if (!smart_table::contains(&vault_info.core_stores, fa_addr)) {
            let vault_signer = object::generate_signer_for_extending(&vault_info.extend_ref);
            let store_constructor = object::create_object_from_account(&vault_signer);
            
            let store_delete_ref = object::generate_delete_ref(&store_constructor);
            let store = fungible_asset::create_store(&store_constructor, fa_metadata);
            let store_addr = object::object_address(&store);
            
            smart_table::add(&mut vault_info.core_stores, fa_addr, store_addr);
            smart_table::add(&mut vault_info.core_delete_refs, fa_addr, store_delete_ref);
        };
        
        // Deposit
        let store_addr = *smart_table::borrow(&vault_info.core_stores, fa_addr);
        let store = object::address_to_object<FungibleStore>(store_addr);
        fungible_asset::deposit(store, fa);
    }

    /// Deposit FA into REWARDS vault (creates store if needed)
    /// 
    /// Rewards vault is for short-term value: royalties, gaming wins, activities.
    /// Claimable anytime via claim_rewards (keeps NFT) or included in burn_and_redeem.
    /// 
    /// This is an INTERNAL function - allowlist check handled by vault_ops.
    public(friend) fun deposit_to_rewards_vault(
        nft_addr: address,
        fa_metadata: Object<Metadata>,
        fa: FungibleAsset
    ) acquires VaultInfo {
        let fa_addr = object::object_address(&fa_metadata);
        let vault_info = borrow_global_mut<VaultInfo>(nft_addr);
        
        // Create store if needed
        if (!smart_table::contains(&vault_info.rewards_stores, fa_addr)) {
            let vault_signer = object::generate_signer_for_extending(&vault_info.extend_ref);
            let store_constructor = object::create_object_from_account(&vault_signer);
            
            let store_delete_ref = object::generate_delete_ref(&store_constructor);
            let store = fungible_asset::create_store(&store_constructor, fa_metadata);
            let store_addr = object::object_address(&store);
            
            smart_table::add(&mut vault_info.rewards_stores, fa_addr, store_addr);
            smart_table::add(&mut vault_info.rewards_delete_refs, fa_addr, store_delete_ref);
        };
        
        // Deposit
        let store_addr = *smart_table::borrow(&vault_info.rewards_stores, fa_addr);
        let store = object::address_to_object<FungibleStore>(store_addr);
        fungible_asset::deposit(store, fa);
    }

    /// Check allowlist for a deposit
    public fun check_allowlist(collection_addr: address, fa_addr: address): bool 
    acquires VaultedCollectionConfig {
        if (!exists<VaultedCollectionConfig>(collection_addr)) {
            return true // No config means no restrictions
        };
        let config = borrow_global<VaultedCollectionConfig>(collection_addr);
        if (vector::is_empty(&config.allowed_assets)) {
            return true // Empty allowlist means all allowed
        };
        vector::contains(&config.allowed_assets, &fa_addr)
    }

    /// Withdraw all rewards vault contents to owner (for claim_rewards)
    /// Returns vector of FA addresses that were claimed
    public(friend) fun withdraw_rewards_vault(
        nft_addr: address,
        owner_addr: address
    ): vector<address> acquires VaultInfo {
        let vault_info = borrow_global_mut<VaultInfo>(nft_addr);
        let vault_signer = object::generate_signer_for_extending(&vault_info.extend_ref);
        
        let claimed_assets = vector::empty<address>();
        let keys = smart_table::keys(&vault_info.rewards_stores);
        let i = 0;
        let len = vector::length(&keys);
        
        while (i < len) {
            let fa_addr = *vector::borrow(&keys, i);
            let store_addr = *smart_table::borrow(&vault_info.rewards_stores, fa_addr);
            let store = object::address_to_object<FungibleStore>(store_addr);
            
            let balance = fungible_asset::balance(store);
            if (balance > 0) {
                let fa = fungible_asset::withdraw(&vault_signer, store, balance);
                primary_fungible_store::deposit(owner_addr, fa);
                vector::push_back(&mut claimed_assets, fa_addr);
            };
            // Note: We keep empty stores for potential future deposits
            
            i = i + 1;
        };
        
        claimed_assets
    }

    /// Move vault out for burn_and_redeem (destructive)
    /// Returns: (extend_ref, burn_ref, delete_ref, core_stores, core_delete_refs, rewards_stores, rewards_delete_refs)
    /// delete_ref may be None for named tokens that don't support deletion
    /// Note: burn_and_redeem should withdraw from BOTH vaults before burning
    public(friend) fun extract_vault_for_redeem(nft_addr: address): (
        ExtendRef, 
        BurnRef, 
        Option<DeleteRef>, 
        SmartTable<address, address>,  // core_stores
        SmartTable<address, DeleteRef>, // core_delete_refs
        SmartTable<address, address>,  // rewards_stores
        SmartTable<address, DeleteRef>  // rewards_delete_refs
    ) acquires VaultInfo {
        let VaultInfo {
            core_stores,
            core_delete_refs,
            is_core_redeemable: _,
            rewards_stores,
            rewards_delete_refs,
            extend_ref,
            delete_ref,
            burn_ref,
            creator_addr: _,
        } = move_from<VaultInfo>(nft_addr);
        
        (extend_ref, burn_ref, delete_ref, core_stores, core_delete_refs, rewards_stores, rewards_delete_refs)
    }

    // ============================================
    // Entry Functions - Distribute Royalties
    // ============================================

    /// Distribute royalties to the core vault
    public(friend) fun distribute_royalties(
        creator: &signer,
        collection_addr: address,
        fa_addr: address,
    ) acquires VaultedCollectionConfig, VaultInfo {
        // Get collection signer first to avoid borrow conflict with config
        let collection_signer = get_collection_signer(collection_addr);

        let creator_addr = signer::address_of(creator);
        let config = borrow_global<VaultedCollectionConfig>(collection_addr);
        assert!(config.creator_payout_addr == creator_addr, err_not_creator());

        let fa_metadata = object::address_to_object<Metadata>(fa_addr);

        let creator_cut = config.creator_royalty_bps;
        let vault_cut = config.vault_royalty_bps;

        let collection_balance = primary_fungible_store::balance(collection_addr, fa_metadata);
        assert!(collection_balance > 0, err_invalid_amount());

        // Calculate creator cut amount
        let creator_cut_amount = math64::mul_div(collection_balance, (creator_cut as u64), 10000);
        
        // Calculate vault cut amount to be split among NFTs
        let vault_cut_amount = math64::mul_div(collection_balance, (vault_cut as u64), 10000);

        // Withdraw and send creator's share
        if (creator_cut_amount > 0) {
            let creator_fa = primary_fungible_store::withdraw(&collection_signer, fa_metadata, creator_cut_amount);
            primary_fungible_store::deposit(config.creator_payout_addr, creator_fa);
        };

        let nft_count = vector::length(&config.nft_addresses);
        // Split vault cut among all NFT addresses
        if (nft_count > 0 && vault_cut_amount > 0) {
            // Calculate per-NFT share
            let per_nft_share = vault_cut_amount / nft_count;

            vector::for_each(config.nft_addresses, |nft_addr| {

                let (found, i) = vector::index_of(&config.nft_addresses, &nft_addr);
                assert!(found, err_nft_not_found());

                let nft_share = if (i == (nft_count - 1)){
                    let amount_left = primary_fungible_store::balance(collection_addr, fa_metadata);
                    amount_left
                } else {
                    per_nft_share
                };
                
                if (nft_share > 0) {
                    // Withdraw this NFT's share from collection
                    let nft_fa = primary_fungible_store::withdraw(&collection_signer, fa_metadata, nft_share);
                    // Deposit to this NFT's rewards vault
                    deposit_to_rewards_vault(nft_addr, fa_metadata, nft_fa);
                };
            });
        };
    }
}
