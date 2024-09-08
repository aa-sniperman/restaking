#[test_only]
module restaking::rewards_tests {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset};
  use aptos_framework::object;
  use aptos_framework::timestamp;
  use aptos_framework::primary_fungible_store;

  use aptos_std::comparator;

  use std::signer;
  use std::vector;

  use restaking::test_helpers;
  use restaking::avs_manager;
  use restaking::staker_manager;
  use restaking::package_manager;

  #[test(deployer = @0xcafe, staker = @0x53af, avs = @0xab12, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_avs_create_rewards_submissions(deployer: &signer, ra: &signer, avs: &signer, staker: &signer){
    test_helpers::set_up(deployer, ra);
    
    let avs_addr = signer::address_of(avs);
    let staked_amount = 1000;
    let staked_fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", staked_amount);

    let staked_token = fungible_asset::asset_metadata(&staked_fa);

    staker_manager::deposit(staker, staked_token, staked_fa);

    let rewarded_amount = 1000;
    let rewarded_fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Reward 1", rewarded_amount);

    let rewarded_token = fungible_asset::asset_metadata(&rewarded_fa);

    let avs_token_store = primary_fungible_store::ensure_primary_store_exists(avs_addr, rewarded_token);

    fungible_asset::deposit(avs_token_store, rewarded_fa);

    avs_manager::create_avs_rewards_submission_for_test(
      avs,
      vector[staked_token],
      vector[1],
      rewarded_token,
      rewarded_amount,
      timestamp::now_seconds(),
      25 * 3600
    );

    let treasury_signer = package_manager::get_signer();
    let treasury = signer::address_of(&treasury_signer);

    let treasury_store = primary_fungible_store::ensure_primary_store_exists(treasury, rewarded_token);
    assert!(fungible_asset::balance(treasury_store) == rewarded_amount, 0);

    let rewarded_for_all_amount = 1000;
    let rewarded_for_all_fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Reward 2", rewarded_for_all_amount);

    let rewarded_for_all_token = fungible_asset::asset_metadata(&rewarded_for_all_fa);

    let avs_token_for_all_store = primary_fungible_store::ensure_primary_store_exists(avs_addr, rewarded_for_all_token);

    fungible_asset::deposit(avs_token_for_all_store, rewarded_for_all_fa);

    avs_manager::create_avs_rewards_for_all_submission_for_test(
      avs,
      vector[staked_token],
      vector[1],
      rewarded_for_all_token,
      rewarded_for_all_amount,
      timestamp::now_seconds(),
      25 * 3600
    );

    let treasury_for_all_store = primary_fungible_store::ensure_primary_store_exists(treasury, rewarded_for_all_token);
    assert!(fungible_asset::balance(treasury_for_all_store) == rewarded_for_all_amount, 0);

  }
}