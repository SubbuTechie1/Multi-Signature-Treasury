module treasury::treasury {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    use std::vector;
    use sui::bag::{Self, Bag};
    use sui::clock::{Self, Clock};
    use std::type_name;

    // Error codes
    const E_INVALID_THRESHOLD: u64 = 1;
    const E_INVALID_SIGNERS: u64 = 2;
    const E_UNAUTHORIZED: u64 = 3;
    const E_TREASURY_FROZEN: u64 = 4;
    const E_INSUFFICIENT_BALANCE: u64 = 5;
    const E_INVALID_AMOUNT: u64 = 6;

    /// Main Treasury object holding funds and configuration
    public struct Treasury has key, store {
        id: UID,
        /// List of authorized signer addresses
        signers: vector<address>,
        /// Number of signatures required for normal operations
        threshold: u8,
        /// Emergency signers for critical operations
        emergency_signers: vector<address>,
        /// Emergency signature threshold
        emergency_threshold: u8,
        /// Multi-coin balances stored in a Bag
        balances: Bag,
        /// Policy IDs applied to this treasury
        policy_ids: vector<ID>,
        /// Treasury creation timestamp
        created_at: u64,
        /// Whether treasury is frozen (emergency state)
        is_frozen: bool,
    }

    /// Capability for treasury administration
    public struct TreasuryAdminCap has key, store {
        id: UID,
        treasury_id: ID,
    }

    // ==================== Events ====================

    public struct TreasuryCreated has copy, drop {
        treasury_id: ID,
        signers: vector<address>,
        threshold: u8,
        created_at: u64,
    }

    public struct FundsDeposited has copy, drop {
        treasury_id: ID,
        coin_type: std::ascii::String,
        amount: u64,
        depositor: address,
    }

    public struct TreasuryFrozen has copy, drop {
        treasury_id: ID,
        frozen_by: address,
        timestamp: u64,
    }

    public struct TreasuryUnfrozen has copy, drop {
        treasury_id: ID,
        unfrozen_by: address,
        timestamp: u64,
    }

    public struct SignersUpdated has copy, drop {
        treasury_id: ID,
        new_signers: vector<address>,
        new_threshold: u8,
    }

    // ==================== Core Functions ====================

    /// Create a new treasury with signers and threshold
    public entry fun create_treasury(
        signers: vector<address>,
        threshold: u8,
        emergency_signers: vector<address>,
        emergency_threshold: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validation
        let signers_count = vector::length(&signers);
        assert!(signers_count >= 2, E_INVALID_SIGNERS);
        assert!(threshold >= 2 && (threshold as u64) <= signers_count, E_INVALID_THRESHOLD);
        
        if (!vector::is_empty(&emergency_signers)) {
            let emergency_count = vector::length(&emergency_signers);
            assert!(
                emergency_threshold > 0 && (emergency_threshold as u64) <= emergency_count,
                E_INVALID_THRESHOLD
            );
        };

        let treasury_uid = object::new(ctx);
        let treasury_id = object::uid_to_inner(&treasury_uid);
        
        let treasury = Treasury {
            id: treasury_uid,
            signers,
            threshold,
            emergency_signers,
            emergency_threshold,
            balances: bag::new(ctx),
            policy_ids: vector::empty(),
            created_at: clock::timestamp_ms(clock),
            is_frozen: false,
        };

        // Create admin capability
        let admin_cap = TreasuryAdminCap {
            id: object::new(ctx),
            treasury_id,
        };

        event::emit(TreasuryCreated {
            treasury_id,
            signers: treasury.signers,
            threshold,
            created_at: treasury.created_at,
        });

        transfer::share_object(treasury);
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    /// Deposit coins into treasury
    public entry fun deposit<T>(
        treasury: &mut Treasury,
        coin: Coin<T>,
        ctx: &mut TxContext
    ) {
        assert!(!treasury.is_frozen, E_TREASURY_FROZEN);
        
        let amount = coin::value(&coin);
        let coin_type = type_name::get<T>();
        
        // Add or update balance
        if (bag::contains(&treasury.balances, coin_type)) {
            let existing_balance: &mut Balance<T> = bag::borrow_mut(&mut treasury.balances, coin_type);
            balance::join(existing_balance, coin::into_balance(coin));
        } else {
            bag::add(&mut treasury.balances, coin_type, coin::into_balance(coin));
        };

        event::emit(FundsDeposited {
            treasury_id: object::uid_to_inner(&treasury.id),
            coin_type: type_name::into_string(coin_type),
            amount,
            depositor: tx_context::sender(ctx),
        });
    }

    /// Get balance for specific coin type
    public fun get_balance<T>(treasury: &Treasury): u64 {
        let coin_type = type_name::get<T>();
        if (bag::contains(&treasury.balances, coin_type)) {
            let balance: &Balance<T> = bag::borrow(&treasury.balances, coin_type);
            balance::value(balance)
        } else {
            0
        }
    }

    /// Check if address is a signer
    public fun is_signer(treasury: &Treasury, addr: address): bool {
        vector::contains(&treasury.signers, &addr)
    }

    /// Check if address is emergency signer
    public fun is_emergency_signer(treasury: &Treasury, addr: address): bool {
        vector::contains(&treasury.emergency_signers, &addr)
    }

    /// Get treasury threshold
    public fun get_threshold(treasury: &Treasury): u8 {
        treasury.threshold
    }

    /// Get signers
    public fun get_signers(treasury: &Treasury): vector<address> {
        treasury.signers
    }

    /// Check if treasury is frozen
    public fun is_frozen(treasury: &Treasury): bool {
        treasury.is_frozen
    }

    /// Freeze treasury (emergency only)
    public entry fun freeze_treasury(
        treasury: &mut Treasury,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(is_emergency_signer(treasury, sender), E_UNAUTHORIZED);
        
        treasury.is_frozen = true;

        event::emit(TreasuryFrozen {
            treasury_id: object::uid_to_inner(&treasury.id),
            frozen_by: sender,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Unfreeze treasury (requires admin cap)
    public entry fun unfreeze_treasury(
        treasury: &mut Treasury,
        _admin_cap: &TreasuryAdminCap,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        treasury.is_frozen = false;

        event::emit(TreasuryUnfrozen {
            treasury_id: object::uid_to_inner(&treasury.id),
            unfrozen_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update signers (requires admin cap or multi-sig approval)
    public entry fun update_signers(
        treasury: &mut Treasury,
        _admin_cap: &TreasuryAdminCap,
        new_signers: vector<address>,
        new_threshold: u8,
    ) {
        let signers_count = vector::length(&new_signers);
        assert!(signers_count >= 2, E_INVALID_SIGNERS);
        assert!(new_threshold >= 2 && (new_threshold as u64) <= signers_count, E_INVALID_THRESHOLD);

        treasury.signers = new_signers;
        treasury.threshold = new_threshold;

        event::emit(SignersUpdated {
            treasury_id: object::uid_to_inner(&treasury.id),
            new_signers,
            new_threshold,
        });
    }

    /// Add policy to treasury
    public fun add_policy(treasury: &mut Treasury, policy_id: ID) {
        vector::push_back(&mut treasury.policy_ids, policy_id);
    }

    /// Remove policy from treasury
    public fun remove_policy(treasury: &mut Treasury, policy_id: ID) {
        let (exists, index) = vector::index_of(&treasury.policy_ids, &policy_id);
        if (exists) {
            vector::remove(&mut treasury.policy_ids, index);
        };
    }

    /// Get policy IDs
    public fun get_policy_ids(treasury: &Treasury): &vector<ID> {
        &treasury.policy_ids
    }

    /// Withdraw from treasury (called by proposal execution)
    public fun withdraw<T>(
        treasury: &mut Treasury,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        assert!(!treasury.is_frozen, E_TREASURY_FROZEN);
        assert!(amount > 0, E_INVALID_AMOUNT);

        let coin_type = type_name::get<T>();
        assert!(bag::contains(&treasury.balances, coin_type), E_INSUFFICIENT_BALANCE);

        let balance: &mut Balance<T> = bag::borrow_mut(&mut treasury.balances, coin_type);
        assert!(balance::value(balance) >= amount, E_INSUFFICIENT_BALANCE);

        coin::from_balance(balance::split(balance, amount), ctx)
    }

    // ==================== Test Helper Functions ====================

    #[test_only]
    public fun create_treasury_for_testing(
        signers: vector<address>,
        threshold: u8,
        ctx: &mut TxContext
    ): Treasury {
        let treasury_uid = object::new(ctx);
        
        Treasury {
            id: treasury_uid,
            signers,
            threshold,
            emergency_signers: vector::empty(),
            emergency_threshold: 0,
            balances: bag::new(ctx),
            policy_ids: vector::empty(),
            created_at: 0,
            is_frozen: false,
        }
    }

    #[test_only]
    public fun destroy_treasury_for_testing(treasury: Treasury) {
        let Treasury {
            id,
            signers: _,
            threshold: _,
            emergency_signers: _,
            emergency_threshold: _,
            balances,
            policy_ids: _,
            created_at: _,
            is_frozen: _,
        } = treasury;
        
        bag::destroy_empty(balances);
        object::delete(id);
    }
}
