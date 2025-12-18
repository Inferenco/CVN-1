import { Cedra, CedraConfig, Network } from "@cedra-labs/ts-sdk";

// CVN-1 v6.0 Contract address on testnet
export const CVN1_ADDRESS = "0xe4ff087a33a936e58efeb9601b6b50c4c83872b968e5bf61444326c2c13d115b";

// Initialize Cedra client for testnet
const config = new CedraConfig({ network: Network.TESTNET });
export const cedra = new Cedra(config);

// ============================================
// Types
// ============================================

export interface VaultConfig {
    creatorRoyaltyBps: number;
    vaultRoyaltyBps: number;
    allowedAssets: string[];
    creatorPayoutAddr: string;
    mintVaultBps: number;
    mintPrice: number;
    mintPriceFa: string;
}

export interface VaultBalance {
    faMetadataAddr: string;
    balance: bigint;
}

export interface DualVaultBalances {
    core: VaultBalance[];
    rewards: VaultBalance[];
}

export interface NFT {
    address: string;
    collection: string;
    name: string;
    uri: string;
    hasVault: boolean;
}

// ============================================
// View Functions (gas-free)
// ============================================

export async function vaultExists(nftAddr: string): Promise<boolean> {
    try {
        const result = await cedra.view({
            payload: {
                function: `${CVN1_ADDRESS}::vault_views::vault_exists`,
                typeArguments: [],
                functionArguments: [nftAddr],
            },
        });
        return result[0] as boolean;
    } catch {
        return false;
    }
}

export async function getVaultConfig(collectionAddr: string): Promise<VaultConfig | null> {
    try {
        const resource = await cedra.getAccountResource({
            accountAddress: collectionAddr,
            resourceType: `${CVN1_ADDRESS}::vault_core::VaultedCollectionConfig`
        });
        const data = resource as Record<string, unknown>;
        return {
            creatorRoyaltyBps: Number(data.creator_royalty_bps),
            vaultRoyaltyBps: Number(data.vault_royalty_bps),
            allowedAssets: data.allowed_assets as string[],
            creatorPayoutAddr: data.creator_payout_addr as string,
            mintVaultBps: Number(data.mint_vault_bps),
            mintPrice: Number(data.mint_price),
            mintPriceFa: data.mint_price_fa as string,
        };
    } catch (e) {
        console.warn("Failed to get vault config for", collectionAddr, e);
        return null;
    }
}

// Get COMBINED balances (backward compatibility)
export async function getVaultBalances(nftAddr: string): Promise<VaultBalance[]> {
    try {
        const result = await cedra.view({
            payload: {
                function: `${CVN1_ADDRESS}::vault_views::get_vault_balances`,
                typeArguments: [],
                functionArguments: [nftAddr],
            },
        });

        const balances = result[0] as Array<{ fa_metadata_addr: string; balance: string }>;
        return balances.map(b => ({
            faMetadataAddr: b.fa_metadata_addr,
            balance: BigInt(b.balance),
        }));
    } catch {
        return [];
    }
}

// Get CORE vault balances (long-term, burn-to-redeem)
export async function getCoreVaultBalances(nftAddr: string): Promise<VaultBalance[]> {
    try {
        const result = await cedra.view({
            payload: {
                function: `${CVN1_ADDRESS}::vault_views::get_core_vault_balances`,
                typeArguments: [],
                functionArguments: [nftAddr],
            },
        });

        const balances = result[0] as Array<{ fa_metadata_addr: string; balance: string }>;
        return balances.map(b => ({
            faMetadataAddr: b.fa_metadata_addr,
            balance: BigInt(b.balance),
        }));
    } catch {
        return [];
    }
}

