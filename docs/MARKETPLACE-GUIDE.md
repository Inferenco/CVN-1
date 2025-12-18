# CVN-1 Marketplace Integration Guide (v6)

> How marketplaces can support CVN-1 vaulted NFTs with framework royalties.

## Overview

CVN-1 v6 uses **Cedra Framework royalties** with a per-NFT escrow payee and a permissionless sweep into the NFT’s Core Vault:

- **Royalties** — Discovered via `cedra_token_objects::royalty`
- **Royalty Escrow** — Token-level royalty payee is a per-NFT escrow address
- **Core Vault Funding** — Anyone can sweep escrow balance into creator payout + NFT Core Vault
- **No Custom Settlement Required** — Standard Cedra NFT sales still work out of the box

## Why Integrate CVN-1?

- **Increased Trade Value** — Vault assets make NFTs more valuable over time
- **Standard Royalties** — Use Cedra's built-in royalty enforcement
- **Community Trust** — Show users you respect creator economics
- **Standard API** — One integration covers all CVN-1 collections

## v6 Changes from v5

| v5 | v6 |
|----|-----|
| Creator-only royalty payee | Per-NFT escrow royalty payee |
| `vault_royalty_bps` ignored | `vault_royalty_bps` funds Core Vault (via sweep) |
| No secondary-sale vault funding | Permissionless sweep to Core Vault |

## Integration Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     MARKETPLACE SETTLEMENT FLOW                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Buyer purchases NFT for 100 CEDRA                           │
│     ↓                                                            │
│  2. Marketplace discovers royalty via framework API              │
│     • Prefer token royalty: royalty::get<Token>(nft)            │
│     ↓                                                            │
│  3. Standard settlement:                                         │
│     • Royalties paid to per-NFT escrow (token payee_address)     │
│     • Seller gets net proceeds                                   │
│     • NFT transfers to buyer                                    │
│     ↓                                                            │
│  4. Optional “instant”: marketplace calls sweep entry function   │
│     • Splits escrowed royalties → creator payout + Core Vault    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Step 1: Detect CVN-1 NFTs

Before listing, check if an NFT has a vault:

```typescript
async function isCVN1NFT(nftAddr: string): Promise<boolean> {
  try {
    const result = await cedra.view({
      payload: {
        function: `${CVN1_ADDRESS}::vault_views::vault_exists`,
        functionArguments: [nftAddr],
      },
    });
    return result[0] as boolean;
  } catch {
    return false;
  }
}
```

## Step 2: Display Vault Info

Show users the vault contents when viewing an NFT:

```typescript
async function getListingInfo(nftAddr: string) {
  // Get separate vault balances
  const coreBalances = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::get_core_vault_balances`,
      functionArguments: [nftAddr],
    },
  });

  const rewardsBalances = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::get_rewards_vault_balances`,
      functionArguments: [nftAddr],
    },
  });

  return {
    coreBalances: coreBalances[0] as { fa_metadata_addr: string; balance: string }[],
    rewardsBalances: rewardsBalances[0] as { fa_metadata_addr: string; balance: string }[],
  };
}
```

## Step 3: Get Token/Collection Royalty

Use Cedra's framework royalty API to discover royalties:

