import { Router, Request, Response } from 'express';
import { suiClient } from '../utils/suiClient';
import { validateCreateTreasury, validateDeposit } from '../validators/treasury';
import { logger } from '../utils/logger';

export const treasuryRouter = Router();

/**
 * POST /treasury/create
 * Create a new treasury
 */
treasuryRouter.post('/create', async (req: Request, res: Response) => {
  try {
    const { signers, threshold, emergency_signers, emergency_threshold } = req.body;

    // Validate input
    const validation = validateCreateTreasury(req.body);
    if (!validation.valid) {
      return res.status(400).json({ error: 'Validation failed', details: validation.errors });
    }

    // Call Sui client to deploy treasury
    const result = await suiClient.createTreasury(
      signers,
      threshold,
      emergency_signers || [],
      emergency_threshold || 0
    );

    // Extract treasury ID from object changes
    const createdObjects = result.objectChanges?.filter((change: any) => change.type === 'created') || [];
    const treasuryObject = createdObjects.find((obj: any) => 
      obj.objectType?.includes('::treasury::Treasury')
    );

    if (!treasuryObject) {
      throw new Error('Treasury object not found in transaction result');
    }

    logger.info(`Treasury created: ${treasuryObject.objectId}`);

    return res.status(201).json({
      id: treasuryObject.objectId,
      signers,
      threshold,
      emergency_signers: emergency_signers || [],
      emergency_threshold: emergency_threshold || 0,
      transaction_digest: result.digest,
    });
  } catch (error: any) {
    logger.error('Error creating treasury:', error);
    return res.status(500).json({ error: 'Failed to create treasury', message: error.message });
  }
});

/**
 * GET /treasury/list
 * Get all treasuries (owned by signer)
 */
treasuryRouter.get('/list', async (req: Request, res: Response) => {
  try {
    const signerAddress = suiClient.getSignerAddress();
    
    // Get all owned objects
    const ownedObjects = await suiClient.getClient().getOwnedObjects({
      owner: signerAddress,
      options: {
        showType: true,
        showContent: true,
      },
    });

    // Filter for TreasuryAdminCap objects
    const treasuries = ownedObjects.data
      .filter((obj: any) => obj.data?.type?.includes('::treasury::TreasuryAdminCap'))
      .map((obj: any) => {
        const fields = obj.data?.content?.dataType === 'moveObject' 
          ? (obj.data.content as any).fields 
          : null;
        
        return {
          adminCapId: obj.data?.objectId,
          treasuryId: fields?.treasury_id || null,
          type: obj.data?.type,
          owner: signerAddress,
        };
      });

    logger.info(`Found ${treasuries.length} treasuries for ${signerAddress}`);

    return res.json({
      treasuries,
      count: treasuries.length,
    });
  } catch (error: any) {
    logger.error('Error fetching treasuries:', error);
    return res.status(500).json({ error: 'Failed to fetch treasuries', message: error.message });
  }
});

/**
 * GET /treasury/:id
 * Get treasury details
 */
treasuryRouter.get('/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;

    const treasury = await suiClient.getTreasury(id);

    if (!treasury.data) {
      return res.status(404).json({ error: 'Treasury not found' });
    }

    return res.json({
      id: treasury.data.objectId,
      content: treasury.data.content,
      owner: treasury.data.owner,
    });
  } catch (error: any) {
    logger.error('Error fetching treasury:', error);
    return res.status(500).json({ error: 'Failed to fetch treasury', message: error.message });
  }
});

/**
 * POST /treasury/:id/deposit
 * Deposit funds into treasury
 */
treasuryRouter.post('/:id/deposit', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { coin_id, coin_type } = req.body;

    // Validate input
    const validation = validateDeposit(req.body);
    if (!validation.valid) {
      return res.status(400).json({ error: 'Validation failed', details: validation.errors });
    }

    const result = await suiClient.depositToTreasury(id, coin_id, coin_type);

    logger.info(`Deposit to treasury ${id}: ${result.digest}`);

    return res.json({
      status: 'success',
      transaction_digest: result.digest,
    });
  } catch (error: any) {
    logger.error('Error depositing to treasury:', error);
    return res.status(500).json({ error: 'Failed to deposit', message: error.message });
  }
});

/**
 * GET /treasury/:id/balance
 * Get treasury balances
 */
treasuryRouter.get('/:id/balance', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;

    const treasury = await suiClient.getTreasury(id);
    
    if (!treasury.data) {
      return res.status(404).json({ error: 'Treasury not found' });
    }

    // Extract balances from treasury content
    // Note: This depends on the actual object structure
    const content: any = treasury.data.content;
    const balances = content?.fields?.balances || [];

    return res.json({
      treasury_id: id,
      balances,
    });
  } catch (error: any) {
    logger.error('Error fetching treasury balance:', error);
    return res.status(500).json({ error: 'Failed to fetch balance', message: error.message });
  }
});

/**
 * PUT /treasury/:id/signers
 * Update treasury signers (requires multi-sig approval)
 */
treasuryRouter.put('/:id/signers', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { new_signers, new_threshold } = req.body;

    // TODO: Implement signer update through proposal system
    // For now, return not implemented
    logger.info(`Update signers request for treasury ${id}: ${new_signers?.length || 0} signers, threshold ${new_threshold}`);

    return res.status(501).json({ 
      error: 'Not implemented',
      message: 'Signer updates must go through proposal system' 
    });
  } catch (error: any) {
    logger.error('Error updating signers:', error);
    return res.status(500).json({ error: 'Failed to update signers', message: error.message });
  }
});

/**
 * GET /treasury/:id/events
 * Get treasury events
 */
treasuryRouter.get('/:id/events', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;

    const events = await suiClient.getTreasuryEvents(id);

    return res.json({
      treasury_id: id,
      events: events.data || [],
    });
  } catch (error: any) {
    logger.error('Error fetching treasury events:', error);
    return res.status(500).json({ error: 'Failed to fetch events', message: error.message });
  }
});
