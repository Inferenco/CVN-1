# CVN-1 Use Cases & Deployment Strategies

> Creative ways to deploy vaulted NFTs with built-in value

This document explores the various ways creators can leverage the CVN-1 standard to create NFTs with real, on-chain value.

---

## Configuration Options Recap (v6)

| Parameter | Range | Description |
|-----------|-------|-------------|
| `mint_vault_bps` | 0-10000 | % of mint price seeded into Core Vault |
| `mint_price` | 0+ | Cost to mint (in smallest FA units) |
| `creator_royalty_bps` | 0-10000 | % of secondary sales to creator (framework-enforced) |
| `vault_royalty_bps` | 0-10000 | % of secondary-sale royalties routed into the NFT Core Vault (via sweep) |
| `allowed_assets` | addresses | Whitelist of depositable tokens |
| `max_supply` | 0+ | Maximum mintable (0 = unlimited) |

> **v6 Note:** Secondary-sale royalties are paid to a per-NFT escrow (framework royalty payee), then permissionlessly swept into creator payout + the NFT’s Core Vault.

---

## 🎨 Strategy 1: Premium Art with Built-In Value

**Use Case:** High-end 1/1 artwork where the NFT itself holds significant value from day one.

```
mint_price:        1000 USDC
mint_vault_bps:    10000 (100%)
creator_royalty:   500 (5%)
```

**What happens:**
- Collector pays 1000 USDC to mint
- **100% (1000 USDC) goes directly into the NFT's Core Vault**
- Creator earns on secondary sales (5% via framework royalties)
- Vault can grow via direct deposits or integrations

**Why it works:**
- The NFT has provable floor value equal to mint price
- Collectors know they can always redeem for at least what's in vault
- Perfect for digital art, music rights, or luxury digital goods

---

## 🚀 Strategy 2: PFP Collection with Savings Accounts

**Use Case:** 10K generative collection where every NFT builds value over time.

```
mint_price:        50 CEDRA
mint_vault_bps:    5000 (50%)
creator_royalty:   250 (2.5%)
```

**What happens:**
- Each mint: 25 CEDRA → Core Vault, 25 CEDRA → creator
- Holders can deposit more to grow vault value
- Games/dApps can deposit rewards to Rewards Vault

**Why it works:**
- Creates "savings account" energy for holders
- Incentivizes diamond hands (vault grows via engagement)
- Community can see collective vault value

---

## 🎮 Strategy 3: Gaming Items with Real Value

**Use Case:** In-game items that can be "broken down" for materials.

```
mint_price:        100 GOLD_TOKEN
mint_vault_bps:    8000 (80%)
allowed_assets:    [GOLD_TOKEN, SILVER_TOKEN, GEM_TOKEN]
is_redeemable:     true
```

**What happens:**
- Sword minted with 80 GOLD_TOKEN in Core Vault
- Game can deposit rewards to Rewards Vault
- Player can "salvage" sword to retrieve all gold
- Only game currencies can be deposited

**Why it works:**
- Creates real in-game economy with material value
- Salvage mechanic enables crafting systems
- Prevents spam by limiting depositable assets

---

## 💎 Strategy 4: Charity NFTs with Transparent Donations

**Use Case:** NFTs where all proceeds go to a verified cause.

```
mint_price:        25 USDC
mint_vault_bps:    10000 (100%)
creator_royalty:   0 (0%)
vault_royalty:     0 (0%)
creator_payout:    @charity_wallet
is_redeemable:     false
```

**What happens:**
- 100% of mint goes into vault (not to charity yet)
- Charity calls `burn_and_redeem` at end of campaign
- All accumulated funds go to charity
- Wait... `is_redeemable: false` means it can't be burned!

**Better approach:**
```
mint_vault_bps:    0 (0%)
creator_payout:    @charity_wallet
```
All mint fees go directly to charity. NFT is commemorative only.

---

## 📈 Strategy 5: Investment Vehicles (DeFi NFTs)

**Use Case:** NFTs that represent a basket of tokens, like a mini-index fund.

```
mint_price:        0 (free mint)
vault_royalty:     0
allowed_assets:    [CEDRA, USDC, BTC, ETH]
```

**What happens:**
- Creator mints empty vault NFT
- Creator deposits $1000 of diversified tokens
- Sells NFT as "DeFi Basket #1"
- Buyer gets the NFT + all tokens inside
- Anyone can add to the basket at any time

**Why it works:**
- NFT becomes a transferable portfolio
- Anyone can contribute (community building)
- Single burn to claim all assets

---

## 🎵 Strategy 6: Music Royalty Shares

**Use Case:** Artists fund albums through NFTs that receive streaming royalties.

```
mint_price:        100 USDC
mint_vault_bps:    0
vault_royalty:     0
allowed_assets:    [USDC, ROYALTY_TOKEN]
```

**What happens:**
- Artist sells 100 "share" NFTs at 100 USDC each → $10K funding
- Artist uses funds to produce album
- Monthly streaming royalties deposited to each NFT's vault
- Holders burn to claim accumulated royalties

**Why it works:**
- Fans become investors
- Transparent, on-chain royalty distribution
- NFT proves ownership of revenue share

