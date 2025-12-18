/// CVN-1: Minting Functions
/// 
/// All mint variants for creating vaulted NFTs.
module cvn1_vault::minting {
    use std::string::{Self, String};
    use std::option;
    use std::signer;
    use std::vector;
    
    use cedra_framework::object::Self;
    use cedra_framework::fungible_asset::{Self, Metadata};
    use cedra_framework::primary_fungible_store;
    
    use cedra_token_objects::collection::{Self, Collection};
    use cedra_token_objects::token::{Self, Token};
    
    use cedra_std::math64;
    
    use cvn1_vault::vault_core;
    use cvn1_vault::vault_events;

    /// Public mint function - buyer pays and mints from a creator's collection (v4)
    /// 
    /// Uses collection signer for token creation, enforces max_supply limit.
    public entry fun public_mint(
        buyer: &signer,
        collection_addr: address,
        name: String,
        description: String,
        uri: String,
        is_redeemable: bool
    ) {
        let buyer_addr = signer::address_of(buyer);
        
        assert!(vault_core::config_exists(collection_addr), vault_core::err_config_not_found());
        
        // Check supply limit (v4)
        assert!(vault_core::can_mint(collection_addr), vault_core::err_max_supply_reached());
        
        // Get all config values at once
        let (
            _creator_royalty_bps,
            _vault_royalty_bps,
            mint_vault_bps,
            mint_price,
            mint_price_fa_addr,
            _allowed_assets,
            creator_payout,
            _nft_addresses,
        ) = vault_core::get_config_values(collection_addr);
        
        // Get collection info
        let collection_obj = object::address_to_object<Collection>(collection_addr);
        let _collection_name = collection::name(collection_obj);
        let creator_addr = collection::creator(collection_obj);
        
        // Get collection signer for token creation (v4 fix)
        // The collection owns itself, so collection_signer is the owner
        let collection_signer = vault_core::get_collection_signer(collection_addr);
        
        // Get current minted count for numbering (before increment)
        let (minted_count, _max) = vault_core::get_supply(collection_addr);
        let token_number = minted_count + 1;
        
        // Create token name with number: "Name #1", "Name #2", etc.
        let token_name = name;
        string::append(&mut token_name, string::utf8(b"#"));
        string::append(&mut token_name, u64_to_string(token_number));
        
        // Use create_token_as_collection_owner - validates owner(collection) == signer
        // Since we transferred collection ownership to itself, collection_signer is the owner
        // v6: token royalty is set post-mint to route to escrow
        let constructor_ref = token::create_token_as_collection_owner(
            &collection_signer,
            collection_obj,  // Pass Object<Collection> directly
            description,
            token_name,
            option::none(),
            uri,
        );
        
        let token_signer = object::generate_signer(&constructor_ref);
        let nft_addr = object::address_from_constructor_ref(&constructor_ref);
        vault_core::add_nft_addresses(collection_addr, nft_addr);
        
        // Create refs for vault lifecycle management
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let delete_ref = object::generate_delete_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
        
        // Create and store VaultInfo
        vault_core::create_and_store_vault(
            &token_signer,
            is_redeemable,
            extend_ref,
            option::some(delete_ref),
            burn_ref,
            creator_addr,
        );
        
        // Handle mint payment if price > 0
        if (mint_price > 0 && mint_price_fa_addr != @0x0) {
            let fa_metadata = object::address_to_object<Metadata>(mint_price_fa_addr);
            
            // Calculate split
            let vault_seed = math64::mul_div(mint_price, (mint_vault_bps as u64), vault_core::max_bps());
            let creator_cut = mint_price - vault_seed;
            
            // Withdraw from buyer
            let payment = primary_fungible_store::withdraw(buyer, fa_metadata, mint_price);
            
            // Pay creator
            if (creator_cut > 0) {
                let creator_payment = fungible_asset::extract(&mut payment, creator_cut);
                primary_fungible_store::deposit(creator_payout, creator_payment);
            };
            
            // Seed vault with remainder
            if (vault_seed > 0) {
                vault_core::deposit_to_core_vault(nft_addr, fa_metadata, payment);
            } else {
                fungible_asset::destroy_zero(payment);
            };
        };
        
        // Increment minted count (v4)
        vault_core::increment_minted_count(collection_addr);
        
        // Transfer NFT to buyer (since collection signer created it)
        let token_obj = object::object_from_constructor_ref<Token>(&constructor_ref);
        object::transfer(&collection_signer, token_obj, buyer_addr);
        
        // Emit minted event
        vault_events::emit_minted(nft_addr, collection_addr, creator_addr, buyer_addr, is_redeemable);
    }

    // ============================================
    // Helper Functions
    // ============================================

    /// Convert u64 to String for token numbering
    fun u64_to_string(value: u64): String {
        if (value == 0) {
            return string::utf8(b"0")
        };
        
        let buffer = vector::empty<u8>();
        let n = value;
        while (n > 0) {
            let digit = ((n % 10) as u8) + 48; // ASCII '0' = 48
            vector::push_back(&mut buffer, digit);
            n = n / 10;
        };
        
        // Reverse the buffer
        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }
}
