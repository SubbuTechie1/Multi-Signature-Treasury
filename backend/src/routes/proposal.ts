import { Router, Request, Response } from 'express';
import { suiClient } from '../utils/suiClient';
import { validateCreateProposal, validateSignProposal } from '../validators/proposal';
import { logger } from '../utils/logger';

export const proposalRouter = Router();

/**
 * POST /proposal/create
 * Create a new proposal
 */
proposalRouter.post('/create', async (req: Request, res: Response) => {
  try {
    const { treasury_id, proposer, transactions, metadata, category } = req.body;

    // Validate input
    const validation = validateCreateProposal(req.body);
    if (!validation.valid) {
      return res.status(400).json({ error: 'Validation failed', details: validation.errors });
    }

    // Default time-lock: 24 hours (in milliseconds)
    const timeLockDuration = 86400000;

    // Create proposal on-chain
    const result = await suiClient.createProposal(
      treasury_id,
      transactions,
      metadata || '',
      category,
      timeLockDuration
    );

    // Extract proposal ID from object changes
    const createdObjects = result.objectChanges?.filter((change: any) => change.type === 'created') || [];
    const proposalObject = createdObjects.find((obj: any) => 
      obj.objectType?.includes('::proposal::Proposal')
    );

    if (!proposalObject) {
      throw new Error('Proposal object not found in transaction result');
    }

    logger.info(`Proposal created: ${proposalObject.objectId}`);

    return res.status(201).json({
      id: proposalObject.objectId,
      treasury_id,
      proposer,
      transactions,
      metadata,
      category,
      status: 'created',
      transaction_digest: result.digest,
    });
  } catch (error: any) {
    logger.error('Error creating proposal:', error);
    return res.status(500).json({ error: 'Failed to create proposal', message: error.message });
  }
});

/**
 * GET /proposal/list
 * List proposals with filters
 */
proposalRouter.get('/list', async (req: Request, res: Response) => {
  try {
    const { treasury_id, status, proposer, limit = 50, offset = 0 } = req.query;

    logger.debug(`List proposals: treasury=${treasury_id}, status=${status}, proposer=${proposer}, limit=${limit}, offset=${offset}`);

    // Query ProposalCreated events to find all proposals
    const packageId = process.env.TREASURY_PACKAGE_ID;
    const eventType = `${packageId}::proposal::ProposalCreated`;

    const events = await suiClient.getClient().queryEvents({
      query: { MoveEventType: eventType },
      limit: 100,
      order: 'descending',
    });

    // Extract proposal IDs from events and fetch their current state
    const proposalIds = events.data.map((event: any) => event.parsedJson?.proposal_id).filter(Boolean);

    if (proposalIds.length === 0) {
      return res.json({
        proposals: [],
        total: 0,
        limit: Number(limit),
        offset: Number(offset),
      });
    }

    // Fetch all proposal objects
    const proposalObjects = await suiClient.getClient().multiGetObjects({
      ids: proposalIds,
      options: {
        showContent: true,
        showType: true,
      },
    });

    // Parse proposals
    let proposals = proposalObjects
      .filter((obj: any) => obj.data?.content?.dataType === 'moveObject')
      .map((obj: any) => {
        const fields = obj.data.content.fields;
        return {
          id: obj.data.objectId,
          treasury_id: fields.treasury_id,
          proposer: fields.proposer,
          category: fields.category,
          status: fields.status,
          signatures_count: fields.signatures?.length || 0,
          metadata: fields.metadata,
          created_at: fields.created_at,
          time_lock_end: fields.time_lock_end,
        };
      });

    // Apply filters
    if (treasury_id) {
      proposals = proposals.filter((p: any) => p.treasury_id === treasury_id);
    }
    if (status !== undefined) {
      proposals = proposals.filter((p: any) => p.status === Number(status));
    }
    if (proposer) {
      proposals = proposals.filter((p: any) => p.proposer === proposer);
    }

    // Apply pagination
    const total = proposals.length;
    const paginatedProposals = proposals.slice(Number(offset), Number(offset) + Number(limit));

    logger.info(`Found ${total} proposals, returning ${paginatedProposals.length}`);

    return res.json({
      proposals: paginatedProposals,
      total,
      limit: Number(limit),
      offset: Number(offset),
    });
  } catch (error: any) {
    logger.error('Error listing proposals:', error);
    return res.status(500).json({ error: 'Failed to list proposals', message: error.message });
  }
});

/**
 * GET /proposal/:id
 * Get proposal details
 */
proposalRouter.get('/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;

    const proposal = await suiClient.getProposal(id);

    if (!proposal.data) {
      return res.status(404).json({ error: 'Proposal not found' });
    }

    return res.json({
      id: proposal.data.objectId,
      content: proposal.data.content,
      owner: proposal.data.owner,
    });
  } catch (error: any) {
    logger.error('Error fetching proposal:', error);
    return res.status(500).json({ error: 'Failed to fetch proposal', message: error.message });
  }
});

/**
 * POST /proposal/:id/sign
 * Sign a proposal
 */
proposalRouter.post('/:id/sign', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { signer, signature, treasury_id } = req.body;

    // Validate input
    const validation = validateSignProposal(req.body);
    if (!validation.valid) {
      return res.status(400).json({ error: 'Validation failed', details: validation.errors });
    }

    // Sign proposal on-chain
    const result = await suiClient.signProposal(id, treasury_id, signature);

    logger.info(`Proposal ${id} signed by ${signer}`);

    return res.json({
      id,
      status: 'signed',
      signer,
      transaction_digest: result.digest,
    });
  } catch (error: any) {
    logger.error('Error signing proposal:', error);
    return res.status(500).json({ error: 'Failed to sign proposal', message: error.message });
  }
});

/**
 * POST /proposal/:id/execute
 * Execute a proposal
 */
proposalRouter.post('/:id/execute', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { treasury_id, coin_type } = req.body;

    if (!treasury_id || !coin_type) {
      return res.status(400).json({ error: 'treasury_id and coin_type are required' });
    }

    // Execute proposal on-chain
    const result = await suiClient.executeProposal(id, treasury_id, coin_type);

    logger.info(`Proposal ${id} executed`);

    return res.json({
      id,
      status: 'executed',
      transaction_digest: result.digest,
      gas_used: result.effects?.gasUsed,
    });
  } catch (error: any) {
    logger.error('Error executing proposal:', error);
    return res.status(500).json({ error: 'Failed to execute proposal', message: error.message });
  }
});

/**
 * POST /proposal/:id/cancel
 * Cancel a proposal
 */
proposalRouter.post('/:id/cancel', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { canceller } = req.body;

    // TODO: Implement cancel proposal on-chain
    logger.info(`Cancel proposal ${id} by ${canceller}`);
    
    return res.status(501).json({ 
      error: 'Not implemented',
      message: 'Proposal cancellation not yet implemented' 
    });
  } catch (error: any) {
    logger.error('Error cancelling proposal:', error);
    return res.status(500).json({ error: 'Failed to cancel proposal', message: error.message });
  }
});