---

## 🏦 Strategy 7: The "Piggy Bank" Collection

**Use Case:** NFTs designed purely as savings vehicles.

```
mint_price:        0 (free)
mint_vault_bps:    N/A
creator_royalty:   0
vault_royalty:     0
allowed_assets:    [] (any token)
is_redeemable:     true
```

**What happens:**
- Free mint, empty vault
- Owner deposits any tokens over time
- Can burn anytime to withdraw everything
- Essentially a transferable savings account

**Why it works:**
- Gift piggy banks to friends/family
- Transfer savings by transferring NFT
- Visual savings tracker (if UI shows vault balance)

---

## 🎁 Strategy 8: Gift Cards / Vouchers

**Use Case:** Redeemable gift cards for specific tokens.

```
mint_price:        50 STORE_TOKEN
mint_vault_bps:    10000 (100%)
allowed_assets:    [STORE_TOKEN]
is_redeemable:     true
```

**What happens:**
- Purchaser pays 50 STORE_TOKEN
- NFT contains exactly 50 STORE_TOKEN
- Recipient burns NFT to get the tokens
- Works like a transferable gift card

**Why it works:**
- Tokens are locked until redeemed
- Gift-able and tradeable
- Can include artwork/branding

---

## 🔒 Strategy 9: Locked Savings (Non-Redeemable)

**Use Case:** Tokens that must be held forever (burn mechanism for deflationary economics).

```
mint_price:        100 TOKEN
mint_vault_bps:    10000 (100%)
is_redeemable:     false
```

**What happens:**
- 100 TOKEN locked in vault permanently
- NFT can be traded but never redeemed
- Tokens effectively burned but verifiably exist

**Why it works:**
- Deflationary without actual burning
- Creates "treasure" NFTs with known value
- Speculation on whether standard might change

---

## 🏆 Strategy 10: Competitive Staking

**Use Case:** NFTs that compete based on vault size.

```
allowed_assets:    [GAME_TOKEN]
is_redeemable:     true
```

**What happens:**
- Players mint warrior NFTs
- Deposit GAME_TOKEN to "power up"
- Leaderboard tracks highest vault balances
- Top vaults win tournament prizes
- Game deposits rewards to top performers

**Why it works:**
- Gamified savings
- Social competition
- Self-reinforcing value

---

## Configuration Matrix (v6)

| Use Case | mint_vault_bps | creator_royalty | is_redeemable | allowed_assets |
|----------|----------------|-----------------|---------------|----------------|
| Premium Art | 100% | 5% | ✅ | Any |
| PFP Collection | 50% | 2.5% | ✅ | Any |
| Game Items | 80% | 0% | ✅ | Game tokens |
| Charity | 0% | 0% | ❌ | N/A |
| DeFi Basket | 0% | 0% | ✅ | Specified |
| Music Shares | 0% | 0% | ✅ | USDC |
| Piggy Bank | N/A | 0% | ✅ | Any |
| Gift Card | 100% | 0% | ✅ | Store token |
| Locked Savings | 100% | 0% | ❌ | Any |
| Competitive | 0% | 0% | ✅ | Game token |

---

## Best Practices

### 1. **Set Clear Expectations**
Document exactly what happens at mint:
- How much goes to vault vs creator
- Whether it's redeemable
- What assets are allowed

### 2. **Consider Gas Costs**
- Each FA type in vault = extra storage
- Limiting `allowed_assets` reduces complexity
- Batch deposits when possible

### 3. **Think About Redemption**
- `is_redeemable: false` is permanent
- Useful for locked value but limits utility
- Most use cases want redemption

### 4. **Vault Funding Strategy**
- Mint seeding provides initial floor value
- Integrate with games/dApps for ongoing deposits
- Consider staking or reward mechanisms

### 5. **Asset Allowlists**
- Empty = any FA allowed (spam risk)
- Specific = controlled (user-friendly)
- Consider what FA types make sense

---

## Example: Complete Collection Setup (v6)

```move
init_collection_config(
    creator,
    "Vaulted Dragons",                   // name
    "Dragons with treasure hoards",      // description
    "https://dragons.io/collection",     // uri
    500,                                 // 5% creator royalty (framework-enforced)
    0,                                   // 0% core vault royalty (optional in v6)
    5000,                                // 50% of mint → Core Vault
    100_000_000,                         // 100 CEDRA mint price
    @cedra_fa_address,                   // pay in CEDRA
    vector[@cedra, @usdc, @gold],        // only these in vault
    @treasury_wallet,                    // creator payments
    10000                                // max supply (v4+)
);
```

Result:
- Mint costs 100 CEDRA
- 50 CEDRA seeds the dragon's Core Vault
- 50 CEDRA goes to creator
- Secondary sales: 5% to creator (framework-enforced)
- Holders can burn to claim treasure

---

## What's Next?

- **Indexed Vault Values**: Off-chain service to track total vault values
- **Vault Leaderboards**: Show richest NFTs in collection
- **Conditional Redemption**: Time-locks or milestones before burn
- **Vault-Weighted Governance**: Voting power based on vault balance

---

*Built with CVN-1: The Cedra Vaulted NFT Standard*
