Readiness Assessment: CVN-1 PFP Launch

What’s already implemented
- Collection creation + config (mint price, royalty splits, max supply, allowlisted deposit assets) in contracts/cvn1_vault/sources/collection.move and contracts/cvn1_vault/sources/vault_core.move.
- Public mint flow with vault seeding + supply tracking in contracts/cvn1_vault/sources/minting.move.
- Vault mechanics (deposit, claim rewards, burn+redeem) in contracts/cvn1_vault/sources/vault_ops.move.
- Views + events for indexers in contracts/cvn1_vault/sources/vault_views.move and contracts/cvn1_vault/sources/vault_events.move.

Gaps to reach “full launch” readiness
- Whitelist / sale phases: No allowlist for minting, no presale vs public toggles, no start/end times. Add Merkle root or on-chain allowlist + per-wallet caps + phase gates in minting.move.
- Per-wallet / per-tx limits: No per-wallet mint count or max-per-tx enforcement. Typical PFP drops need this to prevent whales.
- Pause / emergency stop: No pause flag to halt minting during incidents. Add a mint_active bool or pause entry guard.
- Admin update hooks: After init there’s no way to update mint price, mint currency, payout address, allowed assets, max supply, etc. Add admin-only setters in vault_core.move/collection.move.
- Mint metadata control: public_mint takes name/description/uri from the buyer. For a PFP, you usually want fixed metadata (base URI + token id) controlled by the creator. Add base URI, placeholder URI, reveal flag, and auto-computed token names/IDs.
- Reveal + provenance: No provenance hash, reveal time, or randomness source. Add provenance hash storage + a reveal switch, or VRF-style randomness.
- Collection supply at framework level: You always create an unlimited collection (create_unlimited_collection). Max supply is only enforced in your config. Some marketplaces will show “unlimited” unless you create a fixed supply collection.
- Royalties escrow logic is missing: Comments mention per-token escrow, but there’s no escrow module or token-level royalty setting. distribute_royalties currently iterates all NFTs and splits a batch payout; this won’t scale to 5k/10k collections (O(n) gas explosion). You likely need per-token escrow or a cumulative reward index.
- Royalty ingestion: Nothing actually routes secondary sale royalties into the collection address automatically. You’ll need a marketplace integration or an on-chain “sweeper” workflow to call distribute_royalties.
- Mint payment sanity checks: If mint_price > 0 and mint_price_fa_addr == @0x0, public_mint silently mints free. Add an assert in init + mint.
- Team reserve / airdrop: No admin mint / reserve allocation path for giveaways, treasury, or founders.
- Metadata freeze: No irreversible “freeze” once reveal is done (typical for PFP trust).

Operational + off-chain launch items to plan
- Front-end minting app, wallet UX, allowlist management UI.
- Metadata hosting (IPFS/Arweave) + reveal pipeline.
- Indexer + analytics (events are there, but you’ll need off-chain infra).
- Deployment scripts + multi-sig ownership for admin functions.
- Marketplace listing checklist and royalty settings verification.
