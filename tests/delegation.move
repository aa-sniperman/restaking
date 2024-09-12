#[test_only]
module restaking::delegation_tests {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset};
  use aptos_framework::object;
  use aptos_framework::timestamp;
  use aptos_framework::primary_fungible_store;

  use aptos_std::comparator;

  use std::signer;
  use std::vector;

  use restaking::staking_pool;
  use restaking::staker_manager;
  use restaking::operator_manager;
  use restaking::slasher;
  use restaking::withdrawal;
  use restaking::test_helpers;

  #[test(deployer = @0xcafe, staker = @0xab12, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_add_shares(deployer: &signer, ra: &signer, staker: &signer){

    let staker_addr = signer::address_of(staker);

    test_helpers::set_up(deployer, ra);

    let amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", amount);
    let token = fungible_asset::asset_metadata(&fa);
    staker_manager::add_shares(staker_addr, token, (amount as u128));

    assert!(staker_manager::staker_store_exists(staker_addr), 3);

    let (staked_tokens, staked_shares) = staker_manager::staker_nonormalized_shares(staker_addr);
    assert!(vector::length(&staked_tokens) == 1, 0);
    let expected_token = *vector::borrow(&staked_tokens, 0);
    assert!(object::object_address(&expected_token) == object::object_address(&token), 1);
    let expected_shares = *vector::borrow(&staked_shares, 0);
    assert!(expected_shares == (amount as u128), 2);
    


    let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
    fungible_asset::deposit(store, fa);
  }

  #[test(deployer = @0xcafe, staker = @0xab12, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_remove_shares(deployer: &signer, ra: &signer, staker: &signer){

    let staker_addr = signer::address_of(staker);

    test_helpers::set_up(deployer, ra);

    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", 1000);
    let token = fungible_asset::asset_metadata(&fa);

    let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
    fungible_asset::deposit(store, fa);

    let shares_to_add = 1000u128;

    staker_manager::add_shares(staker_addr, token, shares_to_add);

    let shares_to_remove = 500u128;

    staker_manager::remove_shares(staker_addr, token, shares_to_remove);

    let (tokens_1, shares_1) = staker_manager::staker_nonormalized_shares(staker_addr);
    assert!(vector::length(&tokens_1) == 1, 0);

    let expected_shares_1 = *vector::borrow(&shares_1, 0);
    assert!(expected_shares_1 == shares_to_add - shares_to_remove, 2);
    
    staker_manager::remove_shares(staker_addr, token, shares_to_remove);
    let (tokens_2, shares_2) = staker_manager::staker_nonormalized_shares(staker_addr);
    assert!(vector::length(&tokens_2) == 1, 0);
    let expected_shares_2 = *vector::borrow(&shares_2, 0);
    assert!(expected_shares_2 == 0, 2);
  }

  #[test(deployer = @0xcafe, staker = @0xab12, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_deposit(deployer: &signer, ra: &signer, staker: &signer){

    let staker_addr = signer::address_of(staker);

    test_helpers::set_up(deployer, ra);

    let deposit_amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", deposit_amount);
    let token = fungible_asset::asset_metadata(&fa);
    
    deposit_into_pool(staker, fa);

    let (staked_tokens, staked_shares) = staker_manager::staker_nonormalized_shares(staker_addr);
    assert!(vector::length(&staked_tokens) == 1, 0);
    let expected_token = *vector::borrow(&staked_tokens, 0);
    assert!(object::object_address(&expected_token) == object::object_address(&token), 1);
    let expected_shares = *vector::borrow(&staked_shares, 0);
    assert!(expected_shares == (deposit_amount as u128), 2);

    let staker_token_shares = staker_manager::staker_token_shares(
      staker_addr,
      token
    );

    assert!(staker_token_shares == (deposit_amount as u128), 2);

    let pool = staking_pool::ensure_staking_pool(token);
    let total_shares = staking_pool::total_shares(pool);
    assert!(total_shares == (deposit_amount as u128), 1);
  }

  #[test(deployer = @0xcafe, staker = @0xab12, operator = @0x7878, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_delegate(deployer: &signer, ra: &signer, staker: &signer, operator: &signer){

    let staker_addr = signer::address_of(staker);
    let operator_addr = signer::address_of(operator);

    test_helpers::set_up(deployer, ra);

    let deposit_amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", deposit_amount);
    let token = fungible_asset::asset_metadata(&fa);

    deposit_into_pool(staker, fa);

    staker_manager::delegate(operator, operator_addr);

    assert!(staker_manager::delegate_of(operator_addr) == operator_addr, 0);
    assert!(staker_manager::is_operator(operator_addr), 0);

    staker_manager::delegate(staker, operator_addr);
    assert!(staker_manager::delegate_of(staker_addr) == operator_addr, 0);

    let staker_token_shares = staker_manager::staker_token_shares(
      staker_addr,
      token
    );

    assert!(staker_token_shares == (deposit_amount as u128), 2);

    let operator_token_shares = operator_manager::operator_token_shares(
      operator_addr,
      token
    );

    assert!(operator_token_shares == (deposit_amount as u128), 2);
  }

  #[test(deployer = @0xcafe, staker = @0xab12, operator = @0x7878, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_undelegate(deployer: &signer, ra: &signer, staker: &signer, operator: &signer){

    let staker_addr = signer::address_of(staker);
    let operator_addr = signer::address_of(operator);

    test_helpers::set_up(deployer, ra);

    let deposit_amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", deposit_amount);
    let token = fungible_asset::asset_metadata(&fa);

    deposit_into_pool(staker, fa);

    staker_manager::delegate(operator, operator_addr);

    assert!(staker_manager::delegate_of(operator_addr) == operator_addr, 0);
    assert!(staker_manager::is_operator(operator_addr), 0);

    staker_manager::delegate(staker, operator_addr);
    assert!(staker_manager::delegate_of(staker_addr) == operator_addr, 0);

    let operator_token_shares = operator_manager::operator_token_shares(
      operator_addr,
      token
    );

    assert!(operator_token_shares == (deposit_amount as u128), 2);

    staker_manager::undelegate(staker, staker_addr);

    assert!(staker_manager::delegate_of(staker_addr) == @0x0, 0);

    operator_manager::decrease_operator_shares(operator_addr, staker_addr, token, (deposit_amount as u128));
    
    let operator_token_shares_after = operator_manager::operator_token_shares(
      operator_addr,
      token
    );

    assert!(operator_token_shares_after == 0, 2);
  }

  #[test(deployer = @0xcafe, staker = @0xab12, operator = @0x7878, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_queue_withdrawal(deployer: &signer, ra: &signer, staker: &signer, operator: &signer){

    let staker_addr = signer::address_of(staker);
    let operator_addr = signer::address_of(operator);

    test_helpers::set_up(deployer, ra);

    let deposit_amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", deposit_amount);
    let token = fungible_asset::asset_metadata(&fa);

    deposit_into_pool(staker, fa);

    staker_manager::delegate(operator, operator_addr);

    staker_manager::delegate(staker, operator_addr);

    let operator_token_shares = operator_manager::operator_token_shares(
      operator_addr,
      token
    );

    assert!(operator_token_shares == (deposit_amount as u128), 2);

    let withdrawal_delay = withdrawal::withdrawal_delay(vector[token]);
    assert!(withdrawal_delay == 24 * 3600, 0);

    let withdrawn_amount = 500u128;
    withdrawal::queue_withdrawal(
      staker,
      vector[token],
      vector[withdrawn_amount]
    );

    let staker_nonce_after = staker_manager::cummulative_withdrawals_queued(staker_addr);
    assert!(staker_nonce_after == 1, 0);

    let staker_shares_after = staker_manager::staker_token_shares(staker_addr, token);
    assert!(staker_shares_after == 500, 0);

    let operator_shares_after = operator_manager::operator_token_shares(operator_addr, token);
    assert!(operator_shares_after == 500, 0);
  }

  #[test(deployer = @0xcafe, staker = @0xab12, operator = @0x7878, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_complete_queued_withdrawal(deployer: &signer, ra: &signer, staker: &signer, operator: &signer){

    let staker_addr = signer::address_of(staker);
    let operator_addr = signer::address_of(operator);

    test_helpers::set_up(deployer, ra);

    let deposit_amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", deposit_amount);
    let token = fungible_asset::asset_metadata(&fa);

    deposit_into_pool(staker, fa);

    staker_manager::delegate(operator, operator_addr);

    staker_manager::delegate(staker, operator_addr);

    let operator_token_shares = operator_manager::operator_token_shares(
      operator_addr,
      token
    );

    assert!(operator_token_shares == (deposit_amount as u128), 2);

    let withdrawal_delay = withdrawal::withdrawal_delay(vector[token]);
    assert!(withdrawal_delay == 24 * 3600, 0);

    let withdrawn_amount = 500u128;
    let (
      queued_staker,
      queued_operator,
      queued_withdrawer,
      queued_nonce,
      queued_start_time
    ) = withdrawal::queue_withdrawal_for_test(
      staker,
      vector[token],
      vector[withdrawn_amount]
    );

    assert!(queued_staker == staker_addr, 0);
    assert!(queued_operator == operator_addr, 0);
    assert!(queued_withdrawer == staker_addr, 0);
    assert!(queued_nonce == 0, 0);
    
    timestamp::fast_forward_seconds(withdrawal_delay + 10);

    
    withdrawal::complete_queued_withdrawal(
      staker,
      queued_staker,
      queued_operator,
      queued_withdrawer,
      queued_nonce,
      queued_start_time,
      vector[token],
      vector[withdrawn_amount],
      true
    );

    let staker_store_after = primary_fungible_store::ensure_primary_store_exists(staker_addr, token);
    assert!(fungible_asset::balance(staker_store_after) == 500, 0);
  }

  #[test(deployer = @0xcafe, staker = @0xab12, operator = @0x7878, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  #[expected_failure(abort_code = 303)]
  public fun test_failed_complete_queued_withdrawal(deployer: &signer, ra: &signer, staker: &signer, operator: &signer){

    let staker_addr = signer::address_of(staker);
    let operator_addr = signer::address_of(operator);

    test_helpers::set_up(deployer, ra);

    let deposit_amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", deposit_amount);
    let token = fungible_asset::asset_metadata(&fa);

    deposit_into_pool(staker, fa);

    staker_manager::delegate(operator, operator_addr);

    staker_manager::delegate(staker, operator_addr);

    let operator_token_shares = operator_manager::operator_token_shares(
      operator_addr,
      token
    );

    assert!(operator_token_shares == (deposit_amount as u128), 2);

    let withdrawal_delay = withdrawal::withdrawal_delay(vector[token]);
    assert!(withdrawal_delay == 24 * 3600, 0);

    let withdrawn_amount = 500u128;
    let (
      queued_staker,
      queued_operator,
      queued_withdrawer,
      queued_nonce,
      queued_start_time
    ) = withdrawal::queue_withdrawal_for_test(
      staker,
      vector[token],
      vector[withdrawn_amount]
    );

    assert!(queued_staker == staker_addr, 0);
    assert!(queued_operator == operator_addr, 0);
    assert!(queued_withdrawer == staker_addr, 0);
    assert!(queued_nonce == 0, 0);
    
    timestamp::fast_forward_seconds(withdrawal_delay - 100);

    
    withdrawal::complete_queued_withdrawal(
      staker,
      queued_staker,
      queued_operator,
      queued_withdrawer,
      queued_nonce,
      queued_start_time,
      vector[token],
      vector[withdrawn_amount],
      true
    );
  }

  #[test(deployer = @0xcafe, staker = @0xab12, operator = @0x7878, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_undelegate_via_withdrawal(deployer: &signer, ra: &signer, staker: &signer, operator: &signer){

    let staker_addr = signer::address_of(staker);
    let operator_addr = signer::address_of(operator);

    test_helpers::set_up(deployer, ra);

    let deposit_amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", deposit_amount);
    let token = fungible_asset::asset_metadata(&fa);

    deposit_into_pool(staker, fa);

    staker_manager::delegate(operator, operator_addr);

    staker_manager::delegate(staker, operator_addr);

    let operator_token_shares = operator_manager::operator_token_shares(
      operator_addr,
      token
    );

    assert!(operator_token_shares == (deposit_amount as u128), 2);

    let withdrawal_delay = withdrawal::withdrawal_delay(vector[token]);
    assert!(withdrawal_delay == 24 * 3600, 0);

    withdrawal::undelegate(
      staker,
      staker_addr
    );

    assert!(staker_manager::delegate_of(staker_addr) == @0x0, 1);

    let staker_nonce_after = staker_manager::cummulative_withdrawals_queued(staker_addr);
    assert!(staker_nonce_after == 1, 0);

    let staker_shares_after = staker_manager::staker_token_shares(staker_addr, token);
    assert!(staker_shares_after == 0, 0);

    let operator_shares_after = operator_manager::operator_token_shares(operator_addr, token);
    assert!(operator_shares_after == 0, 0);
  }

  public fun deposit_into_pool(staker: &signer, fa: FungibleAsset){
    let token = fungible_asset::asset_metadata(&fa);
    let amount = fungible_asset::amount(&fa);
    let staker_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(staker), token);
    fungible_asset::deposit(staker_store, fa);
    staker_manager::stake_asset_entry(staker, token, amount);
  }
}