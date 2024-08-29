module restaking::avs_manager{
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Self, Metadata,
  };
  use aptos_framework::object::{Self, Object};
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_framework::timestamp;
  use aptos_framework::primary_fungible_store;

  use aptos_std::simple_map::{Self, SimpleMap};
  use aptos_std::aptos_hash;
  use aptos_std::comparator;
  
  use std::string;
  use std::bcs;
  use std::vector;
  use std::signer;

  use restaking::package_manager;
  use restaking::math_utils;

  const AVS_MANAGER_NAME: vector<u8> = b"AVS_MANAGER_NAME";
  const AVS_PREFIX: vector<u8> = b"AVS_PREFIX";

  const MAX_REWARDS_DURATION: u64 = 7 * 24 * 3600;
  const MAX_RETROACTIVE_DURATION: u64 = 24 * 3600;
  const MAX_FUTURE_LENGTH: u64 = 24 * 3600;
  const CALCULATION_INTERVAL_SECONDS: u64 = 10 * 60;

  const ENO_TOKENS: u64 = 501;
  const EINVALID_DURATION: u64 = 503;
  const EINVALID_START_TIME: u64 = 504;
  const EINVALID_TIME_RANGE: u64 = 505;
  const EINVALID_TOKENS_ORDER: u64 = 506;
  const EINVALID_REWARDS_AMOUNT: u64 = 507;
  const EINVALID_INPUT_LENGTH_MISMATCH: u64 = 508;


  struct RewardsSubmission has copy, drop, store {
    tokens: vector<Object<Metadata>>,
    multipliers: vector<u64>,
    rewarded_token: Object<Metadata>,
    rewarded_amount: u64,
    start_time: u64,
    duration: u64,
  }

  struct AVSStore has key {
    operator_registration: SimpleMap<address, bool>,
    rewards_submission_nonce: u256,
    rewards_submission_hash_submitted: SimpleMap<u256, bool>,
    rewards_submission_for_all_hash_submitted: SimpleMap<u256, bool>,
  }

  struct AVSManagerConfigs has key {
    signer_cap: SignerCapability,
  }

  #[event]
  struct AVSRewardsSubmissionCreated has drop, store {
    avs: address,
    submission_nonce: u256,
    rewards_submission_hash: u256,
    rewards_submission: RewardsSubmission,
  }

  #[event]
  struct AVSRewardsSubmissionForAllCreated has drop, store {
    avs: address,
    submission_nonce: u256,
    rewards_submission_for_all_hash: u256,
    rewards_submission: RewardsSubmission,
  }

  /// Create the share account to host all the avs & operator shares.
  public entry fun initialize() {
    if (is_initialized()) {
      return
    };

    // derive a resource account from signer to manage User share Account
    let staking_signer = &package_manager::get_signer();
    let (avs_manager_signer, signer_cap) = account::create_resource_account(staking_signer, AVS_MANAGER_NAME);
    package_manager::add_address(string::utf8(AVS_MANAGER_NAME), signer::address_of(&avs_manager_signer));
    move_to(&avs_manager_signer, AVSManagerConfigs {
      signer_cap,
    });
  }

  #[view]
  public fun is_initialized(): bool{
    package_manager::address_exists(string::utf8(AVS_MANAGER_NAME))
  }

  public entry fun create_avs_rewards_for_all_submissions(sender: &signer, rewards_submissions: vector<RewardsSubmission>) acquires AVSStore {
    vector::for_each_ref(&rewards_submissions, |submission| create_avs_rewards_for_all_submission(sender, submission));
  }
  public entry fun create_avs_rewards_submissions(sender: &signer, rewards_submissions: vector<RewardsSubmission>) acquires AVSStore {
    vector::for_each_ref(&rewards_submissions, |submission| create_avs_rewards_submission(sender, submission));
  }

  fun create_avs_rewards_submission(sender: &signer, rewards_submission: &RewardsSubmission) acquires AVSStore {
    let avs = signer::address_of(sender);
    let store = mut_avs_store(avs);
    let nonce = store.rewards_submission_nonce;
    let submission_hash = rewards_submission_hash(avs, nonce, rewards_submission);
    validate_rewards_submission(rewards_submission);
    simple_map::upsert(&mut store.rewards_submission_hash_submitted, submission_hash, true);
    store.rewards_submission_nonce = nonce + 1;

    let treasury = signer::address_of(&package_manager::get_signer());
    // transfer token to this address
    let token_store = primary_fungible_store::ensure_primary_store_exists(treasury, rewards_submission.rewarded_token);
    
    let in = primary_fungible_store::withdraw(sender, rewards_submission.rewarded_token, rewards_submission.rewarded_amount);
    fungible_asset::deposit(token_store, in);

    event::emit(AVSRewardsSubmissionCreated {
      avs,
      submission_nonce: nonce,
      rewards_submission_hash: submission_hash,
      rewards_submission: *rewards_submission
    });
  }

  fun create_avs_rewards_for_all_submission(sender: &signer, rewards_submission: &RewardsSubmission) acquires AVSStore {
    let avs = signer::address_of(sender);
    let store = mut_avs_store(avs);
    let nonce = store.rewards_submission_nonce;
    let submission_hash = rewards_submission_hash(avs, nonce, rewards_submission);
    validate_rewards_submission(rewards_submission);
    simple_map::upsert(&mut store.rewards_submission_for_all_hash_submitted, submission_hash, true);
    store.rewards_submission_nonce = nonce + 1;

    let treasury = signer::address_of(&package_manager::get_signer());
    // transfer token to this address
    let token_store = primary_fungible_store::ensure_primary_store_exists(treasury, rewards_submission.rewarded_token);
    
    let in = primary_fungible_store::withdraw(sender, rewards_submission.rewarded_token, rewards_submission.rewarded_amount);
    fungible_asset::deposit(token_store, in);

    event::emit(AVSRewardsSubmissionForAllCreated {
      avs,
      submission_nonce: nonce,
      rewards_submission_for_all_hash: submission_hash,
      rewards_submission: *rewards_submission
    });
  }

  fun rewards_submission_hash(avs: address, nonce: u256, rewards_submission: &RewardsSubmission): u256{
    let bytes = bcs::to_bytes(&avs);
    vector::append(&mut bytes, bcs::to_bytes(&nonce));
    vector::append(&mut bytes, bcs::to_bytes(rewards_submission));

    math_utils::bytes32_to_u256(aptos_hash::keccak256(bytes))
  }

  fun validate_rewards_submission(rewards_submission: &RewardsSubmission) {
    assert!(rewards_submission.rewarded_amount > 0, EINVALID_REWARDS_AMOUNT);
    assert!(rewards_submission.duration <= MAX_REWARDS_DURATION, EINVALID_DURATION);
    assert!(rewards_submission.duration % CALCULATION_INTERVAL_SECONDS == 0, EINVALID_DURATION);
    assert!(rewards_submission.start_time % CALCULATION_INTERVAL_SECONDS == 0, EINVALID_DURATION);

    let now = timestamp::now_seconds();

    assert!(rewards_submission.start_time + MAX_RETROACTIVE_DURATION >= now, EINVALID_START_TIME);
    assert!(rewards_submission.start_time <= now + MAX_FUTURE_LENGTH, EINVALID_START_TIME);

    let tokens_length = vector::length(&rewards_submission.tokens);
    assert!(tokens_length > 0, ENO_TOKENS);
    assert!(tokens_length == vector::length(&rewards_submission.multipliers), EINVALID_INPUT_LENGTH_MISMATCH);
    
    let cur_address = @0x0;
    let idx = 0;
    while(idx < tokens_length){
      let token = vector::borrow(&rewards_submission.tokens, idx);
      let token_addr = object::object_address(token);
      assert!(comparator::is_smaller_than(&comparator::compare(&cur_address, &token_addr)), EINVALID_TOKENS_ORDER);
      idx = idx + 1;
    };

  }

  fun create_avs_store(avs: address){
    let avs_manager_signer = avs_manager_signer();
    let ctor = &object::create_named_object(avs_manager_signer, avs_store_seeds(avs));
    let avs_store_signer = object::generate_signer(ctor);
    move_to(&avs_store_signer, AVSStore {
      operator_registration: simple_map::new(),
      rewards_submission_nonce: 0,
      rewards_submission_hash_submitted: simple_map::new(),
      rewards_submission_for_all_hash_submitted: simple_map::new(),
    });
  }

  inline fun avs_store_address(avs: address): address {
    object::create_object_address(&avs_manager_address(), avs_store_seeds(avs))
  }

  inline fun avs_manager_address(): address {
    package_manager::get_address(string::utf8(AVS_MANAGER_NAME))
  }

  inline fun avs_manager_signer(): &signer acquires AVSManagerConfigs{
    &account::create_signer_with_capability(&borrow_global<AVSManagerConfigs>(avs_manager_address()).signer_cap)
  }

  inline fun avs_store_seeds(avs: address): vector<u8>{
    let seeds = vector<u8>[];
    vector::append(&mut seeds, AVS_PREFIX);
    vector::append(&mut seeds, bcs::to_bytes(&avs));
    seeds
  }

  inline fun avs_store(avs: address): &AVSStore acquires AVSStore {
    borrow_global<AVSStore>(avs_store_address(avs))
  }

  inline fun mut_avs_store(avs: address): &mut AVSStore acquires AVSStore {
    borrow_global_mut<AVSStore>(avs_store_address(avs))
  }
}