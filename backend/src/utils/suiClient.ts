// Load environment variables first
import dotenv from 'dotenv';
dotenv.config();

// Updated imports for @mysten/sui v1.x
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { fromHex, fromBase64 } from '@mysten/sui/utils';

// Simple logger fallback
const logger = {
  info: (...args: any[]) => console.log('[INFO]', ...args),
  error: (...args: any[]) => console.error('[ERROR]', ...args),
  warn: (...args: any[]) => console.warn('[WARN]', ...args),
  debug: (...args: any[]) => console.debug('[DEBUG]', ...args),
};

/**
 * Sui Client wrapper for blockchain interactions
 */
export class SuiClientWrapper {
  private client: SuiClient;
  private keypair: Ed25519Keypair | null = null;
  private packageId: string;

  constructor() {
    const networkEnv = process.env.SUI_NETWORK || 'testnet';
    const network = networkEnv as 'testnet' | 'mainnet' | 'devnet' | 'localnet';
    this.client = new SuiClient({ url: getFullnodeUrl(network) });
    this.packageId = process.env.TREASURY_PACKAGE_ID || '';

    // Initialize keypair if private key provided
    if (process.env.SUI_PRIVATE_KEY) {
      try {
        const privateKey = process.env.SUI_PRIVATE_KEY;
        
        // Handle different private key formats
        if (privateKey.startsWith('0x')) {
          // Hex format
          const privateKeyBytes = fromHex(privateKey);
          this.keypair = Ed25519Keypair.fromSecretKey(privateKeyBytes);
        } else {
          // Base64 format (default from Sui keystore)
          // The keystore format includes a flag byte (33 bytes total)
          // We need to strip the first byte to get the 32-byte private key
          let privateKeyBytes = fromBase64(privateKey);
          
          if (privateKeyBytes.length === 33) {
            // Strip the first byte (scheme flag) to get the 32-byte secret key
            privateKeyBytes = privateKeyBytes.slice(1);
          }
          
          this.keypair = Ed25519Keypair.fromSecretKey(privateKeyBytes);
        }
        
        const address = this.keypair.getPublicKey().toSuiAddress();
        logger.info('✅ Sui keypair initialized');
        logger.info('📍 Signer address:', address);
      } catch (error) {
        logger.error('❌ Failed to initialize keypair:', error);
        logger.error('Error details:', error);
      }
    } else {
      logger.warn('⚠️ No SUI_PRIVATE_KEY provided - treasury creation will not work');
    }

    logger.info(`🔗 Connected to Sui ${network}`);
  }

  /**
   * Get Sui client instance
   */
  getClient(): SuiClient {
    return this.client;
  }

  /**
   * Get package ID
   */
  getPackageId(): string {
    return this.packageId;
  }

  /**
   * Get signer address
   */
  getSignerAddress(): string {
    if (!this.keypair) {
      throw new Error('Keypair not initialized');
    }
    return this.keypair.getPublicKey().toSuiAddress();
  }

  /**
   * Create treasury on-chain
   */
  async createTreasury(
    signers: string[],
    threshold: number,
    emergencySigners: string[],
    emergencyThreshold: number
  ): Promise<any> {
    if (!this.keypair) {
      throw new Error('Keypair not initialized');
    }

    // Get signer address
    const signerAddress = this.keypair.getPublicKey().toSuiAddress();
    logger.info(`Creating treasury with signer: ${signerAddress}`);
    
    // Get gas coins for the signer
    const gasCoins = await this.client.getCoins({
      owner: signerAddress,
      coinType: '0x2::sui::SUI',
    });

    if (!gasCoins.data || gasCoins.data.length === 0) {
      throw new Error(`No SUI coins found for address ${signerAddress}`);
    }

    logger.info(`Found ${gasCoins.data.length} gas coins, using: ${gasCoins.data[0].coinObjectId}`);

    const tx = new Transaction();
    
    // Set gas budget and payment
    tx.setGasBudget(100000000); // 0.1 SUI
    tx.setGasPayment([{
      objectId: gasCoins.data[0].coinObjectId,
      version: gasCoins.data[0].version,
      digest: gasCoins.data[0].digest,
    }]);

    // Get clock object
    const clock = '0x6';

    tx.moveCall({
      target: `${this.packageId}::treasury::create_treasury`,
      arguments: [
        tx.pure.vector('address', signers),
        tx.pure.u8(threshold),
        tx.pure.vector('address', emergencySigners),
        tx.pure.u8(emergencyThreshold),
        tx.object(clock),
      ],
    });

    try {
      const result = await this.client.signAndExecuteTransaction({
        signer: this.keypair,
        transaction: tx,
        options: {
          showEffects: true,
          showObjectChanges: true,
          showEvents: true,
        },
      });

      logger.info(`✅ Treasury created: ${result.digest}`);
      return result;
    } catch (error) {
      logger.error('❌ Failed to create treasury:', error);
      throw error;
    }
  }

  /**
   * Deposit funds into treasury
   */
  async depositToTreasury(
    treasuryId: string,
    coinId: string,
    coinType: string
  ): Promise<any> {
    if (!this.keypair) {
      throw new Error('Keypair not initialized');
    }

    const tx = new Transaction();

    tx.moveCall({
      target: `${this.packageId}::treasury::deposit`,
      typeArguments: [coinType],
      arguments: [
        tx.object(treasuryId),
        tx.object(coinId),
      ],
    });

    const result = await this.client.signAndExecuteTransaction({
      signer: this.keypair,
      transaction: tx,
      options: {
        showEffects: true,
        showEvents: true,
      },
    });

    logger.info(`Deposit completed: ${result.digest}`);
    return result;
  }

