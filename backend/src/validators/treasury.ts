import Ajv, { JSONSchemaType } from 'ajv';
import addFormats from 'ajv-formats';

const ajv = new Ajv();
addFormats(ajv);

interface CreateTreasuryRequest {
  signers: string[];
  threshold: number;
  emergency_signers?: string[];
  emergency_threshold?: number;
}

interface DepositRequest {
  coin_id: string;
  coin_type: string;
}

const createTreasurySchema: JSONSchemaType<CreateTreasuryRequest> = {
  type: 'object',
  properties: {
    signers: {
      type: 'array',
      items: { type: 'string' },
      minItems: 2,
    },
    threshold: {
      type: 'number',
      minimum: 2,
    },
    emergency_signers: {
      type: 'array',
      items: { type: 'string' },
      nullable: true,
    },
    emergency_threshold: {
      type: 'number',
      minimum: 1,
      nullable: true,
    },
  },
  required: ['signers', 'threshold'],
  additionalProperties: true,
};

const depositSchema: JSONSchemaType<DepositRequest> = {
  type: 'object',
  properties: {
    coin_id: { type: 'string' },
    coin_type: { type: 'string' },
  },
  required: ['coin_id', 'coin_type'],
  additionalProperties: true,
};

const validateCreateTreasuryFn = ajv.compile(createTreasurySchema);
const validateDepositFn = ajv.compile(depositSchema);

export function validateCreateTreasury(data: any): { valid: boolean; errors?: any } {
  const valid = validateCreateTreasuryFn(data);
  return {
    valid,
    errors: valid ? undefined : validateCreateTreasuryFn.errors,
  };
}

export function validateDeposit(data: any): { valid: boolean; errors?: any } {
  const valid = validateDepositFn(data);
  return {
    valid,
    errors: valid ? undefined : validateDepositFn.errors,
  };
}
