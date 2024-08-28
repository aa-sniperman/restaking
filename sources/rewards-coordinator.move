module restaking::rewards_coordinator{
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Metadata,
  };
  use aptos_framework::object::{Self, Object};
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_std::simple_map::{Self, SimpleMap};
  use aptos_std::smart_vector::{Self, SmartVector};
  use std::string;
  use std::bcs;
  use std::vector;
  use std::signer;
  
  use restaking::package_manager;
  
  const REWARDS_COORDINATOR_NAME: vector<u8> = b"REWARDS_COORDINATOR";


  struct RewardsSubmission has drop, store {
    tokens: vector<Object<Metadata>>,
    multipliers: vector<u64>,
    rewarded_token: Object<Metadata>,
    rewarded_amount: u64,
    start_time: u64,
    duration: u64,
  }

  struct DistributionRoot has drop, store {
    root: u256,
    rewards_calculation_end_time: u64,
    activated_at: u64,
    disabled: bool,
  }

  struct EarnerMerkleTreeLeaf has drop, store {
    earner: address,
    earner_token_root: vector<u8>
  }

  struct TokenTreeMerkleLeaf has drop, store {
    token: Object<Metadata>,
    cummulative_earnings: u256
  }

  struct RewardsMerkleClaim {
    root_index: u32,
    earner_index: u32,
    earner_tree_proof: vector<vector<u8>>,
    earner_leaf: EarnerMerkleTreeLeaf,
    token_indices: vector<u32>,
    token_tree_proofs: vector<vector<u8>>,
    token_leaves: vector<TokenTreeMerkleLeaf>,
  }

  struct RewardsCoordinatorConfigs has key {
    signer_cap: SignerCapability,
    rewards_updater: address,
    activation_delay: u64,
    current_rewards_calculation_end_time: u64,
    global_operator_commission_bips: u16,
    distribution_roots: SmartVector<DistributionRoot>,
    rewards_for_all_submitter: SmartVector<address>,
  }

  #[event]
  struct AVSRewardsSubmissionCreated has drop, store {
    avs: address,
    submission_nonce: u256,
    rewards_submission_hash: u256,
    rewards_submission: RewardsSubmission,
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
  struct ClaimerForSet has drop, store {
    earner: address,
    old_claimer: address,
    claimer: address,
  }

  #[event]
  struct DistributionRootSubmitted has drop, store {
    root_index: u32,
    root: u256,
    rewards_calculation_end_time: u64,
    activated_at: u64
  }

  #[event]
  struct DistributionRootDisabled has drop, store {
    root_index: u32
  }

  #[event]
  struct RewardsClaimed has drop, store {
    root: u256,
    earner: address,
    claimer: address,
    recipient: address,
    token: Object<Metadata>,
    claimed_amount: u64
  }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        let staking_signer = &package_manager::get_signer();
        let (rewards_coordinator_signer, signer_cap) = account::create_resource_account(staking_signer, REWARDS_COORDINATOR_NAME);
        package_manager::add_address(string::utf8(REWARDS_COORDINATOR_NAME), signer::address_of(&rewards_coordinator_signer));
        move_to(&rewards_coordinator_signer, RewardsCoordinatorConfigs {
            signer_cap,
            rewards_updater: @0x0,
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
}