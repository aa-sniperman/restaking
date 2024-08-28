module restaking::earner_manager{
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

  const EARNER_MANAGER_NAME: vector<u8> = b"EARNER_MANAGER_NAME";
  const EARNER_PREFIX: vector<u8> = b"EARNER_PREFIX";

  struct EarnerStore has key {
    claimer_for: address,
    cummulative_claimed: SimpleMap<Object<Metadata>, u64>,
  }

  struct EarnerManagerConfigs{
    signer_cap: SignerCapability,
  }

  /// Create the share account to host all the staker & operator shares.
  public entry fun initialize() {
    if (is_initialized()) {
      return
    };

    // derive a resource account from signer to manage User share Account
    let staking_signer = &package_manager::get_signer();
    let (earner_manager_signer, signer_cap) = account::create_resource_account(staking_signer, EARNER_MANAGER_NAME);
    package_manager::add_address(string::utf8(EARNER_MANAGER_NAME), signer::address_of(&earner_manager_signer));
    move_to(&earner_manager_signer, EarnerManagerConfigs {
      signer_cap,
    });
  }

  #[view]
  public fun is_initialized(): bool{
    package_manager::address_exists(string::utf8(EARNER_MANAGER_NAME))
  }
}