#[test_only]
module restaking::staking_pool_tests {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset};
  use aptos_framework::object;
  use aptos_framework::primary_fungible_store;

  use aptos_std::comparator;

  use std::signer;

  use restaking::staking_pool;
  use restaking::test_helpers;

  #[test(deployer = @0xcafe, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_can_create_staking_pool(deployer: &signer, ra: &signer){
    test_helpers::set_up(deployer, ra);
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", 1000);
    let token = fungible_asset::asset_metadata(&fa);
    let pool = staking_pool::ensure_staking_pool(token);
    let expected_token = staking_pool::token_metadata(pool);
    let token_addr = object::object_address(&token);
    let expected_token_addr = object::object_address(&expected_token);
    assert!(token_addr == expected_token_addr, 1);
    let store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(deployer), token);
    fungible_asset::deposit(store, fa);
  }

  #[test(deployer = @0xcafe, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_deposit_into_pool(deployer: &signer, ra: &signer){
    test_helpers::set_up(deployer, ra);
    let amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", amount);
    let token = fungible_asset::asset_metadata(&fa);
    let pool = staking_pool::ensure_staking_pool(token);
    let store = staking_pool::token_store(pool);
    fungible_asset::deposit(store, fa);
    let new_shares = staking_pool::deposit(pool, amount);
    assert!(new_shares == (amount as u128), 0);
    let total_shares = staking_pool::total_shares(pool);
    assert!(total_shares == (amount as u128), 1);
  }

  #[test(deployer = @0xcafe, recipient = @0xffee, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_withdraw_from_pool(deployer: &signer, ra: &signer, recipient: &signer){
    let recipient_addr = signer::address_of(recipient);
    test_helpers::set_up(deployer, ra);
    let amount = 1000;
    let fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", amount);
    let token = fungible_asset::asset_metadata(&fa);
    let pool = staking_pool::ensure_staking_pool(token);
    
    let pool_store = staking_pool::token_store(pool);
    fungible_asset::deposit(pool_store, fa);
    
    staking_pool::deposit(pool, amount);

    let withdrawal = 500u128;
    staking_pool::withdraw(recipient_addr, pool, withdrawal);

    let total_shares = staking_pool::total_shares(pool);
    assert!(total_shares == (amount as u128) - withdrawal, 0);

    let recipient_store = primary_fungible_store::ensure_primary_store_exists(recipient_addr, token);
    let recipient_balance = fungible_asset::balance(recipient_store); 
    assert!(recipient_balance == (withdrawal as u64), 1);

    let pool_store_after = staking_pool::token_store(pool);
    let pool_balance = fungible_asset::balance(pool_store_after);
    assert!(pool_balance == (amount - (withdrawal as u64)), 2);
  }
}