// Get REWARDS vault balances (short-term, claimable anytime)
export async function getRewardsVaultBalances(nftAddr: string): Promise<VaultBalance[]> {
    try {
        const result = await cedra.view({
            payload: {
                function: `${CVN1_ADDRESS}::vault_views::get_rewards_vault_balances`,
                typeArguments: [],
                functionArguments: [nftAddr],
            },
        });

        const balances = result[0] as Array<{ fa_metadata_addr: string; balance: string }>;
        return balances.map(b => ({
            faMetadataAddr: b.fa_metadata_addr,
            balance: BigInt(b.balance),
        }));
    } catch {
        return [];
    }
}

// Get BOTH vaults at once
export async function getDualVaultBalances(nftAddr: string): Promise<DualVaultBalances> {
    const [core, rewards] = await Promise.all([
        getCoreVaultBalances(nftAddr),
        getRewardsVaultBalances(nftAddr),
    ]);
    return { core, rewards };
}

// Get vault info (is_redeemable, creator, compliant)
export async function getVaultInfo(nftAddr: string): Promise<{ isRedeemable: boolean; creator: string; isCompliant: boolean } | null> {
    try {
        const result = await cedra.view({
            payload: {
                function: `${CVN1_ADDRESS}::vault_views::get_vault_info`,
                typeArguments: [],
                functionArguments: [nftAddr],
            },
        });
        return {
            isRedeemable: result[0] as boolean,
            creator: result[1] as string,
            isCompliant: result[2] as boolean,
        };
    } catch {
        return null;
    }
}

// ============================================
// v4: Supply View Functions
// ============================================

export interface CollectionSupply {
    mintedCount: number;
    maxSupply: number;  // 0 = unlimited
}

// Get collection supply info (v4)
export async function getCollectionSupply(collectionAddr: string): Promise<CollectionSupply | null> {
    try {
        const result = await cedra.view({
            payload: {
                function: `${CVN1_ADDRESS}::vault_views::get_collection_supply`,
                typeArguments: [],
                functionArguments: [collectionAddr],
            },
        });
        return {
            mintedCount: Number(result[0]),
            maxSupply: Number(result[1]),
        };
    } catch {
        return null;
    }
}

// Check if collection can still mint (v4)
export async function canMint(collectionAddr: string): Promise<boolean> {
    try {
        const result = await cedra.view({
            payload: {
                function: `${CVN1_ADDRESS}::vault_views::can_mint`,
                typeArguments: [],
                functionArguments: [collectionAddr],
            },
        });
        return result[0] as boolean;
    } catch {
        return false;
    }
}

// ============================================
// Transaction Payload Builders
// ============================================

export function buildInitCollectionPayload(
    name: string,
    description: string,
    uri: string,
    creatorRoyaltyBps: number,
    vaultRoyaltyBps: number,
    mintVaultBps: number,
    mintPrice: bigint,
    mintPriceFa: string,
    allowedAssets: string[],
    creatorPayoutAddr: string,
    maxSupply: number = 0  // v4: 0 = unlimited
) {
    return {
        function: `${CVN1_ADDRESS}::collection::init_collection_config`,
        typeArguments: [],
        functionArguments: [
            name,
            description,
            uri,
            creatorRoyaltyBps,
            vaultRoyaltyBps,
            mintVaultBps,
            mintPrice.toString(),
            mintPriceFa,
            allowedAssets,
            creatorPayoutAddr,
            maxSupply,  // v4
        ],
    };
}

export function buildPublicMintPayload(
    collectionAddr: string,
    name: string,
    description: string,
    uri: string,
    isRedeemable: boolean
) {
    return {
        function: `${CVN1_ADDRESS}::minting::public_mint`,
        typeArguments: [],
        functionArguments: [collectionAddr, name, description, uri, isRedeemable],
    };
}

export function buildDepositToCorePayload(
    nftAddr: string,
    faMetadataAddr: string,
    amount: bigint
) {
    return {
        function: `${CVN1_ADDRESS}::vault_ops::deposit_to_core_vault`,
        typeArguments: [],
        functionArguments: [nftAddr, faMetadataAddr, amount.toString()],
    };
}

