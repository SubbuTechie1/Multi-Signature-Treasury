import React, { useState } from 'react';
import axios from 'axios';
import './TreasurySetup.css';

const API_BASE = process.env.REACT_APP_API_BASE || 'http://localhost:3000/api/v1';

export default function TreasurySetup() {
  const [signers, setSigners] = useState<string[]>(['', '']);
  const [threshold, setThreshold] = useState(2);
  const [emergencySigners, setEmergencySigners] = useState<string[]>(['']);
  const [emergencyThreshold, setEmergencyThreshold] = useState(1);
  const [loading, setLoading] = useState(false);

  const addSigner = () => {
    setSigners([...signers, '']);
  };

  const removeSigner = (index: number) => {
    if (signers.length > 2) {
      setSigners(signers.filter((_: string, i: number) => i !== index));
    }
  };

  const updateSigner = (index: number, value: string) => {
    const updated = [...signers];
    updated[index] = value;
    setSigners(updated);
  };

  const addEmergencySigner = () => {
    setEmergencySigners([...emergencySigners, '']);
  };

  const removeEmergencySigner = (index: number) => {
    if (emergencySigners.length > 1) {
      setEmergencySigners(emergencySigners.filter((_: string, i: number) => i !== index));
    }
  };

  const updateEmergencySigner = (index: number, value: string) => {
    const updated = [...emergencySigners];
    updated[index] = value;
    setEmergencySigners(updated);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    try {
      setLoading(true);

      // Filter out empty signers
      const validSigners = signers.filter(s => s.trim() !== '');
      const validEmergencySigners = emergencySigners.filter(s => s.trim() !== '');

      if (validSigners.length < 2) {
        alert('At least 2 signers are required');
        return;
      }

      if (threshold < 2 || threshold > validSigners.length) {
        alert('Threshold must be between 2 and number of signers');
        return;
      }

      const response = await axios.post(`${API_BASE}/treasury/create`, {
        signers: validSigners,
        threshold,
        emergency_signers: validEmergencySigners.length > 0 ? validEmergencySigners : undefined,
        emergency_threshold: validEmergencySigners.length > 0 ? emergencyThreshold : undefined,
      });

      alert(`Treasury created successfully! ID: ${response.data.id}`);
      
      // Reset form
      setSigners(['', '']);
      setThreshold(2);
      setEmergencySigners(['']);
      setEmergencyThreshold(1);
      
    } catch (error: any) {
      console.error('Error creating treasury:', error);
      alert(`Failed to create treasury: ${error.response?.data?.message || error.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="treasury-setup">
      <h2>Create New Treasury</h2>
      
      <form onSubmit={handleSubmit}>
        <div className="form-section">
          <h3>Regular Signers</h3>
          {signers.map((signer, index) => (
            <div key={index} className="signer-input">
              <input
                type="text"
                placeholder="Signer address (0x...)"
                value={signer}
                onChange={(e) => updateSigner(index, e.target.value)}
                required
              />
              {signers.length > 2 && (
                <button 
                  type="button" 
                  onClick={() => removeSigner(index)}
                  className="btn btn-danger btn-small"
                >
                  Remove
                </button>
              )}
            </div>
          ))}
          <button 
            type="button" 
            onClick={addSigner}
            className="btn btn-secondary"
          >
            Add Signer
          </button>

          <div className="form-group">
            <label>Threshold (signatures required):</label>
            <input
              type="number"
              min="2"
              max={signers.length}
              value={threshold}
              onChange={(e) => setThreshold(Number(e.target.value))}
              required
            />
            <small>Must be between 2 and {signers.length}</small>
          </div>
        </div>

        <div className="form-section">
          <h3>Emergency Signers (Optional)</h3>
          {emergencySigners.map((signer, index) => (
            <div key={index} className="signer-input">
              <input
                type="text"
                placeholder="Emergency signer address (0x...)"
                value={signer}
                onChange={(e) => updateEmergencySigner(index, e.target.value)}
              />
              {emergencySigners.length > 1 && (
                <button 
                  type="button" 
                  onClick={() => removeEmergencySigner(index)}
                  className="btn btn-danger btn-small"
                >
                  Remove
                </button>
              )}
            </div>
          ))}
          <button 
            type="button" 
            onClick={addEmergencySigner}
            className="btn btn-secondary"
          >
            Add Emergency Signer
          </button>

          <div className="form-group">
            <label>Emergency Threshold:</label>
            <input
              type="number"
              min="1"
              max={emergencySigners.length}
              value={emergencyThreshold}
              onChange={(e) => setEmergencyThreshold(Number(e.target.value))}
            />
          </div>
        </div>

        <div className="form-actions">
          <button type="submit" disabled={loading} className="btn btn-primary">
            {loading ? 'Creating...' : 'Create Treasury'}
          </button>
        </div>
      </form>
    </div>
  );
}
