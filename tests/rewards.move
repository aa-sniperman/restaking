#[test_only]
module restaking::rewards_tests {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
  use aptos_framework::object::{Object};
  use aptos_framework::timestamp;
  use aptos_framework::primary_fungible_store;

  use aptos_std::comparator;

  use std::signer;
  use std::vector;
  use std::debug;

  use restaking::test_helpers;
  use restaking::avs_manager;
  use restaking::staker_manager;
  use restaking::earner_manager;
  use restaking::package_manager;
  use restaking::rewards_coordinator;
  use restaking::delegation_tests;
  use restaking::math_utils;

  #[test(deployer = @0xcafe, staker = @0x53af, avs = @0xab12, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_avs_create_rewards_submissions(deployer: &signer, ra: &signer, avs: &signer, staker: &signer){
    test_helpers::set_up(deployer, ra);
    
    let avs_addr = signer::address_of(avs);
    let staked_amount = 1000;
    let staked_fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", staked_amount);

    let staked_token = fungible_asset::asset_metadata(&staked_fa);

    delegation_tests::deposit_into_pool(staker, staked_fa);

    let rewarded_amount = 1000;
    let rewarded_fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Reward 1", rewarded_amount);

    let rewarded_token = fungible_asset::asset_metadata(&rewarded_fa);

    create_avs_rewards_submission(
      avs,
      vector[staked_token],
      vector[1],
      rewarded_fa,
      25 * 3600
    );

    let treasury_signer = package_manager::get_signer();
    let treasury = signer::address_of(&treasury_signer);

    let treasury_store = primary_fungible_store::ensure_primary_store_exists(treasury, rewarded_token);
    assert!(fungible_asset::balance(treasury_store) == rewarded_amount, 0);

    let rewarded_for_all_amount = 1000;
    let rewarded_for_all_fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Reward 2", rewarded_for_all_amount);

    let rewarded_for_all_token = fungible_asset::asset_metadata(&rewarded_for_all_fa);

    create_avs_rewards_for_all_submission(
      avs,
      vector[staked_token],
      vector[1],
      rewarded_for_all_fa,
      25 * 3600
    );

