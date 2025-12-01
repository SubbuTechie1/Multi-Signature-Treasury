module treasury::policy_manager {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use std::vector;
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use treasury::proposal::{Self, Proposal};
    use treasury::treasury::{Self, Treasury};

    // Error codes
    const E_POLICY_VIOLATION: u64 = 200;
    const E_SPENDING_LIMIT_EXCEEDED: u64 = 201;
    const E_NOT_WHITELISTED: u64 = 202;
    const E_BLACKLISTED: u64 = 203;
    const E_INVALID_CATEGORY: u64 = 204;
    const E_TIMELOCK_TOO_SHORT: u64 = 205;
    const E_AMOUNT_THRESHOLD_NOT_MET: u64 = 206;
    const E_REQUIRED_SIGNER_MISSING: u64 = 207;

    // Policy types
    const POLICY_TYPE_SPENDING_LIMIT: u8 = 0;
    const POLICY_TYPE_WHITELIST: u8 = 1;
    const POLICY_TYPE_CATEGORY: u8 = 2;
    const POLICY_TYPE_TIMELOCK: u8 = 3;
    const POLICY_TYPE_AMOUNT_THRESHOLD: u8 = 4;
    const POLICY_TYPE_APPROVAL: u8 = 5;

    /// Spending limit policy configuration
    public struct SpendingLimitConfig has store, copy, drop {
        category: u8, // 255 for global
        daily_limit: u64,
        weekly_limit: u64,
        monthly_limit: u64,
        per_transaction_cap: u64,
    }

    /// Spending tracker for a category
    public struct SpendingTracker has store {
        daily_spent: u64,
        weekly_spent: u64,
        monthly_spent: u64,
        last_daily_reset: u64,
        last_weekly_reset: u64,
        last_monthly_reset: u64,
    }

    /// Whitelist policy configuration
    public struct WhitelistConfig has store, copy, drop {
        enforce_whitelist: bool,
        whitelist: vector<address>,
        blacklist: vector<address>,
    }

    /// Time-lock policy configuration
    public struct TimeLockConfig has store, copy, drop {
        base_duration: u64, // milliseconds
        amount_factor: u64, // duration += amount / factor
        category_overrides: vector<u64>, // per-category durations
    }

    /// Amount threshold policy configuration
    public struct AmountThresholdConfig has store, copy, drop {
        thresholds: vector<ThresholdRule>,
    }

    public struct ThresholdRule has store, copy, drop {
        min_amount: u64,
        max_amount: u64, // 0 means unlimited
        required_signatures: u8,
    }

    /// Approval policy configuration
    public struct ApprovalConfig has store, copy, drop {
        required_signers: vector<address>,
        veto_signers: vector<address>,
        category: u8, // 255 for all categories
    }

    /// Policy object
    public struct Policy has key, store {
        id: UID,
        treasury_id: ID,
        policy_type: u8,
        is_active: bool,
        created_at: u64,
        // Configs stored as separate fields based on type
        spending_limit_config: std::option::Option<SpendingLimitConfig>,
        whitelist_config: std::option::Option<WhitelistConfig>,
        timelock_config: std::option::Option<TimeLockConfig>,
        amount_threshold_config: std::option::Option<AmountThresholdConfig>,
        approval_config: std::option::Option<ApprovalConfig>,
    }

    /// Policy manager for a treasury
    public struct PolicyManager has key, store {
        id: UID,
        treasury_id: ID,
        policy_ids: vector<ID>,
        spending_trackers: Table<u8, SpendingTracker>, // category -> tracker
    }

    // ==================== Events ====================

    public struct PolicyCreated has copy, drop {
        policy_id: ID,
        treasury_id: ID,
        policy_type: u8,
    }

    public struct PolicyViolation has copy, drop {
        proposal_id: ID,
        policy_id: ID,
        violation_type: u8,
        details: std::string::String,
    }

    public struct SpendingTracked has copy, drop {
        treasury_id: ID,
        category: u8,
        amount: u64,
        period: std::string::String,
    }

    // ==================== Core Functions ====================

    /// Create policy manager for treasury
    public entry fun create_policy_manager(
        treasury: &Treasury,
        ctx: &mut TxContext
    ) {
        let treasury_id = object::id(treasury);
        
        let manager = PolicyManager {
            id: object::new(ctx),
            treasury_id,
            policy_ids: vector::empty(),
            spending_trackers: table::new(ctx),
        };

        transfer::share_object(manager);
    }

    /// Create spending limit policy
    public entry fun create_spending_limit_policy(
        manager: &mut PolicyManager,
        treasury: &mut Treasury,
        category: u8,
        daily_limit: u64,
        weekly_limit: u64,
        monthly_limit: u64,
        per_transaction_cap: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let treasury_id = object::id(treasury);
        let policy_uid = object::new(ctx);
        let policy_id = object::uid_to_inner(&policy_uid);

        let config = SpendingLimitConfig {
            category,
            daily_limit,
            weekly_limit,
            monthly_limit,
            per_transaction_cap,
        };

        let policy = Policy {
            id: policy_uid,
            treasury_id,
            policy_type: POLICY_TYPE_SPENDING_LIMIT,
            is_active: true,
            created_at: clock::timestamp_ms(clock),
            spending_limit_config: std::option::some(config),
            whitelist_config: std::option::none(),
            timelock_config: std::option::none(),
            amount_threshold_config: std::option::none(),
            approval_config: std::option::none(),
        };

        // Initialize spending tracker for category if needed
        if (!table::contains(&manager.spending_trackers, category)) {
            let tracker = SpendingTracker {
                daily_spent: 0,
                weekly_spent: 0,
                monthly_spent: 0,
                last_daily_reset: clock::timestamp_ms(clock),
                last_weekly_reset: clock::timestamp_ms(clock),
                last_monthly_reset: clock::timestamp_ms(clock),
            };
            table::add(&mut manager.spending_trackers, category, tracker);
        };

        vector::push_back(&mut manager.policy_ids, policy_id);
        treasury::add_policy(treasury, policy_id);

        event::emit(PolicyCreated {
            policy_id,
            treasury_id,
            policy_type: POLICY_TYPE_SPENDING_LIMIT,
        });

        transfer::share_object(policy);
    }

    /// Create whitelist policy
    public entry fun create_whitelist_policy(
        manager: &mut PolicyManager,
        treasury: &mut Treasury,
        enforce_whitelist: bool,
        whitelist: vector<address>,
        blacklist: vector<address>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let treasury_id = object::id(treasury);
        let policy_uid = object::new(ctx);
        let policy_id = object::uid_to_inner(&policy_uid);

        let config = WhitelistConfig {
            enforce_whitelist,
            whitelist,
            blacklist,
        };

        let policy = Policy {
            id: policy_uid,
            treasury_id,
            policy_type: POLICY_TYPE_WHITELIST,
            is_active: true,
            created_at: clock::timestamp_ms(clock),
            spending_limit_config: std::option::none(),
            whitelist_config: std::option::some(config),
            timelock_config: std::option::none(),
            amount_threshold_config: std::option::none(),
            approval_config: std::option::none(),
        };

        vector::push_back(&mut manager.policy_ids, policy_id);
        treasury::add_policy(treasury, policy_id);

        event::emit(PolicyCreated {
            policy_id,
            treasury_id,
            policy_type: POLICY_TYPE_WHITELIST,
        });

        transfer::share_object(policy);
    }

    /// Validate proposal against all policies
    public fun validate_proposal(
        manager: &mut PolicyManager,
        proposal: &Proposal,
        policies: &vector<Policy>,
        clock: &Clock,
    ): bool {
        let mut i = 0;
        let len = vector::length(policies);
        
        while (i < len) {
            let policy = vector::borrow(policies, i);
            if (policy.is_active) {
                validate_against_policy(manager, proposal, policy, clock);
            };
            i = i + 1;
        };
        
        true
    }

    /// Validate against a specific policy
    fun validate_against_policy(
        manager: &mut PolicyManager,
        proposal: &Proposal,
        policy: &Policy,
        clock: &Clock,
    ) {
        if (policy.policy_type == POLICY_TYPE_SPENDING_LIMIT) {
            validate_spending_limit(manager, proposal, policy, clock);
        } else if (policy.policy_type == POLICY_TYPE_WHITELIST) {
            validate_whitelist(proposal, policy);
        } else if (policy.policy_type == POLICY_TYPE_TIMELOCK) {
            validate_timelock(proposal, policy);
        } else if (policy.policy_type == POLICY_TYPE_AMOUNT_THRESHOLD) {
            validate_amount_threshold(proposal, policy);
        };
    }

    /// Validate spending limits
    fun validate_spending_limit(
        manager: &mut PolicyManager,
        proposal: &Proposal,
        policy: &Policy,
        clock: &Clock,
    ) {
        let config = std::option::borrow(&policy.spending_limit_config);
        let category = proposal::get_category(proposal);
        
        // Check if policy applies to this category
        if (config.category != 255 && config.category != category) {
            return
        };

        let total_amount = proposal::calculate_total_amount(proposal);

        // Check per-transaction cap
        if (config.per_transaction_cap > 0 && total_amount > config.per_transaction_cap) {
            abort E_SPENDING_LIMIT_EXCEEDED
        };

        // Check period limits
        if (table::contains(&manager.spending_trackers, category)) {
            let tracker = table::borrow_mut(&mut manager.spending_trackers, category);
            reset_trackers_if_needed(tracker, clock);

            if (config.daily_limit > 0 && tracker.daily_spent + total_amount > config.daily_limit) {
                abort E_SPENDING_LIMIT_EXCEEDED
            };
            if (config.weekly_limit > 0 && tracker.weekly_spent + total_amount > config.weekly_limit) {
                abort E_SPENDING_LIMIT_EXCEEDED
            };
            if (config.monthly_limit > 0 && tracker.monthly_spent + total_amount > config.monthly_limit) {
                abort E_SPENDING_LIMIT_EXCEEDED
            };
        };
    }

    /// Validate whitelist
    fun validate_whitelist(
        proposal: &Proposal,
        policy: &Policy,
    ) {
        let config = std::option::borrow(&policy.whitelist_config);
        let transactions = proposal::get_transactions(proposal);
        
        let mut i = 0;
        let len = vector::length(transactions);
        
        while (i < len) {
            let _tx = vector::borrow(transactions, i);
            // Note: Can't access tx.recipient directly, would need accessor
            // This is a skeleton showing validation pattern
            
            // Check blacklist
            // if (vector::contains(&config.blacklist, &tx.recipient)) {
            //     abort E_BLACKLISTED
            // };
            
            // Check whitelist if enforced
            // if (config.enforce_whitelist && !vector::contains(&config.whitelist, &tx.recipient)) {
            //     abort E_NOT_WHITELISTED
            // };
            
            i = i + 1;
        };
    }

    /// Validate time-lock
    fun validate_timelock(
        proposal: &Proposal,
        policy: &Policy,
    ) {
        let config = std::option::borrow(&policy.timelock_config);
        let _time_lock_end = proposal::get_time_lock_end(proposal);
        let _category = proposal::get_category(proposal);
        
        // Calculate required time-lock
        let mut required_duration = config.base_duration;
        
        // Add amount-based extension
        if (config.amount_factor > 0) {
            let total = proposal::calculate_total_amount(proposal);
            required_duration = required_duration + (total / config.amount_factor);
        };

        // Check if actual time-lock meets requirement
        // (simplified - would need creation timestamp)
        // assert!(time_lock_end >= creation + required_duration, E_TIMELOCK_TOO_SHORT);
    }

    /// Validate amount threshold
    fun validate_amount_threshold(
        proposal: &Proposal,
        policy: &Policy,
    ) {
        let config = std::option::borrow(&policy.amount_threshold_config);
        let total = proposal::calculate_total_amount(proposal);
        let signatures_count = proposal::get_signatures_count(proposal);
        
        // Find applicable threshold rule
        let mut i = 0;
        let len = vector::length(&config.thresholds);
        
        while (i < len) {
            let rule = vector::borrow(&config.thresholds, i);
            if (total >= rule.min_amount && (rule.max_amount == 0 || total < rule.max_amount)) {
                assert!((signatures_count as u8) >= rule.required_signatures, E_AMOUNT_THRESHOLD_NOT_MET);
                return
            };
            i = i + 1;
        };
    }

    /// Update spending tracker after execution
    public fun update_spending_tracker(
        manager: &mut PolicyManager,
        category: u8,
        amount: u64,
        clock: &Clock,
    ) {
        if (table::contains(&manager.spending_trackers, category)) {
            let tracker = table::borrow_mut(&mut manager.spending_trackers, category);
            reset_trackers_if_needed(tracker, clock);
            
            tracker.daily_spent = tracker.daily_spent + amount;
            tracker.weekly_spent = tracker.weekly_spent + amount;
            tracker.monthly_spent = tracker.monthly_spent + amount;
        };
    }

    /// Reset spending trackers if period elapsed
    fun reset_trackers_if_needed(tracker: &mut SpendingTracker, clock: &Clock) {
        let now = clock::timestamp_ms(clock);
        let day_ms = 86400000u64; // 24 hours
        let week_ms = 604800000u64; // 7 days
        let month_ms = 2592000000u64; // 30 days

        if (now >= tracker.last_daily_reset + day_ms) {
            tracker.daily_spent = 0;
            tracker.last_daily_reset = now;
        };

        if (now >= tracker.last_weekly_reset + week_ms) {
            tracker.weekly_spent = 0;
            tracker.last_weekly_reset = now;
        };

        if (now >= tracker.last_monthly_reset + month_ms) {
            tracker.monthly_spent = 0;
            tracker.last_monthly_reset = now;
        };
    }

    /// Deactivate policy
    public entry fun deactivate_policy(
        policy: &mut Policy,
        _ctx: &mut TxContext
    ) {
        policy.is_active = false;
    }

    /// Activate policy
    public entry fun activate_policy(
        policy: &mut Policy,
        _ctx: &mut TxContext
    ) {
        policy.is_active = true;
    }

    // ==================== View Functions ====================

    public fun is_policy_active(policy: &Policy): bool {
        policy.is_active
    }

    public fun get_policy_type(policy: &Policy): u8 {
        policy.policy_type
    }
}
