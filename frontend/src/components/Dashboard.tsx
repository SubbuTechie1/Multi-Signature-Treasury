import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './Dashboard.css';

interface Proposal {
  id: string;
  treasury_id: string;
  proposer: string;
  category: number;
  status: string;
  signatures_count?: number;
  metadata?: string;
}

const API_BASE = process.env.REACT_APP_API_BASE || 'http://localhost:3000/api/v1';

export default function Dashboard() {
  const [proposals, setProposals] = useState<Proposal[]>([]);
  const [treasuries, setTreasuries] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      
      // Fetch proposals
      const proposalsRes = await axios.get(`${API_BASE}/proposal/list`);
      setProposals(proposalsRes.data.proposals || []);

      // Fetch treasuries list
      const treasuriesRes = await axios.get(`${API_BASE}/treasury/list`);
      setTreasuries(treasuriesRes.data.treasuries || []);
      
      setLoading(false);
    } catch (error) {
      console.error('Error fetching data:', error);
      setLoading(false);
    }
  };

  const handleSignProposal = async (proposalId: string) => {
    try {
      // TODO: Implement proposal signing with wallet
      console.log('Signing proposal:', proposalId);
      alert('Proposal signing not yet implemented');
    } catch (error) {
      console.error('Error signing proposal:', error);
    }
  };

  const handleExecuteProposal = async (proposalId: string) => {
    try {
      // TODO: Implement proposal execution
      console.log('Executing proposal:', proposalId);
      alert('Proposal execution not yet implemented');
    } catch (error) {
      console.error('Error executing proposal:', error);
    }
  };

  const getCategoryName = (category: number): string => {
    const categories = ['Operations', 'Marketing', 'Development', 'Grants', 'Emergency'];
    return categories[category] || 'Unknown';
  };

  const getStatusBadge = (status: string | number): string => {
    // Status is a number from Move contract: 0=Created, 1=Signed, 2=Executable, 3=Executed, 4=Cancelled
    const statusMap: { [key: number]: string } = {
      0: 'Created',
      1: 'Signed',
      2: 'Executable',
      3: 'Executed',
      4: 'Cancelled',
    };
    
    if (typeof status === 'number') {
      return statusMap[status] || 'Unknown';
    }
    
    // Fallback for string status
    return status.charAt(0).toUpperCase() + status.slice(1);
  };

  if (loading) {
    return <div className="dashboard">Loading...</div>;
  }

  return (
    <div className="dashboard">
      <h1>Treasury Dashboard</h1>

      <section className="section">
        <h2>Pending Proposals</h2>
        {proposals.length === 0 ? (
          <p>No proposals found. Create your first proposal!</p>
        ) : (
          <div className="proposals-grid">
            {proposals.map((proposal) => (
              <div key={proposal.id} className="proposal-card">
                <div className="proposal-header">
                  <span className={`status-badge status-${proposal.status}`}>
                    {getStatusBadge(proposal.status)}
                  </span>
                  <span className="category-badge">
                    {getCategoryName(proposal.category)}
                  </span>
                </div>
                <div className="proposal-body">
                  <p className="proposal-id">ID: {proposal.id.slice(0, 20)}...</p>
                  <p className="proposal-metadata">{proposal.metadata || 'No description'}</p>
                  <p className="proposal-proposer">Proposer: {proposal.proposer.slice(0, 10)}...</p>
                </div>
                <div className="proposal-actions">
                  {proposal.status === 'created' || proposal.status === 'signed' ? (
                    <button 
                      onClick={() => handleSignProposal(proposal.id)}
                      className="btn btn-primary"
                    >
                      Sign Proposal
                    </button>
                  ) : null}
                  {proposal.status === 'executable' ? (
                    <button 
                      onClick={() => handleExecuteProposal(proposal.id)}
                      className="btn btn-success"
                    >
                      Execute
                    </button>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="section">
        <h2>Your Treasuries</h2>
        {treasuries.length === 0 ? (
          <p>No treasuries found. Create your first treasury!</p>
        ) : (
          <div className="treasuries-grid">
            {treasuries.map((treasury) => (
              <div key={treasury.adminCapId || treasury.id} className="treasury-card">
                <h3>Treasury</h3>
                <p><strong>Admin Cap:</strong> {(treasury.adminCapId || treasury.id)?.slice(0, 20)}...</p>
                {treasury.treasuryId && (
                  <p><strong>Treasury ID:</strong> {treasury.treasuryId?.slice(0, 20)}...</p>
                )}
                <p><strong>Owner:</strong> {treasury.owner?.slice(0, 10)}...</p>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