    let treasury_for_all_store = primary_fungible_store::ensure_primary_store_exists(treasury, rewarded_for_all_token);
    assert!(fungible_asset::balance(treasury_for_all_store) == rewarded_for_all_amount, 0);

  }

  #[test(deployer = @0xcafe, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_submit_root(deployer: &signer, ra: &signer){
    test_helpers::set_up(deployer, ra);
    let root_bytes = vector<u8>[
      240,  47, 223, 182, 233, 180, 130,
      92, 171,  45, 252, 183, 234, 179,
      173, 128, 249, 250,   3, 103, 139,
      188,  70, 165,  90, 171, 153, 232,
      157, 132,  91, 168
    ];
    let root = math_utils::bytes32_to_u256(root_bytes);

    let actual_root_bytes = math_utils::u256_to_bytes32(root);
    assert!(comparator::is_equal(&comparator::compare_u8_vector(root_bytes, actual_root_bytes)), 1);

    timestamp::fast_forward_seconds(100);
    let rewards_calculation_end_time = timestamp::now_seconds() - 1;
    rewards_coordinator::submit_root(deployer, root, rewards_calculation_end_time);
  }

  #[test(deployer = @0xcafe, staker = @0x34162865fa, claimer = @0x34162865fa, avs = @0xab12, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_submit_and_self_claim(deployer: &signer, ra: &signer, avs: &signer, staker: &signer, claimer: &signer){
    test_helpers::set_up(deployer, ra);
    let token = submit_and_claim(deployer, ra, avs, staker, claimer);
    let cummulative_claimed = earner_manager::cummulative_claimed(signer::address_of(staker), token);
    assert!(cummulative_claimed == 1000, 0);
  }

  #[test(deployer = @0xcafe, staker = @0x34162865fa, claimer = @0xc1ae, avs = @0xab12, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_set_claimer_submit_and_claim(deployer: &signer, ra: &signer, avs: &signer, staker: &signer, claimer: &signer){
    test_helpers::set_up(deployer, ra);
    earner_manager::set_claimer_for(staker, signer::address_of(claimer));
    let token = submit_and_claim(deployer, ra, avs, staker, claimer);
    let cummulative_claimed = earner_manager::cummulative_claimed(signer::address_of(staker), token);
    assert!(cummulative_claimed == 1000, 0);
  }

  public fun submit_and_claim(deployer: &signer, ra: &signer, avs: &signer, staker: &signer, claimer: &signer): Object<Metadata>{

    // submit rewards
    let rewarded_amount = 1000;

    let rewarded_fa = test_helpers::create_fungible_asset_and_mint(deployer, b"Token 1", rewarded_amount);

    let rewarded_token = fungible_asset::asset_metadata(&rewarded_fa);

    create_avs_rewards_submission(
      avs,
      vector[rewarded_token],
      vector[1],
      rewarded_fa,
      25 * 3600
    );

    // submit root
    let root_bytes = vector<u8>[
      240,  47, 223, 182, 233, 180, 130,
      92, 171,  45, 252, 183, 234, 179,
      173, 128, 249, 250,   3, 103, 139,
      188,  70, 165,  90, 171, 153, 232,
      157, 132,  91, 168
    ];
    let root = math_utils::bytes32_to_u256(root_bytes);

    timestamp::fast_forward_seconds(100);
    let rewards_calculation_end_time = timestamp::now_seconds() - 1;
    rewards_coordinator::submit_root(deployer, root, rewards_calculation_end_time);

    // create claim
    let cummulative_earnings = 1000u64;

    let token_leaf = test_helpers::calculate_token_leaf_hash(rewarded_token, cummulative_earnings);
  
    let token_index = 2u32;
    let token_proof = vector<u8>[
      112, 137, 187,  16,  74, 149, 187,   1, 254,  76, 201,
      37, 136, 245, 164, 229, 183,  36, 227,  73, 139, 155,
      67,  36,  85,  93,  45,  80, 204, 206, 200,  61,  49,
      178, 232, 160,  30,  18, 225,  68,  10, 205, 180, 139,
      2, 169, 134, 176,  15, 119, 227,  40, 109, 130,  29,
      215, 101, 127, 199, 199,  57, 171, 172, 114
    ];

    let token_root = vector<u8>[
      3,  49,  26,  37, 139, 239, 224, 244,
      103, 189, 225, 158,  85, 238,  21,  67,
      52, 187, 194,  20, 132,  93,   0,   6,
      89, 169,  68, 176,  84, 153, 144, 195
    ];

    let earner = signer::address_of(staker);

    let earner_leaf = test_helpers::calculate_earner_leaf_hash(earner, token_root);

    let earner_index = 3;

    let earner_proof = vector<u8>[
      162, 184, 188, 164, 152,  16, 100, 214,  33, 197, 201,  47,
      242, 181, 125, 177,  38, 248,  19, 123,  39, 227,   2, 255,
      4,  79,  24, 131,  25,   8, 167,  54, 237, 128,  35, 189,
      169, 143, 171, 225,  90, 143, 188, 194, 207,  13,  47, 103,
      239, 161, 168, 182, 152, 163, 164, 111,   1, 106, 161, 240,
      25,  76, 170, 214,  89,  37, 215, 219,  40,  14, 240, 146,
      41, 127,  82, 185, 248,  77,  91, 195,  50, 124, 173, 231,
      95, 140, 101, 112,  19, 198, 134,  16, 127,  24,  30,  89
    ];

    rewards_coordinator::process_claim(
      claimer,
      signer::address_of(claimer),
      0,
      earner_index,
      earner_proof,
      earner,
      token_root,
      vector[token_index],
      vector[token_proof],
      vector[rewarded_token],
      vector[cummulative_earnings]
    );

    rewarded_token
  }

  public fun create_avs_rewards_submission(
    avs: &signer,     
    tokens: vector<Object<Metadata>>,
    multipliers: vector<u64>, 
    rewarded_fa: FungibleAsset,
    duration: u64
  ){
    let start_time = timestamp::now_seconds();
    let rewarded_token = fungible_asset::asset_metadata(&rewarded_fa);
    let rewarded_amount = fungible_asset::amount(&rewarded_fa);

    let avs_token_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(avs), rewarded_token);

    fungible_asset::deposit(avs_token_store, rewarded_fa);

    avs_manager::create_avs_rewards_submission(
      avs,
      tokens,
      multipliers,
      rewarded_token,
      rewarded_amount,
      start_time,
      duration
    );
  }

  public fun create_avs_rewards_for_all_submission(
    avs: &signer,     
    tokens: vector<Object<Metadata>>,
    multipliers: vector<u64>, 
    rewarded_fa: FungibleAsset,
    duration: u64
  ){
    let start_time = timestamp::now_seconds();
    let rewarded_token = fungible_asset::asset_metadata(&rewarded_fa);
    let rewarded_amount = fungible_asset::amount(&rewarded_fa);

    let avs_token_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(avs), rewarded_token);

    fungible_asset::deposit(avs_token_store, rewarded_fa);
    
    avs_manager::create_avs_rewards_for_all_submission(
      avs,
      tokens,
      multipliers,
      rewarded_token,
      rewarded_amount,
      start_time,
      duration
    );
  }
}