```typescript
import { royalty } from "@cedra-labs/ts-sdk";

async function getTokenRoyalties(nftAddr: string) {
  const royaltyInfo = await cedra.view({
    payload: {
      function: "0x4::royalty::get",
      typeArguments: ["0x4::token::Token"],
      functionArguments: [nftAddr],
    },
  });

  if (royaltyInfo[0]) {
    const { numerator, denominator, payee_address } = royaltyInfo[0];
    return {
      royaltyBps: (Number(numerator) / Number(denominator)) * 10000,
      payeeAddress: payee_address,
    };
  }
  
  return { royaltyBps: 0, payeeAddress: null };
}

// CVN-1 specific config (for vault display)
async function getCVN1Config(collectionAddr: string) {
  const result = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::get_vault_config`,
      functionArguments: [collectionAddr],
    },
  });

  return {
    creatorRoyaltyBps: Number(result[0]),
    vaultRoyaltyBps: Number(result[1]),
    allowedAssets: result[2] as string[],
    creatorPayoutAddr: result[3] as string,
  };
}
```

## Step 4: Execute Sale

Use standard Cedra NFT transfer. The framework handles royalty enforcement:

```typescript
async function completeSale(
  marketplace: Account,
  nftAddr: string,
  sellerAddr: string,
  buyerAddr: string,
  price: bigint
) {
  // Standard transfer - framework enforces royalties
  const txn = await cedra.transaction.build.simple({
    sender: marketplace.accountAddress,
    data: {
      function: "0x1::object::transfer",
      typeArguments: ["0x4::token::Token"],
      functionArguments: [nftAddr, buyerAddr],
    },
  });

  // Handle payment separately (marketplace-specific)
  // Framework royalties are enforced by the Cedra protocol

  const result = await cedra.signAndSubmitTransaction({
    signer: marketplace,
    transaction: txn,
  });

  await cedra.waitForTransaction({ transactionHash: result.hash });

  return { txHash: result.hash };
}
```

> **Note:** The specific royalty enforcement mechanism depends on your marketplace implementation and how Cedra's framework royalties are integrated. Consult Cedra documentation for the latest patterns.

## Step 5 (Optional): Sweep Royalties Into Core Vault (“Instant”)

If you want vault funding to happen immediately after settlement, call the sweep entry:

```typescript
async function sweepRoyaltiesToCoreVault(
  sweeper: Account,
  nftAddr: string,
  faMetadataAddr: string,
) {
  const txn = await cedra.transaction.build.simple({
    sender: sweeper.accountAddress,
    data: {
      function: `${CVN1_ADDRESS}::vault_ops::sweep_royalty_to_core_vault`,
      typeArguments: [],
      functionArguments: [nftAddr, faMetadataAddr],
    },
  });

  const result = await cedra.signAndSubmitTransaction({
    signer: sweeper,
    transaction: txn,
  });
  await cedra.waitForTransaction({ transactionHash: result.hash });
}
```

If you don’t call this, a permissionless sweeper (like `royalty_sweeper/`) can do it near-real-time.

## Step 6: Display Vault Value

Show vault contents as additional NFT value:

```typescript
async function getTotalVaultValue(nftAddr: string): Promise<string> {
  const coreResult = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::get_core_vault_balances`,
      functionArguments: [nftAddr],
    },
  });
  
  const rewardsResult = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::get_rewards_vault_balances`,
      functionArguments: [nftAddr],
    },
  });

  const coreBalances = coreResult[0] as { balance: string }[];
  const rewardsBalances = rewardsResult[0] as { balance: string }[];
  
  let totalOctas = 0n;
  for (const b of [...coreBalances, ...rewardsBalances]) {
    totalOctas += BigInt(b.balance);
  }
  
  return `${Number(totalOctas) / 1e8} CEDRA`;
}
```

## UI Recommendations

### Listing Page

```
┌────────────────────────────────────────┐
│  [NFT Image]                           │
│                                        │
│  Vaulted NFT #42                       │
│  Collection: Premium Art               │
│                                        │
│  Price: 100 CEDRA                      │
│                                        │
│  ┌──────────────────────────────────┐ │
│  │ 💎 Vault Contents                 │ │
│  │ 🔒 Core:    15.5 CEDRA           │ │
│  │ 🎁 Rewards:  5.0 CEDRA           │ │
│  │ Floor Value: ~$20.50              │ │
│  └──────────────────────────────────┘ │
│                                        │
│  Creator Royalty: 5%                   │
│                                        │
│  [Buy Now]                             │
│                                        │
│  ✓ Framework Royalties Enforced       │
└────────────────────────────────────────┘
```

### Vault Badges

```
🔒 Core Vault   — Burn-to-redeem only (floor value)
🎁 Rewards      — Claim anytime by owner
```

## Error Handling

| Error | Code | Action |
|-------|------|--------|
| `EVAULT_NOT_FOUND` | 8 | Not a CVN-1 NFT, no vault display needed |
| `ECONFIG_NOT_FOUND` | 10 | Collection config missing |

## Updated Checklist for v6

- [ ] Detect CVN-1 NFTs via `vault_exists`
- [ ] Display dual vault balances on listings
- [ ] Show creator + Core Vault royalty bps (via `get_vault_config`)
- [ ] Use standard transfer + framework royalties (pay to token `payee_address`)
- [ ] Optionally call `sweep_royalty_to_core_vault` post-settlement for “instant”
- [ ] Display total vault value as floor price indicator
- [ ] Handle non-CVN-1 NFTs gracefully

## Legacy Notes

- `settle_sale_with_vault_royalty` remains removed; v6 uses framework royalties + sweep instead.

## Support

For integration support, contact the CVN-1 team or open an issue on the repository.
