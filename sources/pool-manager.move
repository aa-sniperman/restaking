module restaking::pool_manager {
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Self, FungibleAsset, FungibleStore, Metadata,
  };
  use aptos_framework::object::{Self, ConstructorRef, Object};
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_framework::primary_fungible_store;
  use aptos_std::simple_map::{Self, SimpleMap};
  use std::string::{Self, String};


  use std::vector;
  use std::signer;
  use restaking::package_manager;

  const POOL_MANAGER_NAME: vector<u8> = b"POOL_MANAGER";

  struct StakerShareKey has store {
    staker: address,
    token: Object<Metadata>,
  }

  struct PoolManagerConfigs has key {
    signer_cap: SignerCapability,
    staking_pools: SimpleMap<Object<Metadata>, Object<FungibleStore>>,
    staker_shares: SimpleMap<StakerShareKey, u64>,
    staker_pool_list: SimpleMap<address, vector<Object<Metadata>>>
  }

      /// Create the pool manager account to host all the staking pools.
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from swap signer to manage Wrapper Account
        let swap_signer = &package_manager::get_signer();
        let (pool_manager_signer, signer_cap) = account::create_resource_account(swap_signer, POOL_MANAGER_NAME);
        package_manager::add_address(string::utf8(POOL_MANAGER_NAME), signer::address_of(&pool_manager_signer));
        move_to(&pool_manager_signer, PoolManagerConfigs {
            signer_cap,
            staking_pools: simple_map::new(),
            staker_shares: simple_map::new(),
            staker_pool_list: simple_map::new(),
        });
    }

    #[view]
    public fun is_initialized(): bool {
        package_manager::address_exists(string::utf8(POOL_MANAGER_NAME))
    }


}