  /**
   * Create proposal on-chain
   */
  async createProposal(
    treasuryAdminCapId: string,
    transactions: Array<{ recipient: string; amount: string; coinType: string }>,
    metadata: string,
    category: number,
    timeLockDuration: number
  ): Promise<any> {
    if (!this.keypair) {
      throw new Error('Keypair not initialized');
    }

    // First, get the actual Treasury object ID from TreasuryAdminCap
    const adminCapObj = await this.client.getObject({
      id: treasuryAdminCapId,
      options: { showContent: true },
    });

    if (!adminCapObj.data || !adminCapObj.data.content || adminCapObj.data.content.dataType !== 'moveObject') {
      throw new Error('Invalid TreasuryAdminCap object');
    }

    const fields = adminCapObj.data.content.fields as any;
    const actualTreasuryId = fields.treasury_id;

    if (!actualTreasuryId) {
      throw new Error('Treasury ID not found in TreasuryAdminCap');
    }

    logger.info(`Creating proposal for Treasury: ${actualTreasuryId}`);

    const tx = new Transaction();
    const clock = '0x6';

    // Build Transaction structs using create_transaction helper
    const txObjects = [];
    for (const t of transactions) {
      // Handle both coinType and coin_type from frontend
      const coinType = (t as any).coinType || (t as any).coin_type;
      
      if (!coinType) {
        throw new Error('Transaction missing coin_type field');
      }
      
      const txObj = tx.moveCall({
        target: `${this.packageId}::proposal::create_transaction`,
        arguments: [
          tx.pure.address(t.recipient),
          tx.pure.u64(t.amount),
          tx.pure.vector('u8', Array.from(Buffer.from(coinType))),
        ],
      });
      txObjects.push(txObj);
    }

    // Create proposal with the transaction vector
    tx.moveCall({
      target: `${this.packageId}::proposal::create_proposal`,
      arguments: [
        tx.object(actualTreasuryId),
        tx.makeMoveVec({ 
          type: `${this.packageId}::proposal::Transaction`,
          elements: txObjects 
        }),
        tx.pure.vector('u8', Array.from(Buffer.from(metadata))),
        tx.pure.u8(category),
        tx.pure.u64(timeLockDuration),
        tx.object(clock),
      ],
    });

    const result = await this.client.signAndExecuteTransaction({
      signer: this.keypair,
      transaction: tx,
      options: {
        showEffects: true,
        showObjectChanges: true,
        showEvents: true,
      },
    });

    logger.info(`Proposal created: ${result.digest}`);
    return result;
  }

  /**
   * Sign proposal on-chain
   */
  async signProposal(
    proposalId: string,
    treasuryId: string,
    signature: string
  ): Promise<any> {
    if (!this.keypair) {
      throw new Error('Keypair not initialized');
    }

    const tx = new Transaction();
    const clock = '0x6';

    tx.moveCall({
      target: `${this.packageId}::proposal::sign_proposal`,
      arguments: [
        tx.object(proposalId),
        tx.object(treasuryId),
        tx.pure.vector('u8', Array.from(fromHex(signature))),
        tx.object(clock),
      ],
    });

    const result = await this.client.signAndExecuteTransaction({
      signer: this.keypair,
      transaction: tx,
      options: {
        showEffects: true,
        showEvents: true,
      },
    });

    logger.info(`Proposal signed: ${result.digest}`);
    return result;
  }

  /**
   * Execute proposal on-chain
   */
  async executeProposal(
    proposalId: string,
    treasuryId: string,
    coinType: string
  ): Promise<any> {
    if (!this.keypair) {
      throw new Error('Keypair not initialized');
    }

    const tx = new Transaction();
    const clock = '0x6';

    tx.moveCall({
      target: `${this.packageId}::proposal::execute_proposal`,
      typeArguments: [coinType],
      arguments: [
        tx.object(proposalId),
        tx.object(treasuryId),
        tx.object(clock),
      ],
    });

    const result = await this.client.signAndExecuteTransaction({
      signer: this.keypair,
      transaction: tx,
      options: {
        showEffects: true,
        showEvents: true,
      },
    });

    logger.info(`Proposal executed: ${result.digest}`);
    return result;
  }

  /**
   * Get treasury object
   */
  async getTreasury(treasuryId: string): Promise<any> {
    return await this.client.getObject({
      id: treasuryId,
      options: {
        showContent: true,
        showOwner: true,
      },
    });
  }

  /**
   * Get proposal object
   */
  async getProposal(proposalId: string): Promise<any> {
    return await this.client.getObject({
      id: proposalId,
      options: {
        showContent: true,
        showOwner: true,
      },
    });
  }

  /**
   * Get events for treasury
   */
  async getTreasuryEvents(treasuryId: string): Promise<any> {
    // TODO: Filter by treasury ID
    logger.debug(`Fetching events for treasury ${treasuryId}`);
    return await this.client.queryEvents({
      query: { MoveEventModule: { package: this.packageId, module: 'treasury' } },
    });
  }

  /**
   * Get balance for address
   */
  async getBalance(address: string, coinType?: string): Promise<any> {
    if (coinType) {
      return await this.client.getBalance({ owner: address, coinType });
    }
    return await this.client.getAllBalances({ owner: address });
  }
}

// Singleton instance
export const suiClient = new SuiClientWrapper();
