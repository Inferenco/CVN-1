# CVN-1 TypeScript Integration Guide (v6)

> Examples using `@cedra-labs/ts-sdk` to interact with CVN-1 dual vault NFTs.

## Setup

```typescript
import { Cedra, CedraConfig, Account, Network } from "@cedra-labs/ts-sdk";

const config = new CedraConfig({ network: Network.TESTNET });
const cedra = new Cedra(config);

const CVN1_ADDRESS = "0x..."; // Your deployed CVN-1 address

// Full-length CEDRA FA metadata address
const CEDRA_FA = "0x000000000000000000000000000000000000000000000000000000000000000a";
```

## Creating a Collection (v6)

```typescript
async function createCollection(creator: Account) {
  const txn = await cedra.transaction.build.simple({
    sender: creator.accountAddress,
    data: {
      function: `${CVN1_ADDRESS}::collection::init_collection_config`,
      functionArguments: [
        "My Vaulted Collection",
        "A collection with dual vaults",
        "https://example.com/meta",
        500,   // creator_royalty_bps (5%)
        500,   // vault_royalty_bps (5% routed into NFT core vault via sweep)
        5000,  // mint_vault_bps (50% → core vault)
        1000000, // mint_price in octas
        CEDRA_FA,
        [],    // allowed_assets (empty = all allowed)
        creator.accountAddress.toString(), // creator_payout_addr
        0,     // max_supply (0 = unlimited)
      ],
    },
  });

  const result = await cedra.signAndSubmitTransaction({ signer: creator, transaction: txn });
  await cedra.waitForTransaction({ transactionHash: result.hash });
  
  const collectionAddr = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::collection::get_collection_address`,
      functionArguments: [creator.accountAddress.toString(), "My Vaulted Collection"],
    },
  });
  
  return collectionAddr[0];
}
```

## Minting (Seeds Core Vault)

```typescript
async function publicMint(buyer: Account, collectionAddr: string) {
  // mint_vault_bps % of mint price goes to CORE vault
  // v6: mint creates a per-NFT royalty escrow and sets token-level royalty payee to that escrow
  const txn = await cedra.transaction.build.simple({
    sender: buyer.accountAddress,
    data: {
      function: `${CVN1_ADDRESS}::minting::public_mint`,
      functionArguments: [
        collectionAddr,
        "NFT #1",
        "Vaulted NFT",
        "https://example.com/nft/1",
        true, // is_core_redeemable
      ],
    },
  });

  const result = await cedra.signAndSubmitTransaction({ signer: buyer, transaction: txn });
  return result.hash;
}
```

## Royalty Sweep (v6)

Royalties are paid to the NFT’s escrow address (token-level framework royalty payee). Anyone can sweep those funds into creator payout + Core Vault:

```typescript
async function sweepRoyaltiesToCoreVault(sweeper: Account, nftAddr: string, faMetadataAddr: string) {
  const txn = await cedra.transaction.build.simple({
    sender: sweeper.accountAddress,
    data: {
      function: `${CVN1_ADDRESS}::vault_ops::sweep_royalty_to_core_vault`,
      functionArguments: [nftAddr, faMetadataAddr],
    },
  });

  const result = await cedra.signAndSubmitTransaction({ signer: sweeper, transaction: txn });
  return result.hash;
}
```

## Vault Operations

### Deposit to Core Vault (Long-term)

```typescript
async function depositToCore(depositor: Account, nftAddr: string, amount: bigint) {
  const txn = await cedra.transaction.build.simple({
    sender: depositor.accountAddress,
    data: {
      function: `${CVN1_ADDRESS}::vault_ops::deposit_to_core_vault`,
      functionArguments: [nftAddr, CEDRA_FA, amount.toString()],
    },
  });

  const result = await cedra.signAndSubmitTransaction({ signer: depositor, transaction: txn });
  return result.hash;
}
```

### Deposit to Rewards Vault (Short-term)

```typescript
async function depositToRewards(depositor: Account, nftAddr: string, amount: bigint) {
  const txn = await cedra.transaction.build.simple({
    sender: depositor.accountAddress,
    data: {
      function: `${CVN1_ADDRESS}::vault_ops::deposit_to_rewards_vault`,
      functionArguments: [nftAddr, CEDRA_FA, amount.toString()],
    },
  });

  const result = await cedra.signAndSubmitTransaction({ signer: depositor, transaction: txn });
  return result.hash;
}
```

### Claim Rewards (Keep NFT)

```typescript
async function claimRewards(owner: Account, nftAddr: string) {
  const txn = await cedra.transaction.build.simple({
    sender: owner.accountAddress,
    data: {
      function: `${CVN1_ADDRESS}::vault_ops::claim_rewards`,
      functionArguments: [nftAddr],
    },
  });

  const result = await cedra.signAndSubmitTransaction({ signer: owner, transaction: txn });
  return result.hash;
}
```

### Burn and Redeem (Both Vaults)

```typescript
async function burnAndRedeem(owner: Account, nftAddr: string) {
  // Burns NFT and claims BOTH core + rewards vaults
  const txn = await cedra.transaction.build.simple({
    sender: owner.accountAddress,
    data: {
      function: `${CVN1_ADDRESS}::vault_ops::burn_and_redeem`,
      functionArguments: [nftAddr],
    },
  });

  const result = await cedra.signAndSubmitTransaction({ signer: owner, transaction: txn });
  return result.hash;
}
```

## View Functions

### Get Core Vault Balances

```typescript
async function getCoreBalances(nftAddr: string) {
  const result = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::get_core_vault_balances`,
      functionArguments: [nftAddr],
    },
  });
  return result[0] as { fa_metadata_addr: string; balance: string }[];
}
```

### Get Rewards Vault Balances

```typescript
async function getRewardsBalances(nftAddr: string) {
  const result = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::get_rewards_vault_balances`,
      functionArguments: [nftAddr],
    },
  });
  return result[0] as { fa_metadata_addr: string; balance: string }[];
}
```

### Get Combined Balances

```typescript
async function getTotalBalances(nftAddr: string) {
  const result = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::get_vault_balances`,
      functionArguments: [nftAddr],
    },
  });
  return result[0] as { fa_metadata_addr: string; balance: string }[];
}
```

### Check If Vault Exists

```typescript
async function vaultExists(nftAddr: string): Promise<boolean> {
  const result = await cedra.view({
    payload: {
      function: `${CVN1_ADDRESS}::vault_views::vault_exists`,
      functionArguments: [nftAddr],
    },
  });
  return result[0] as boolean;
}
```

## Royalties (v6)

In v6, royalties are handled by the **Cedra Framework** (discovery + enforcement), with a per-NFT escrow payee. The `payee_address` returned for a token is the escrow address.

```typescript
async function getFrameworkRoyalty(tokenOrCollectionAddr: string) {
  const result = await cedra.view({
    payload: {
      function: "0x4::royalty::get",
      typeArguments: ["0x4::token::Token"],
      functionArguments: [tokenOrCollectionAddr],
    },
  });
  
  if (result[0]) {
    const royalty = result[0] as { numerator: string; denominator: string; payee_address: string };
    return {
      percentage: (Number(royalty.numerator) / Number(royalty.denominator)) * 100,
      payee: royalty.payee_address,
    };
  }
  return null;
}
```

> **Note:** Custom `settle_sale_with_vault_royalty` was removed in v5 and remains removed. Use standard marketplace settlement with framework royalty enforcement + sweep.

## Summary

| Action | Function | Vault |
|--------|----------|-------|
| Mint | `public_mint` | Core |
| Deposit long-term | `deposit_to_core_vault` | Core |
| Deposit short-term | `deposit_to_rewards_vault` | Rewards |
| Sweep royalties | `sweep_royalty_to_core_vault` | Core |
| Claim rewards | `claim_rewards` | Rewards |
| Burn & redeem | `burn_and_redeem` | Both |

## Notes

- `vault_royalty_bps` is used in v6 to route a share of secondary-sale royalties into the NFT’s Core Vault (via sweep).
- `settle_sale_with_vault_royalty` remains removed; use framework royalties + sweep instead.
