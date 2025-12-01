import React, { useState } from 'react';
import axios from 'axios';
import './ProposalForm.css';

const API_BASE = process.env.REACT_APP_API_BASE || 'http://localhost:3000/api/v1';

interface Transaction {
  recipient: string;
  amount: string;
  coin_type: string;
}

export default function ProposalForm() {
  const [treasuryId, setTreasuryId] = useState('');
  const [metadata, setMetadata] = useState('');
  const [category, setCategory] = useState(0);
  const [transactions, setTransactions] = useState<Transaction[]>([
    { recipient: '', amount: '', coin_type: '0x2::sui::SUI' }
  ]);
  const [loading, setLoading] = useState(false);

  const addTransaction = () => {
    if (transactions.length < 50) {
      setTransactions([...transactions, { recipient: '', amount: '', coin_type: '0x2::sui::SUI' }]);
    }
  };

  const removeTransaction = (index: number) => {
    setTransactions(transactions.filter((_, i) => i !== index));
  };

  const updateTransaction = (index: number, field: keyof Transaction, value: string) => {
    const updated = [...transactions];
    updated[index][field] = value;
    setTransactions(updated);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    try {
      setLoading(true);

      // TODO: Get proposer address from connected wallet
      const proposerAddress = '0x1234...5678';

      const response = await axios.post(`${API_BASE}/proposal/create`, {
        treasury_id: treasuryId,
        proposer: proposerAddress,
        transactions,
        metadata,
        category,
      });

      alert(`Proposal created successfully! ID: ${response.data.id}`);
      
      // Reset form
      setTreasuryId('');
      setMetadata('');
      setCategory(0);
      setTransactions([{ recipient: '', amount: '', coin_type: '0x2::sui::SUI' }]);
      
    } catch (error: any) {
      console.error('Error creating proposal:', error);
      alert(`Failed to create proposal: ${error.response?.data?.message || error.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="proposal-form">
      <h2>Create Spending Proposal</h2>
      
      <form onSubmit={handleSubmit}>
        <div className="form-group">
          <label>Treasury ID:</label>
          <input
            type="text"
            value={treasuryId}
            onChange={(e) => setTreasuryId(e.target.value)}
            placeholder="0x..."
            required
          />
        </div>

        <div className="form-group">
          <label>Category:</label>
          <select value={category} onChange={(e) => setCategory(Number(e.target.value))}>
            <option value={0}>Operations</option>
            <option value={1}>Marketing</option>
            <option value={2}>Development</option>
            <option value={3}>Grants</option>
            <option value={4}>Emergency</option>
          </select>
        </div>

        <div className="form-group">
          <label>Description / Justification:</label>
          <textarea
            value={metadata}
            onChange={(e) => setMetadata(e.target.value)}
            placeholder="Describe the purpose of this proposal..."
            rows={4}
            required
          />
        </div>

        <div className="transactions-section">
          <h3>Transactions</h3>
          {transactions.map((tx, index) => (
            <div key={index} className="transaction-item">
              <div className="transaction-fields">
                <input
                  type="text"
                  placeholder="Recipient address (0x...)"
                  value={tx.recipient}
                  onChange={(e) => updateTransaction(index, 'recipient', e.target.value)}
                  required
                />
                <input
                  type="text"
                  placeholder="Amount (in MIST)"
                  value={tx.amount}
                  onChange={(e) => updateTransaction(index, 'amount', e.target.value)}
                  required
                />
                <input
                  type="text"
                  placeholder="Coin type"
                  value={tx.coin_type}
                  onChange={(e) => updateTransaction(index, 'coin_type', e.target.value)}
                  required
                />
                {transactions.length > 1 && (
                  <button 
                    type="button" 
                    onClick={() => removeTransaction(index)}
                    className="btn btn-danger btn-small"
                  >
                    Remove
                  </button>
                )}
              </div>
            </div>
          ))}
          
          {transactions.length < 50 && (
            <button 
              type="button" 
              onClick={addTransaction}
              className="btn btn-secondary"
            >
              Add Transaction
            </button>
          )}
        </div>

        <div className="form-actions">
          <button type="submit" disabled={loading} className="btn btn-primary">
            {loading ? 'Creating...' : 'Create Proposal'}
          </button>
        </div>
      </form>
    </div>
  );
}
