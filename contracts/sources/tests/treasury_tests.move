#[test_only]
module treasury::treasury_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use treasury::treasury::{Self, Treasury, TreasuryAdminCap};
    use std::vector;

    const ADMIN: address = @0xAD;
    const SIGNER1: address = @0xA1;
    const SIGNER2: address = @0xA2;
    const SIGNER3: address = @0xA3;

    #[test]
    fun test_create_treasury() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Create treasury
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let emergency_signers = vector[SIGNER1, SIGNER2];
            
            treasury::create_treasury(
                signers,
                2,
                emergency_signers,
                2,
                &clock,
                ts::ctx(&mut scenario)
            );
        };

        // Verify treasury was created
        ts::next_tx(&mut scenario, ADMIN);
        {
            let treasury = ts::take_shared<Treasury>(&scenario);
            assert!(treasury::get_threshold(&treasury) == 2, 0);
            assert!(vector::length(&treasury::get_signers(&treasury)) == 3, 1);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = treasury::E_INVALID_THRESHOLD)]
    fun test_create_treasury_invalid_threshold() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Try to create treasury with threshold > signers
        {
            let signers = vector[SIGNER1, SIGNER2];
            let emergency_signers = vector::empty();
            
            treasury::create_treasury(
                signers,
                5, // Invalid threshold
                emergency_signers,
                0,
                &clock,
                ts::ctx(&mut scenario)
            );
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_deposit() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Create treasury
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            treasury::create_treasury(
                signers,
                2,
                vector::empty(),
                0,
                &clock,
                ts::ctx(&mut scenario)
            );
        };

        // Deposit coins
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut treasury = ts::take_shared<Treasury>(&scenario);
            let coin = coin::mint_for_testing<SUI>(1000000, ts::ctx(&mut scenario));
            
            treasury::deposit(&mut treasury, coin, ts::ctx(&mut scenario));
            
            // Verify balance
            assert!(treasury::get_balance<SUI>(&treasury) == 1000000, 0);
            
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_is_signer() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            treasury::create_treasury(
                signers,
                2,
                vector::empty(),
                0,
                &clock,
                ts::ctx(&mut scenario)
            );
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let treasury = ts::take_shared<Treasury>(&scenario);
            
            assert!(treasury::is_signer(&treasury, SIGNER1), 0);
            assert!(treasury::is_signer(&treasury, SIGNER2), 1);
            assert!(!treasury::is_signer(&treasury, ADMIN), 2);
            
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_freeze_treasury() {
        let mut scenario = ts::begin(SIGNER1);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Create treasury with emergency signers
        {
            let signers = vector[SIGNER1, SIGNER2, SIGNER3];
            let emergency_signers = vector[SIGNER1, SIGNER2];
            
            treasury::create_treasury(
                signers,
                2,
                emergency_signers,
                2,
                &clock,
                ts::ctx(&mut scenario)
            );
        };

        // Freeze treasury
        ts::next_tx(&mut scenario, SIGNER1);
        {
            let mut treasury = ts::take_shared<Treasury>(&scenario);
            
            treasury::freeze_treasury(&mut treasury, &clock, ts::ctx(&mut scenario));
            assert!(treasury::is_frozen(&treasury), 0);
            
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
