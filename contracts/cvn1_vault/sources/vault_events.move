/// CVN-1: Event Definitions
/// 
/// All events emitted by the CVN-1 standard for indexer consumption.
module cvn1_vault::vault_events {
    use cedra_framework::event;

    // ============================================
    // Event Structures
    // ============================================

    #[event]
    struct VaultedNFTMinted has drop, store {
        nft_object_addr: address,
        collection_addr: address,
        creator: address,
        recipient: address,
        is_redeemable: bool,
    }

    #[event]
    struct VaultDeposited has drop, store {
        nft_object_addr: address,
        fa_type: address,
        amount: u64,
        depositor: address,
    }

    #[event]
    struct VaultRedeemed has drop, store {
        nft_object_addr: address,
        redeemer: address,
        assets_redeemed: vector<address>,
    }

    #[event]
    struct RoyaltySettled has drop, store {
        nft_object_addr: address,
        sale_currency: address,
        gross_amount: u64,
        creator_cut: u64,
        vault_cut: u64,
        seller_net: u64,
    }

    #[event]
    struct RoyaltySweptToCore has drop, store {
        nft_object_addr: address,
        fa_type: address,
        gross_amount: u64,
        creator_cut: u64,
        core_vault_cut: u64,
        escrow_addr: address,
        sweeper: address,
    }

    #[event]
    struct RewardsClaimed has drop, store {
        nft_object_addr: address,
        claimer: address,
        assets_claimed: vector<address>,
    }

    // ============================================
    // Emit Functions
    // ============================================

    /// Emit a VaultedNFTMinted event
    public fun emit_minted(
        nft_object_addr: address,
        collection_addr: address,
        creator: address,
        recipient: address,
        is_redeemable: bool,
    ) {
        event::emit(VaultedNFTMinted {
            nft_object_addr,
            collection_addr,
            creator,
            recipient,
            is_redeemable,
        });
    }

    /// Emit a VaultDeposited event
    public fun emit_deposited(
        nft_object_addr: address,
        fa_type: address,
        amount: u64,
        depositor: address,
    ) {
        event::emit(VaultDeposited {
            nft_object_addr,
            fa_type,
            amount,
            depositor,
        });
    }

    /// Emit a VaultRedeemed event
    public fun emit_redeemed(
        nft_object_addr: address,
        redeemer: address,
        assets_redeemed: vector<address>,
    ) {
        event::emit(VaultRedeemed {
            nft_object_addr,
            redeemer,
            assets_redeemed,
        });
    }

    /// Emit a RoyaltySettled event
    public fun emit_royalty_settled(
        nft_object_addr: address,
        sale_currency: address,
        gross_amount: u64,
        creator_cut: u64,
        vault_cut: u64,
        seller_net: u64,
    ) {
        event::emit(RoyaltySettled {
            nft_object_addr,
            sale_currency,
            gross_amount,
            creator_cut,
            vault_cut,
            seller_net,
        });
    }

    /// Emit a RoyaltySweptToCore event
    public fun emit_royalty_swept(
        nft_object_addr: address,
        fa_type: address,
        gross_amount: u64,
        creator_cut: u64,
        core_vault_cut: u64,
        escrow_addr: address,
        sweeper: address,
    ) {
        event::emit(RoyaltySweptToCore {
            nft_object_addr,
            fa_type,
            gross_amount,
            creator_cut,
            core_vault_cut,
            escrow_addr,
            sweeper,
        });
    }

    /// Emit a RewardsClaimed event
    public fun emit_rewards_claimed(
        nft_object_addr: address,
        claimer: address,
        assets_claimed: vector<address>,
    ) {
        event::emit(RewardsClaimed {
            nft_object_addr,
            claimer,
            assets_claimed,
        });
    }
}
