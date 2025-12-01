# Multi-Signature Treasury - Deployment Guide

## Prerequisites

- [Sui CLI](https://docs.sui.io/build/install) installed and configured
- Node.js v18+ and npm
- Git

## 1. Deploy Smart Contracts

### Build Contracts

```powershell
cd contracts
sui move build
```

### Run Tests

```powershell
sui move test
```

### Deploy to Testnet

```powershell
# Switch to testnet
sui client switch --env testnet

# Publish contracts
sui client publish --gas-budget 100000000

# Save the Package ID from the output
```

## 2. Configure Backend

### Install Dependencies

```powershell
cd ..\backend
npm install
```

### Configure Environment

Copy `.env.example` to `.env` and update:

```env
SUI_NETWORK=testnet
SUI_PRIVATE_KEY=your_private_key_here
TREASURY_PACKAGE_ID=package_id_from_deployment
PORT=3000
```

### Start Backend

```powershell
npm run dev
```

## 3. Configure Frontend

### Install Dependencies

```powershell
cd ..\frontend
npm install
```

### Configure Environment

Create `.env` file:

```env
REACT_APP_API_BASE=http://localhost:3000/api/v1
REACT_APP_SUI_NETWORK=testnet
```

### Start Frontend

```powershell
npm start
```

## 4. Verify Deployment

1. Open http://localhost:3001 in your browser
2. Connect your Sui wallet
3. Create a test treasury
4. Create a test proposal
5. Sign and execute the proposal

## Production Deployment

### Backend (Node.js)

Deploy to your preferred platform:

- **Heroku**: `git push heroku main`
- **AWS EC2**: Use PM2 for process management
- **Docker**: Build and deploy container

### Frontend (React)

Deploy static build:

```powershell
npm run build
```

Deploy `build/` folder to:
- Vercel
- Netlify
- AWS S3 + CloudFront
- GitHub Pages

### Contracts

For mainnet deployment:

```powershell
sui client switch --env mainnet
sui client publish --gas-budget 100000000
```

## Security Checklist

- [ ] Store private keys securely (use environment variables, never commit)
- [ ] Enable rate limiting on API
- [ ] Use HTTPS in production
- [ ] Audit smart contracts before mainnet deployment
- [ ] Implement proper access controls
- [ ] Monitor gas costs and optimize
- [ ] Set up alerting for treasury events

## Monitoring

### Backend Logs

```powershell
# View logs
tail -f logs/combined.log

# View errors only
tail -f logs/error.log
```

### Smart Contract Events

Monitor on-chain events using Sui Explorer or custom indexer.

## Troubleshooting

### Contract Build Errors

```powershell
# Clean and rebuild
sui move clean
sui move build
```

### Backend Connection Issues

- Verify Sui network RPC URL
- Check private key format
- Ensure package ID is correct

### Frontend CORS Errors

- Update `CORS_ORIGIN` in backend `.env`
- Restart backend server

## Backup and Recovery

### Treasury Data

- Export treasury IDs and configurations
- Backup signer addresses and thresholds
- Document all active proposals

### Emergency Procedures

1. Freeze treasury using emergency signer
2. Contact all signers
3. Review and resolve issue
4. Unfreeze treasury with admin capability

## Support

For issues or questions:
- Open an issue on GitHub
- Check documentation at `/docs`
- Review smart contract comments
