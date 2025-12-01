import Ajv, { JSONSchemaType } from 'ajv';
import addFormats from 'ajv-formats';

const ajv = new Ajv();
addFormats(ajv);

interface CreateProposalRequest {
  treasury_id: string;
  proposer: string;
  transactions: Array<{
    recipient: string;
    amount: string;
    coin_type: string;
  }>;
  metadata?: string;
  category: number;
}

interface SignProposalRequest {
  signer: string;
  signature: string;
  treasury_id: string;
}

const createProposalSchema: JSONSchemaType<CreateProposalRequest> = {
  type: 'object',
  properties: {
    treasury_id: { type: 'string' },
    proposer: { type: 'string' },
    transactions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          recipient: { type: 'string' },
          amount: { type: 'string' },
          coin_type: { type: 'string' },
        },
        required: ['recipient', 'amount', 'coin_type'],
      },
      minItems: 1,
      maxItems: 50,
    },
    metadata: { type: 'string', nullable: true },
    category: { type: 'number', minimum: 0, maximum: 4 },
  },
  required: ['treasury_id', 'proposer', 'transactions', 'category'],
  additionalProperties: true,
};

const signProposalSchema: JSONSchemaType<SignProposalRequest> = {
  type: 'object',
  properties: {
    signer: { type: 'string' },
    signature: { type: 'string' },
    treasury_id: { type: 'string' },
  },
  required: ['signer', 'signature', 'treasury_id'],
  additionalProperties: true,
};

const validateCreateProposalFn = ajv.compile(createProposalSchema);
const validateSignProposalFn = ajv.compile(signProposalSchema);

export function validateCreateProposal(data: any): { valid: boolean; errors?: any } {
  const valid = validateCreateProposalFn(data);
  return {
    valid,
    errors: valid ? undefined : validateCreateProposalFn.errors,
  };
}

export function validateSignProposal(data: any): { valid: boolean; errors?: any } {
  const valid = validateSignProposalFn(data);
  return {
    valid,
    errors: valid ? undefined : validateSignProposalFn.errors,
  };
}