export function buildDepositToRewardsPayload(
    nftAddr: string,
    faMetadataAddr: string,
    amount: bigint
) {
    return {
        function: `${CVN1_ADDRESS}::vault_ops::deposit_to_rewards_vault`,
        typeArguments: [],
        functionArguments: [nftAddr, faMetadataAddr, amount.toString()],
    };
}

export function buildClaimRewardsPayload(nftAddr: string) {
    return {
        function: `${CVN1_ADDRESS}::vault_ops::claim_rewards`,
        typeArguments: [],
        functionArguments: [nftAddr],
    };
}

export function buildBurnAndRedeemPayload(nftAddr: string) {
    return {
        function: `${CVN1_ADDRESS}::vault_ops::burn_and_redeem`,
        typeArguments: [],
        functionArguments: [nftAddr],
    };
}

// ============================================
// NFT & Collection Helpers
// ============================================

export async function getWalletNfts(ownerAddr: string): Promise<NFT[]> {
    try {
        const tokens = await cedra.getAccountOwnedTokens({
            accountAddress: ownerAddr,
        });

        const nfts: NFT[] = [];

        // Limit to 20 for performance
        for (const token of tokens.slice(0, 20)) {
            const hasVault = await vaultExists(token.token_data_id);

            nfts.push({
                address: token.token_data_id,
                collection: token.current_token_data?.collection_id ?? "",
                name: token.current_token_data?.token_name ?? "Unknown NFT",
                uri: token.current_token_data?.token_uri ?? "",
                hasVault,
            });
        }

        return nfts;
    } catch (e) {
        console.error("Failed to fetch NFTs:", e);
        return [];
    }
}

export async function getVaultedCollections(): Promise<string[]> {
    try {
        const query = `
            query GetVaultedCollections {
                move_resources(
                    where: { type: { _ilike: "%::vault_core::VaultedCollectionConfig" } }
                    distinct_on: [address]
                    order_by: { address: asc }
                    limit: 50
                ) {
                    address
                }
            }
        `;

        const result = await cedra.queryIndexer({ query: { query } });
        return (result as { move_resources: Array<{ address: string }> }).move_resources.map(r => r.address);
    } catch (e) {
        console.error("Failed to fetch collections from indexer:", e);
        return [];
    }
}

export async function getCollectionDetails(addr: string): Promise<{ name: string; uri: string } | null> {
    try {
        const resource = await cedra.getAccountResource({
            accountAddress: addr,
            resourceType: "0x4::collection::Collection",
        });

        return {
            name: (resource as Record<string, unknown>).name as string,
            uri: (resource as Record<string, unknown>).uri as string,
        };
    } catch {
        return null;
    }
}

export async function getCollectionAddrFromTx(txHash: string): Promise<string | null> {
    try {
        const txn = await cedra.waitForTransaction({ transactionHash: txHash });
        const changes = (txn as Record<string, unknown>).changes as Array<Record<string, unknown>>;

        for (const change of changes) {
            if (change.type === "write_resource") {
                const data = change.data as Record<string, unknown>;

                if (data && data.type &&
                    (data.type as string).includes(`${CVN1_ADDRESS}::vault_core::VaultedCollectionConfig`)) {
                    return change.address as string;
                }
            }
        }
        return null;
    } catch (e) {
        console.error("Failed to parse tx for collection addr:", e);
        return null;
    }
}

// ============================================
// Utilities
// ============================================

export function bpsToPercent(bps: number): number {
    return bps / 100;
}

export function formatAddress(address: string): string {
    if (address.length <= 12) return address;
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatBalance(balance: bigint, decimals: number = 8): string {
    const divisor = BigInt(10 ** decimals);
    const whole = balance / divisor;
    const frac = balance % divisor;
    const fracStr = frac.toString().padStart(decimals, '0').slice(0, 2);
    return `${whole}.${fracStr}`;
}
