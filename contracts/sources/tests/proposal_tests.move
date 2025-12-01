#[test_only]
module treasury::proposal_tests {
    use sui::test_scenario::{Self as ts};
    use sui::clock::{Self, Clock};
    use treasury::treasury::{Self, Treasury};
    use treasury::proposal::{Self, Proposal};
    use std::vector;
    use std::string;

    const ADMIN: address = @0xAD;
    const SIGNER1: address = @0xA1;
    const SIGNER2: address = @0xA2;
    const SIGNER3: address = @0xA3;

    #[test]
    fun test_create_proposal() {
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

        // Create proposal
        ts::next_tx(&mut scenario, SIGNER1);
        {
            let treasury = ts::take_shared<Treasury>(&scenario);
            
            let mut transactions = vector::empty();
            let tx = proposal::create_transaction(
                ADMIN,
                1000000,
                b"0x2::sui::SUI"
            );
            vector::push_back(&mut transactions, tx);

            proposal::create_proposal(
                &treasury,
                transactions,
                b"Test proposal",
                0, // Category: Operations
                86400000, // 24 hour time-lock
                &clock,
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(treasury);
        };

        // Verify proposal was created
        ts::next_tx(&mut scenario, SIGNER1);
        {
            let proposal = ts::take_shared<Proposal>(&scenario);
            
            assert!(proposal::get_status(&proposal) == 0, 0); // STATUS_CREATED
            assert!(proposal::get_category(&proposal) == 0, 1);
            assert!(proposal::get_signatures_count(&proposal) == 0, 2);
            
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_sign_proposal() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Setup treasury and proposal
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

        ts::next_tx(&mut scenario, SIGNER1);
        {
            let treasury = ts::take_shared<Treasury>(&scenario);
            
            let mut transactions = vector::empty();
            let tx = proposal::create_transaction(ADMIN, 1000000, b"0x2::sui::SUI");
            vector::push_back(&mut transactions, tx);

            proposal::create_proposal(
                &treasury,
                transactions,
                b"Test proposal",
                0,
                86400000,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(treasury);
        };

        // Sign proposal (first signature)
        ts::next_tx(&mut scenario, SIGNER1);
        {
            let mut proposal = ts::take_shared<Proposal>(&scenario);
            let treasury = ts::take_shared<Treasury>(&scenario);
            
            let signature = vector[1, 2, 3, 4]; // Mock signature
            proposal::sign_proposal(
                &mut proposal,
                &treasury,
                signature,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            assert!(proposal::get_signatures_count(&proposal) == 1, 0);
            assert!(proposal::get_status(&proposal) == 1, 1); // STATUS_SIGNED
            
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        // Sign proposal (second signature - meets threshold)
        ts::next_tx(&mut scenario, SIGNER2);
        {
            let mut proposal = ts::take_shared<Proposal>(&scenario);
            let treasury = ts::take_shared<Treasury>(&scenario);
            
            let signature = vector[5, 6, 7, 8]; // Mock signature
            proposal::sign_proposal(
                &mut proposal,
                &treasury,
                signature,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            assert!(proposal::get_signatures_count(&proposal) == 2, 0);
            assert!(proposal::get_status(&proposal) == 2, 1); // STATUS_EXECUTABLE
            
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = proposal::E_ALREADY_SIGNED)]
    fun test_sign_proposal_twice() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // Setup
        {
            let signers = vector[SIGNER1, SIGNER2];
            treasury::create_treasury(
                signers,
                2,
                vector::empty(),
                0,
                &clock,
                ts::ctx(&mut scenario)
            );
        };

        ts::next_tx(&mut scenario, SIGNER1);
        {
            let treasury = ts::take_shared<Treasury>(&scenario);
            let mut transactions = vector::empty();
            let tx = proposal::create_transaction(ADMIN, 1000, b"0x2::sui::SUI");
            vector::push_back(&mut transactions, tx);

            proposal::create_proposal(
                &treasury,
                transactions,
                b"Test",
                0,
                1000,
                &clock,
                ts::ctx(&mut scenario)
            );
            ts::return_shared(treasury);
        };

        // Sign once
        ts::next_tx(&mut scenario, SIGNER1);
        {
            let mut proposal = ts::take_shared<Proposal>(&scenario);
            let treasury = ts::take_shared<Treasury>(&scenario);
            
            proposal::sign_proposal(
                &mut proposal,
                &treasury,
                vector[1, 2, 3],
                &clock,
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        // Try to sign again (should fail)
        ts::next_tx(&mut scenario, SIGNER1);
        {
            let mut proposal = ts::take_shared<Proposal>(&scenario);
            let treasury = ts::take_shared<Treasury>(&scenario);
            
            proposal::sign_proposal(
                &mut proposal,
                &treasury,
                vector[4, 5, 6],
                &clock,
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(proposal);
            ts::return_shared(treasury);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test]
    fun test_calculate_total_amount() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        {
            let signers = vector[SIGNER1, SIGNER2];
            treasury::create_treasury(
                signers,
                2,
                vector::empty(),
                0,
                &clock,
                ts::ctx(&mut scenario)
            );
        };

        ts::next_tx(&mut scenario, SIGNER1);
        {
            let treasury = ts::take_shared<Treasury>(&scenario);
            
            let mut transactions = vector::empty();
            vector::push_back(&mut transactions, proposal::create_transaction(ADMIN, 1000, b"0x2::sui::SUI"));
            vector::push_back(&mut transactions, proposal::create_transaction(ADMIN, 2000, b"0x2::sui::SUI"));
            vector::push_back(&mut transactions, proposal::create_transaction(ADMIN, 3000, b"0x2::sui::SUI"));

            proposal::create_proposal(
                &treasury,
                transactions,
                b"Multi-tx proposal",
                0,
                1000,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(treasury);
        };

        ts::next_tx(&mut scenario, SIGNER1);
        {
            let proposal = ts::take_shared<Proposal>(&scenario);
            
            let total = proposal::calculate_total_amount(&proposal);
            assert!(total == 6000, 0);
            
            ts::return_shared(proposal);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}
