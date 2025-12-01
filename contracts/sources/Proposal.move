module treasury::proposal {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use std::vector;
    use sui::clock::{Self, Clock};
    use treasury::treasury::{Self, Treasury};

    // Error codes
    const E_NOT_PROPOSER: u64 = 100;
    const E_ALREADY_SIGNED: u64 = 101;
    const E_NOT_SIGNER: u64 = 102;
    const E_TIMELOCK_ACTIVE: u64 = 103;
    const E_THRESHOLD_NOT_MET: u64 = 104;
    const E_INVALID_STATUS: u64 = 105;
    const E_ALREADY_EXECUTED: u64 = 106;
    const E_TOO_MANY_TRANSACTIONS: u64 = 107;
    const E_TREASURY_FROZEN: u64 = 108;

    // Constants
    const MAX_TRANSACTIONS: u64 = 50;

    // Proposal status
    const STATUS_CREATED: u8 = 0;
    const STATUS_SIGNED: u8 = 1;
    const STATUS_EXECUTABLE: u8 = 2;
    const STATUS_EXECUTED: u8 = 3;
    const STATUS_CANCELLED: u8 = 4;

    // Spending categories
    const CATEGORY_OPERATIONS: u8 = 0;
    const CATEGORY_MARKETING: u8 = 1;
    const CATEGORY_DEVELOPMENT: u8 = 2;
    const CATEGORY_GRANTS: u8 = 3;
    const CATEGORY_EMERGENCY: u8 = 4;

    /// Transaction details within a proposal
    public struct Transaction has store, copy, drop {
        recipient: address,
        amount: u64,
        coin_type: std::ascii::String,
    }

    /// Signature from a signer
    public struct Signature has store, copy, drop {
        signer: address,
        signature: vector<u8>,
        signed_at: u64,
    }

    /// Proposal for spending from treasury
    public struct Proposal has key, store {
        id: UID,
        /// Associated treasury ID
        treasury_id: ID,
        /// Address that created proposal
        proposer: address,
        /// List of transactions to execute
        transactions: vector<Transaction>,
        /// Spending category
        category: u8,
        /// Collected signatures
        signatures: vector<Signature>,
        /// Timestamp when created
        created_at: u64,
        /// Timestamp when time-lock expires
        time_lock_end: u64,
        /// Current status
        status: u8,
        /// Human-readable metadata
        metadata: std::string::String,
    }

    // ==================== Events ====================

    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        treasury_id: ID,
        proposer: address,
        category: u8,
        time_lock_end: u64,
        transaction_count: u64,
    }

    public struct ProposalSigned has copy, drop {
        proposal_id: ID,
        signer: address,
        signatures_count: u64,
        threshold: u8,
    }

    public struct ProposalExecuted has copy, drop {
        proposal_id: ID,
        treasury_id: ID,
        executed_by: address,
        executed_at: u64,
    }

    public struct ProposalCancelled has copy, drop {
        proposal_id: ID,
        cancelled_by: address,
        cancelled_at: u64,
    }

    // ==================== Core Functions ====================

    /// Create a new spending proposal
    /// Note: Not marked as 'entry' because it takes vector<Transaction> (custom struct)
    /// Call this from a PTB (Programmable Transaction Block) instead
    public fun create_proposal(
        treasury: &Treasury,
        transactions: vector<Transaction>,
        metadata: vector<u8>,
        category: u8,
        time_lock_duration: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validations
        assert!(!treasury::is_frozen(treasury), E_TREASURY_FROZEN);
        assert!(vector::length(&transactions) > 0, E_TOO_MANY_TRANSACTIONS);
        assert!(vector::length(&transactions) <= MAX_TRANSACTIONS, E_TOO_MANY_TRANSACTIONS);

        let sender = tx_context::sender(ctx);
        let proposal_uid = object::new(ctx);
        let proposal_id = object::uid_to_inner(&proposal_uid);
        let treasury_id = object::id(treasury);
        let now = clock::timestamp_ms(clock);

        let proposal = Proposal {
            id: proposal_uid,
            treasury_id,
            proposer: sender,
            transactions,
            category,
            signatures: vector::empty(),
            created_at: now,
            time_lock_end: now + time_lock_duration,
            status: STATUS_CREATED,
            metadata: std::string::utf8(metadata),
        };

        event::emit(ProposalCreated {
            proposal_id,
            treasury_id,
            proposer: sender,
            category,
            time_lock_end: proposal.time_lock_end,
            transaction_count: vector::length(&proposal.transactions),
        });

        transfer::share_object(proposal);
    }

    /// Sign a proposal
    public entry fun sign_proposal(
        proposal: &mut Proposal,
        treasury: &Treasury,
        signature_bytes: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Validations
        assert!(proposal.status == STATUS_CREATED || proposal.status == STATUS_SIGNED, E_INVALID_STATUS);
        assert!(treasury::is_signer(treasury, sender), E_NOT_SIGNER);
        assert!(!has_signed(proposal, sender), E_ALREADY_SIGNED);

        // Add signature
        let signature = Signature {
            signer: sender,
            signature: signature_bytes,
            signed_at: clock::timestamp_ms(clock),
        };
        vector::push_back(&mut proposal.signatures, signature);

        // Update status
        let signatures_count = vector::length(&proposal.signatures);
        let threshold = treasury::get_threshold(treasury);
        
        if ((signatures_count as u8) >= threshold) {
            proposal.status = STATUS_EXECUTABLE;
        } else {
            proposal.status = STATUS_SIGNED;
        };

        event::emit(ProposalSigned {
            proposal_id: object::uid_to_inner(&proposal.id),
            signer: sender,
            signatures_count,
            threshold,
        });
    }

    /// Execute proposal (after threshold and time-lock met)
    public entry fun execute_proposal<T>(
        proposal: &mut Proposal,
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validations
        assert!(proposal.status == STATUS_EXECUTABLE, E_INVALID_STATUS);
        assert!(!treasury::is_frozen(treasury), E_TREASURY_FROZEN);
        
        let now = clock::timestamp_ms(clock);
        assert!(now >= proposal.time_lock_end, E_TIMELOCK_ACTIVE);

        let signatures_count = vector::length(&proposal.signatures);
        let threshold = treasury::get_threshold(treasury);
        assert!((signatures_count as u8) >= threshold, E_THRESHOLD_NOT_MET);

        // Execute all transactions
        // Note: In production, you'd iterate and execute each transaction
        // For now, this is a skeleton showing the pattern
        let mut i = 0;
        let len = vector::length(&proposal.transactions);
        while (i < len) {
            let _tx = vector::borrow(&proposal.transactions, i);
            // TODO: Execute transaction: withdraw from treasury and transfer to recipient
            // let coin = treasury::withdraw<T>(treasury, tx.amount, ctx);
            // transfer::public_transfer(coin, tx.recipient);
            i = i + 1;
        };

        proposal.status = STATUS_EXECUTED;

        event::emit(ProposalExecuted {
            proposal_id: object::uid_to_inner(&proposal.id),
            treasury_id: proposal.treasury_id,
            executed_by: tx_context::sender(ctx),
            executed_at: now,
        });
    }

    /// Cancel proposal (by proposer or unanimous signers)
    public entry fun cancel_proposal(
        proposal: &mut Proposal,
        treasury: &Treasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        assert!(
            proposal.status == STATUS_CREATED || 
            proposal.status == STATUS_SIGNED ||
            proposal.status == STATUS_EXECUTABLE,
            E_INVALID_STATUS
        );

        // Allow proposer to cancel
        let mut can_cancel = sender == proposal.proposer;

        // Or allow if all signers agree (check if all signers have signed cancellation)
        if (!can_cancel) {
            can_cancel = treasury::is_signer(treasury, sender);
            // TODO: Implement unanimous cancellation logic
        };

        assert!(can_cancel, E_NOT_PROPOSER);

        proposal.status = STATUS_CANCELLED;

        event::emit(ProposalCancelled {
            proposal_id: object::uid_to_inner(&proposal.id),
            cancelled_by: sender,
            cancelled_at: clock::timestamp_ms(clock),
        });
    }

    // ==================== View Functions ====================

    /// Check if address has already signed
    public fun has_signed(proposal: &Proposal, addr: address): bool {
        let mut i = 0;
        let len = vector::length(&proposal.signatures);
        while (i < len) {
            let sig = vector::borrow(&proposal.signatures, i);
            if (sig.signer == addr) {
                return true
            };
            i = i + 1;
        };
        false
    }

    /// Get proposal status
    public fun get_status(proposal: &Proposal): u8 {
        proposal.status
    }

    /// Get signatures count
    public fun get_signatures_count(proposal: &Proposal): u64 {
        vector::length(&proposal.signatures)
    }

    /// Get proposal category
    public fun get_category(proposal: &Proposal): u8 {
        proposal.category
    }

    /// Get proposal treasury ID
    public fun get_treasury_id(proposal: &Proposal): ID {
        proposal.treasury_id
    }

    /// Get time lock end
    public fun get_time_lock_end(proposal: &Proposal): u64 {
        proposal.time_lock_end
    }

    /// Get transactions
    public fun get_transactions(proposal: &Proposal): &vector<Transaction> {
        &proposal.transactions
    }

    /// Calculate total amount in proposal
    public fun calculate_total_amount(proposal: &Proposal): u64 {
        let mut total = 0u64;
        let mut i = 0;
        let len = vector::length(&proposal.transactions);
        while (i < len) {
            let tx = vector::borrow(&proposal.transactions, i);
            total = total + tx.amount;
            i = i + 1;
        };
        total
    }

    // ==================== Transaction Builder ====================

    /// Create a transaction struct
    public fun create_transaction(
        recipient: address,
        amount: u64,
        coin_type: vector<u8>
    ): Transaction {
        Transaction {
            recipient,
            amount,
            coin_type: std::ascii::string(coin_type),
        }
    }

    // ==================== Test Helper Functions ====================

    #[test_only]
    public fun create_proposal_for_testing(
        treasury_id: ID,
        proposer: address,
        transactions: vector<Transaction>,
        category: u8,
        ctx: &mut TxContext
    ): Proposal {
        let proposal_uid = object::new(ctx);
        
        Proposal {
            id: proposal_uid,
            treasury_id,
            proposer,
            transactions,
            category,
            signatures: vector::empty(),
            created_at: 0,
            time_lock_end: 0,
            status: STATUS_CREATED,
            metadata: std::string::utf8(b"Test proposal"),
        }
    }

    #[test_only]
    public fun destroy_proposal_for_testing(proposal: Proposal) {
        let Proposal {
            id,
            treasury_id: _,
            proposer: _,
            transactions: _,
            category: _,
            signatures: _,
            created_at: _,
            time_lock_end: _,
            status: _,
            metadata: _,
        } = proposal;
        
        object::delete(id);
    }
}
