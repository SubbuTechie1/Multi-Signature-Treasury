import React, { useState } from 'react';
import { BrowserRouter as Router, Routes, Route, Link } from 'react-router-dom';
import './App.css';
import Dashboard from './components/Dashboard';
import TreasurySetup from './components/TreasurySetup';
import ProposalForm from './components/ProposalForm';

function App() {
  const [connectedWallet, setConnectedWallet] = useState<string | null>(null);

  const connectWallet = async () => {
    // TODO: Implement wallet connection using @mysten/wallet-kit
    setConnectedWallet('0x1234...5678'); // Placeholder
  };

  return (
    <Router>
      <div className="App">
        <header className="App-header">
          <nav>
            <Link to="/">Dashboard</Link>
            <Link to="/create-treasury">Create Treasury</Link>
            <Link to="/create-proposal">Create Proposal</Link>
          </nav>
          <div className="wallet-section">
            {connectedWallet ? (
              <div>Connected: {connectedWallet}</div>
            ) : (
              <button onClick={connectWallet}>Connect Wallet</button>
            )}
          </div>
        </header>

        <main>
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/create-treasury" element={<TreasurySetup />} />
            <Route path="/create-proposal" element={<ProposalForm />} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

export default App;
