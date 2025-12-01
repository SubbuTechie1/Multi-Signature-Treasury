module treasury::emergency_module {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Coin};
    use sui::event;
    use std::vector;
    use sui::clock::{Self, Clock};
    use treasury::treasury::{Self, Treasury};

    // Error codes
    const E_NOT_EMERGENCY_SIGNER: u64 = 300;
    const E_EMERGENCY_THRESHOLD_NOT_MET: u64 = 301;
    const E_COOLDOWN_ACTIVE: u64 = 302;
    const E_TREASURY_NOT_FROZEN: u64 = 303;
    const E_ALREADY_SIGNED_EMERGENCY: u64 = 304;
    const E_EMERGENCY_EXECUTED: u64 = 305;

    // Constants
    const EMERGENCY_COOLDOWN: u64 = 86400000; // 24 hours in milliseconds

    /// Emergency signature
    public struct EmergencySignature has store, copy, drop {
        signer: address,
        signature: vector<u8>,
        signed_at: u64,
    }

    /// Emergency withdrawal proposal
    public struct EmergencyProposal has key, store {
        id: UID,
        treasury_id: ID,
        proposer: address,
        recipient: address,
        amount: u64,
        coin_type: std::ascii::String,
        reason: std::string::String,
        signatures: vector<EmergencySignature>,
        created_at: u64,
        executed: bool,
    }

    /// Emergency audit log entry
    public struct EmergencyAuditLog has key, store {
        id: UID,
        treasury_id: ID,
        action: std::string::String,
        executed_by: address,
        amount: u64,
        timestamp: u64,
        reason: std::string::String,
    }

    /// Cooldown tracker for treasury
    public struct EmergencyCooldown has key, store {
        id: UID,
        treasury_id: ID,
        last_emergency: u64,
    }

    // ==================== Events ====================

    public struct EmergencyProposalCreated has copy, drop {
        proposal_id: ID,
        treasury_id: ID,
        proposer: address,
        amount: u64,
        reason: std::string::String,
    }

    public struct EmergencyProposalSigned has copy, drop {
        proposal_id: ID,
        signer: address,
        signatures_count: u64,
        emergency_threshold: u8,
    }

    public struct EmergencyWithdrawalExecuted has copy, drop {
        proposal_id: ID,
        treasury_id: ID,
        recipient: address,
        amount: u64,
        executed_by: address,
        timestamp: u64,
    }

    public struct TreasuryFrozenEmergency has copy, drop {
        treasury_id: ID,
        frozen_by: address,
        reason: std::string::String,
        timestamp: u64,
    }

    // ==================== Core Functions ====================

    /// Create emergency withdrawal proposal
    public entry fun create_emergency_proposal(
        treasury: &Treasury,
        recipient: address,
        amount: u64,
        coin_type: vector<u8>,
        reason: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(treasury::is_emergency_signer(treasury, sender), E_NOT_EMERGENCY_SIGNER);

        let proposal_uid = object::new(ctx);
        let proposal_id = object::uid_to_inner(&proposal_uid);
        let treasury_id = object::id(treasury);

        let proposal = EmergencyProposal {
            id: proposal_uid,
            treasury_id,
            proposer: sender,
            recipient,
            amount,
            coin_type: std::ascii::string(coin_type),
            reason: std::string::utf8(reason),
            signatures: vector::empty(),
            created_at: clock::timestamp_ms(clock),
            executed: false,
        };

        event::emit(EmergencyProposalCreated {
            proposal_id,
            treasury_id,
            proposer: sender,
            amount,
            reason: proposal.reason,
        });

        transfer::share_object(proposal);
    }

    /// Sign emergency proposal
    public entry fun sign_emergency_proposal(
        proposal: &mut EmergencyProposal,
        treasury: &Treasury,
        signature_bytes: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        assert!(!proposal.executed, E_EMERGENCY_EXECUTED);
        assert!(treasury::is_emergency_signer(treasury, sender), E_NOT_EMERGENCY_SIGNER);
        assert!(!has_signed_emergency(proposal, sender), E_ALREADY_SIGNED_EMERGENCY);

        let signature = EmergencySignature {
            signer: sender,
            signature: signature_bytes,
            signed_at: clock::timestamp_ms(clock),
        };
        vector::push_back(&mut proposal.signatures, signature);

        let signatures_count = vector::length(&proposal.signatures);
        
        event::emit(EmergencyProposalSigned {
            proposal_id: object::uid_to_inner(&proposal.id),
            signer: sender,
            signatures_count,
            emergency_threshold: get_emergency_threshold(treasury),
        });
    }

    /// Execute emergency withdrawal (no time-lock)
    public entry fun execute_emergency_withdrawal<T>(
        proposal: &mut EmergencyProposal,
        treasury: &mut Treasury,
        cooldown: &mut EmergencyCooldown,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!proposal.executed, E_EMERGENCY_EXECUTED);
        
        // Check threshold
        let signatures_count = vector::length(&proposal.signatures);
        let emergency_threshold = get_emergency_threshold(treasury);
        assert!((signatures_count as u8) >= emergency_threshold, E_EMERGENCY_THRESHOLD_NOT_MET);

        // Check cooldown
        let now = clock::timestamp_ms(clock);
        if (cooldown.last_emergency > 0) {
            assert!(now >= cooldown.last_emergency + EMERGENCY_COOLDOWN, E_COOLDOWN_ACTIVE);
        };

        // Execute withdrawal
        let coin = treasury::withdraw<T>(treasury, proposal.amount, ctx);
        transfer::public_transfer(coin, proposal.recipient);

        proposal.executed = true;
        cooldown.last_emergency = now;

        // Create audit log
        let audit_log = EmergencyAuditLog {
            id: object::new(ctx),
            treasury_id: proposal.treasury_id,
            action: std::string::utf8(b"Emergency Withdrawal"),
            executed_by: tx_context::sender(ctx),
            amount: proposal.amount,
            timestamp: now,
            reason: proposal.reason,
        };

        event::emit(EmergencyWithdrawalExecuted {
            proposal_id: object::uid_to_inner(&proposal.id),
            treasury_id: proposal.treasury_id,
            recipient: proposal.recipient,
            amount: proposal.amount,
            executed_by: tx_context::sender(ctx),
            timestamp: now,
        });

        transfer::share_object(audit_log);
    }

    /// Freeze treasury immediately (emergency)
    public entry fun freeze_treasury_emergency(
        treasury: &mut Treasury,
        reason: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(treasury::is_emergency_signer(treasury, sender), E_NOT_EMERGENCY_SIGNER);

        treasury::freeze_treasury(treasury, clock, ctx);

        // Create audit log
        let audit_log = EmergencyAuditLog {
            id: object::new(ctx),
            treasury_id: object::id(treasury),
            action: std::string::utf8(b"Emergency Freeze"),
            executed_by: sender,
            amount: 0,
            timestamp: clock::timestamp_ms(clock),
            reason: std::string::utf8(reason),
        };

        event::emit(TreasuryFrozenEmergency {
            treasury_id: object::id(treasury),
            frozen_by: sender,
            reason: audit_log.reason,
            timestamp: clock::timestamp_ms(clock),
        });

        transfer::share_object(audit_log);
    }

    /// Initialize cooldown tracker for treasury
    public entry fun create_cooldown_tracker(
        treasury: &Treasury,
        ctx: &mut TxContext
    ) {
        let treasury_id = object::id(treasury);
        
        let cooldown = EmergencyCooldown {
            id: object::new(ctx),
            treasury_id,
            last_emergency: 0,
        };

        transfer::share_object(cooldown);
    }

    // ==================== View Functions ====================

    /// Check if address has signed emergency proposal
    public fun has_signed_emergency(proposal: &EmergencyProposal, addr: address): bool {
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

    /// Get emergency threshold from treasury
    fun get_emergency_threshold(treasury: &Treasury): u8 {
        // Note: Treasury module needs to expose this
        // For now, using standard threshold
        treasury::get_threshold(treasury)
    }

    /// Check if cooldown is active
    public fun is_cooldown_active(cooldown: &EmergencyCooldown, clock: &Clock): bool {
        if (cooldown.last_emergency == 0) {
            return false
        };
        
        let now = clock::timestamp_ms(clock);
        now < cooldown.last_emergency + EMERGENCY_COOLDOWN
    }

    /// Get time until cooldown expires
    public fun get_cooldown_remaining(cooldown: &EmergencyCooldown, clock: &Clock): u64 {
        if (cooldown.last_emergency == 0) {
            return 0
        };

        let now = clock::timestamp_ms(clock);
        let cooldown_end = cooldown.last_emergency + EMERGENCY_COOLDOWN;
        
        if (now >= cooldown_end) {
            0
        } else {
            cooldown_end - now
        }
    }

    /// Get emergency signatures count
    public fun get_emergency_signatures_count(proposal: &EmergencyProposal): u64 {
        vector::length(&proposal.signatures)
    }

    /// Check if emergency proposal is executed
    public fun is_emergency_executed(proposal: &EmergencyProposal): bool {
        proposal.executed
    }

    // ==================== Test Helper Functions ====================

    #[test_only]
    public fun create_cooldown_for_testing(treasury_id: ID, ctx: &mut TxContext): EmergencyCooldown {
        EmergencyCooldown {
            id: object::new(ctx),
            treasury_id,
            last_emergency: 0,
        }
    }

    #[test_only]
    public fun destroy_cooldown_for_testing(cooldown: EmergencyCooldown) {
        let EmergencyCooldown {
            id,
            treasury_id: _,
            last_emergency: _,
        } = cooldown;
        
        object::delete(id);
    }
}
