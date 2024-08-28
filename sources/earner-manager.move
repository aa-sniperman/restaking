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

  struct EarnerManagerConfigs has key{
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

  fun create_earner_store(earner: address){
    let earner_manager_signer = earner_manager_signer();
    let ctor = &object::create_named_object(earner_manager_signer, earner_store_seeds(earner));
    let earner_store_signer = object::generate_signer(ctor);
    move_to(&earner_store_signer, EarnerStore {
      claimer_for: @0x0,
      cummulative_claimed: simple_map::new(),
    });
  }

  inline fun earner_store_address(earner: address): address {
    object::create_object_address(&earner_manager_address(), earner_store_seeds(earner))
  }

  inline fun earner_manager_address(): address {
    package_manager::get_address(string::utf8(EARNER_MANAGER_NAME))
  }

  inline fun earner_manager_signer(): &signer acquires EarnerManagerConfigs{
    &account::create_signer_with_capability(&borrow_global<EarnerManagerConfigs>(earner_manager_address()).signer_cap)
  }

  inline fun earner_store_seeds(earner: address): vector<u8>{
    let seeds = vector<u8>[];
    vector::append(&mut seeds, EARNER_PREFIX);
    vector::append(&mut seeds, bcs::to_bytes(&earner));
    seeds
  }

  inline fun earner_store(earner: address): &EarnerStore acquires EarnerStore {
    borrow_global<EarnerStore>(earner_store_address(earner))
  }

  inline fun mut_earner_store(earner: address): &mut EarnerStore acquires EarnerStore {
    borrow_global_mut<EarnerStore>(earner_store_address(earner))
  }
}