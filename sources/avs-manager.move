module restaking::avs_manager{
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Metadata,
  };
  use aptos_framework::object::{Self, Object};
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_std::simple_map::{Self, SimpleMap};
  use std::string;
  use std::bcs;
  use std::vector;
  use std::signer;

  use restaking::package_manager;

  const AVS_MANAGER_NAME: vector<u8> = b"AVS_MANAGER_NAME";
  const AVS_PREFIX: vector<u8> = b"AVS_PREFIX";

  struct AVSStore has key {
    operator_registration: SimpleMap<address, bool>,
    rewards_submission_nonce: u256,
    rewards_submission_hash_submitted: SimpleMap<u256, bool>,
    rewards_submission_for_all_hash_submitted: SimpleMap<u256, bool>,
  }

  struct AVSManagerConfigs{
    signer_cap: SignerCapability,
  }

  /// Create the share account to host all the staker & operator shares.
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
}