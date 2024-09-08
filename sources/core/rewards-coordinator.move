module restaking::rewards_coordinator{
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Metadata, Self,
  };
  use aptos_framework::object::{Object};
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_framework::timestamp;
  use aptos_framework::primary_fungible_store;


  use aptos_std::aptos_hash;
  use aptos_std::smart_vector::{Self, SmartVector};
  use std::string;
  use std::bcs;
  use std::vector;
  use std::signer;
  
  use restaking::merkle_tree;
  use restaking::math_utils;
  use restaking::earner_manager;
  use restaking::package_manager;
  
  const REWARDS_COORDINATOR_NAME: vector<u8> = b"REWARDS_COORDINATOR";

  const EINVALID_LEAF_INDEX: u64 = 701;
  const EINVALID_TOKEN_CLAIM_PROOF: u64 = 702;
  const EINVALID_EARNER_CLAIM_PROOF: u64 = 703;
  const EROOT_DISABLED: u64 = 704;
  const EROOT_NOT_ACTIVATED_YET: u64 = 705;
  const ECLAIM_INPUT_LENGTH_MISMATCH: u64 = 706;
  const ENOT_CLAIMER: u64 = 707;
  const ECUM_EARNINGS_NOT_GREATER_THAN_CUM_CLAIMED: u64 = 708;
  const ENOT_REWARDS_UPDATER: u64 = 709;
  const ENOT_NEW_CALC_END_TIME: u64 = 710;
  const EFUTURE_CALC_END_TIME: u64 = 711;
  const EINVALID_ROOT_INDEX: u64 = 712;
  const EROOT_ALREADY_DISABLED: u64 = 713;
  const EROOT_ALREADY_ACTIVATED: u64 = 714;

  struct EarnerMerkleTreeLeaf has copy, drop, store {
    earner: address,
    earner_token_root: vector<u8>
  }

  struct TokenTreeMerkleLeaf has copy, drop, store {
    token: Object<Metadata>,
    cummulative_earnings: u64
  }

  struct RewardsMerkleClaim has copy, drop, store {
    root_index: u64,
    earner_index: u32,
    earner_tree_proof: vector<u8>,
    earner_leaf: EarnerMerkleTreeLeaf,
    token_indices: vector<u32>,
    token_tree_proofs: vector<vector<u8>>,
    token_leaves: vector<TokenTreeMerkleLeaf>,
  }

  struct DistributionRoot has copy, drop, store {
    root: u256,
    rewards_calculation_end_time: u64,
    activated_at: u64,
    disabled: bool,
  }

  struct RewardsConfigs has key {
    signer_cap: SignerCapability,
    rewards_updater: address,
    activation_delay: u64,
    current_rewards_calculation_end_time: u64,
    global_operator_commission_bips: u16,
    distribution_roots: SmartVector<DistributionRoot>,
    rewards_for_all_submitter: SmartVector<address>,
  }

  #[event]
  struct RewardsUpdaterSet has drop, store{
    old_rewards_updater: address,
    new_rewards_updater: address,
  }

  #[event]
  struct RewardsForAllSubmitterSet has drop, store{
    rewards_for_all_submitter: address,
    old_value: bool,
    new_value: bool
  }

  #[event]
  struct ActivationDelaySet has drop, store {
    old_activation_delay: u64,
    new_activation_delay: u64,
  }

  #[event]
  struct GlobalCommissionBipsSet has drop, store {
    old_global_commisions_bips: u16,
    new_global_commisions_bips: u16
  }

  #[event]
  struct DistributionRootSubmitted has drop, store {
    root_index: u64,
    root: u256,
    rewards_calculation_end_time: u64,
    activated_at: u64
  }

  #[event]
  struct DistributionRootDisabled has drop, store {
    root_index: u64
  }

  #[event]
  struct RewardsClaimed has drop, store {
    root: u256,
    earner: address,
    claimer: address,
    recipient: address,
    token: Object<Metadata>,
    claim_amount: u64
  }

  public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        let staking_signer = &package_manager::get_signer();
        let (rewards_coordinator_signer, signer_cap) = account::create_resource_account(staking_signer, REWARDS_COORDINATOR_NAME);
        package_manager::add_address(string::utf8(REWARDS_COORDINATOR_NAME), signer::address_of(&rewards_coordinator_signer));
        move_to(&rewards_coordinator_signer, RewardsConfigs {
            signer_cap,
            rewards_updater: @deployer,
            activation_delay: 0,
            current_rewards_calculation_end_time: 0,
            global_operator_commission_bips: 100,
            distribution_roots: smart_vector::new(),
            rewards_for_all_submitter: smart_vector::new(),
        });
    }

    #[view]
    public fun is_initialized(): bool {
        package_manager::address_exists(string::utf8(REWARDS_COORDINATOR_NAME))
    }

  public fun process_claim(
    sender: &signer,
    claim: RewardsMerkleClaim,
    recipient: address
  ) acquires RewardsConfigs{
    let configs = mut_rewards_configs();
    let root = smart_vector::borrow(&configs.distribution_roots, claim.root_index);
    check_claim(claim, *root);
    let earner = claim.earner_leaf.earner;
    let claimer = earner_manager::claimer_of(earner);
    assert!(signer::address_of(sender) == claimer, ENOT_CLAIMER);

    let treasury_signer = &package_manager::get_signer();
    let treasury = signer::address_of(treasury_signer);

    let tokens_length = vector::length(&claim.token_indices);
    let idx = 0;
    while(idx < tokens_length){
      let token_leaf = vector::borrow(&claim.token_leaves, idx);
      let curr_cummulative_claimed = earner_manager::cummulative_claimed(earner, token_leaf.token);
      assert!(curr_cummulative_claimed < token_leaf.cummulative_earnings, ECUM_EARNINGS_NOT_GREATER_THAN_CUM_CLAIMED);
      let claim_amount = token_leaf.cummulative_earnings - curr_cummulative_claimed;
      earner_manager::set_cummulative_claimed(earner, token_leaf.token, claim_amount);

      let from = primary_fungible_store::ensure_primary_store_exists(treasury, token_leaf.token);
      let to = primary_fungible_store::ensure_primary_store_exists(recipient, token_leaf.token);

      fungible_asset::transfer(treasury_signer, from, to, claim_amount);

      event::emit(RewardsClaimed {
        root: root.root,
        earner,
        claimer,
        recipient,
        token: token_leaf.token,
        claim_amount
      });
      idx = idx + 1;
    };
  }

  public entry fun submit_root(
    sender: &signer,
    root: u256,
    rewards_calculation_end_time: u64
  ) acquires RewardsConfigs {
    let configs = mut_rewards_configs();
    assert!(signer::address_of(sender) == configs.rewards_updater, ENOT_REWARDS_UPDATER);
    assert!(rewards_calculation_end_time > configs.current_rewards_calculation_end_time, ENOT_NEW_CALC_END_TIME);
    
    let now = timestamp::now_seconds();
    
    assert!(rewards_calculation_end_time < now, EFUTURE_CALC_END_TIME);
    let root_index = smart_vector::length(&configs.distribution_roots);
    let activated_at = now + configs.activation_delay;

    smart_vector::push_back(&mut configs.distribution_roots, DistributionRoot {
      root,
      activated_at,
      rewards_calculation_end_time,
      disabled: false
    });

    configs.current_rewards_calculation_end_time = rewards_calculation_end_time;
    event::emit(DistributionRootSubmitted {
      root_index,
      root,
      rewards_calculation_end_time,
      activated_at
    });
  }

  public entry fun disable_root(
    sender: &signer,
    root_index: u64
  ) acquires RewardsConfigs {
    let configs = mut_rewards_configs();
    assert!(signer::address_of(sender) == configs.rewards_updater, ENOT_REWARDS_UPDATER);
    assert!(root_index < smart_vector::length(&configs.distribution_roots), EINVALID_ROOT_INDEX);
    let root = smart_vector::borrow_mut(&mut configs.distribution_roots, root_index);
    assert!(!root.disabled, EROOT_ALREADY_DISABLED);
    let now = timestamp::now_seconds();
    assert!(now < root.activated_at, EROOT_ALREADY_ACTIVATED);
    root.disabled = true;
    event::emit(DistributionRootDisabled {
      root_index
    });
  }

  fun check_claim(claim: RewardsMerkleClaim, root: DistributionRoot){
    assert!(!root.disabled, EROOT_DISABLED);
    assert!(timestamp::now_seconds() >= root.activated_at, EROOT_NOT_ACTIVATED_YET);
    let tokens_length = vector::length(&claim.token_indices);
    assert!(tokens_length == vector::length(&claim.token_tree_proofs), ECLAIM_INPUT_LENGTH_MISMATCH);
    assert!(tokens_length == vector::length(&claim.token_leaves), ECLAIM_INPUT_LENGTH_MISMATCH);
    verify_earner_claim_proof(
      math_utils::u256_to_bytes32(root.root),
      claim.earner_index,
      claim.earner_tree_proof,
      claim.earner_leaf
    );
    let token_index = 0;
    while(token_index < tokens_length){
      verify_token_claim_proof(
        claim.earner_leaf.earner_token_root,
        *vector::borrow(&claim.token_indices, token_index),
        *vector::borrow(&claim.token_tree_proofs, token_index),
        *vector::borrow(&claim.token_leaves, token_index)
      );
      token_index = token_index + 1;
    };
  }
  fun verify_token_claim_proof(
    earner_token_root: vector<u8>,
    token_leaf_index: u32,
    token_proof: vector<u8>,
    token_leaf: TokenTreeMerkleLeaf
  ) {
    let proof_length = vector::length(&token_proof);
    assert!(token_leaf_index < (1 << ((proof_length / 32) as u8)), EINVALID_LEAF_INDEX);
    let token_leaf_hash = aptos_hash::keccak256(bcs::to_bytes(&token_leaf));
    assert!(merkle_tree::verify_inclusion_keccak(token_proof, token_leaf_hash, token_leaf_index, earner_token_root), EINVALID_TOKEN_CLAIM_PROOF);
  }

  fun verify_earner_claim_proof(
    root: vector<u8>,
    earner_leaf_index: u32,
    earner_proof: vector<u8>,
    earner_leaf: EarnerMerkleTreeLeaf
  ) {
    let proof_length = vector::length(&earner_proof);
    assert!(earner_leaf_index < (1 << ((proof_length / 32) as u8)), EINVALID_LEAF_INDEX);
    let earner_leaf_hash = aptos_hash::keccak256(bcs::to_bytes(&earner_leaf));
    assert!(merkle_tree::verify_inclusion_keccak(earner_proof, earner_leaf_hash, earner_leaf_index, root), EINVALID_TOKEN_CLAIM_PROOF);
  }

  inline fun rewards_coordinator_address(): address {
    package_manager::get_address(string::utf8(REWARDS_COORDINATOR_NAME))
  }

  inline fun rewards_configs(): &RewardsConfigs acquires RewardsConfigs{
    borrow_global<RewardsConfigs>(rewards_coordinator_address())
  }

  inline fun mut_rewards_configs(): &mut RewardsConfigs acquires RewardsConfigs {
    borrow_global_mut<RewardsConfigs>(rewards_coordinator_address())
  }

  // Operators
  public entry fun set_rewards_updater(sender: &signer, new_rewards_updater: address) acquires RewardsConfigs {
    let sender_addr = signer::address_of(sender);
    let configs = mut_rewards_configs();
    assert!(configs.rewards_updater == sender_addr, ENOT_REWARDS_UPDATER);
    configs.rewards_updater = new_rewards_updater;
    event::emit(RewardsUpdaterSet {
      old_rewards_updater: sender_addr,
      new_rewards_updater
    });
  }

  #[test_only]
  friend restaking::rewards_tests;
}