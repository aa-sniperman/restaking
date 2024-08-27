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
  use std::bcs;
  use std::vector;
  use std::signer;
  use restaking::package_manager;

  use restaking::staking_pool::{Self, StakingPool};



  const POOL_MANAGER_NAME: vector<u8> = b"POOL_MANAGER";
  const MAX_STAKER_POOL_LIST_LENGTH: u64 = 100;

  const EMAX_STAKER_POOL_LIST_LENGTH_EXCEEDED: u64 = 101;

  struct StakerShareKey has drop, copy, store {
    staker: address,
    token: Object<Metadata>,
  }

  struct PoolManagerConfigs has key {
    signer_cap: SignerCapability,
    staker_shares: SimpleMap<StakerShareKey, u64>,
    staker_pool_list: SimpleMap<address, vector<Object<Metadata>>>
  }

  #[event]
  struct Deposit has drop, store {
    staker: address,
    token: Object<Metadata>,
    shares: u64,
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
            staker_shares: simple_map::new(),
            staker_pool_list: simple_map::new(),
        });
    }

    fun add_shares(staker: address, token: Object<Metadata>, shares: u64) acquires PoolManagerConfigs {
      let current_shares = mut_staker_token_shares(staker, token);
      let staker_pool_list = mut_staker_pool_list(staker);
      let current_list_length = vector::length(staker_pool_list);
      if(*current_shares == 0){
        assert!(current_list_length < MAX_STAKER_POOL_LIST_LENGTH, EMAX_STAKER_POOL_LIST_LENGTH_EXCEEDED);
        if(!vector::contains(staker_pool_list, &token)){
          vector::push_back(staker_pool_list, token);
        }
      };

      *current_shares = *current_shares + shares;

      event::emit(Deposit {
        staker, 
        token,
        shares
      })
    }

    // public entry fun deposit(staker: &signer, pool: Object<StakingPool>, asset: FungibleAsset) acquires PoolManagerConfigs{
    //   let token = fungible_asset::metadata_from_asset(&asset);
    //   let amount = fungible_asset::amount(&asset);
     

    // }

    #[view]
    public fun is_initialized(): bool {
      package_manager::address_exists(string::utf8(POOL_MANAGER_NAME))
    }
    #[view]
    /// Return the address of the resource account that stores pool manager configs.
    public fun pool_manager_address(): address {
      package_manager::get_address(string::utf8(POOL_MANAGER_NAME))
    }

    #[view]
    public fun staker_token_shares(staker: address, token: Object<Metadata>): u64 acquires PoolManagerConfigs {
      let staker_shares = &pool_manager_configs().staker_shares;
      
      let key = &StakerShareKey {
        staker,
        token
      };

      if (simple_map::contains_key(staker_shares, key)){
        *simple_map::borrow(staker_shares, key)
      } else {
        0
      }
    }

    inline fun mut_staker_token_shares(staker: address, token: Object<Metadata>): &mut u64 acquires PoolManagerConfigs {
      let staker_shares = mut_pool_manager_configs().staker_shares;
      
      let key = StakerShareKey {
        staker,
        token
      };

      if (!simple_map::contains_key(&mut staker_shares, &key)){
        simple_map::add(&mut staker_shares, key, 0)
      };

      simple_map::borrow_mut(&mut staker_shares, &key)
    }

    #[view] 
    public fun staker_pool_list(staker: address): vector<Object<Metadata>> acquires PoolManagerConfigs {
      let staker_pool_list_map = &pool_manager_configs().staker_pool_list;
      if(!simple_map::contains_key(staker_pool_list_map, &staker)){
        return vector<Object<Metadata>>[];
      };

      *simple_map::borrow(staker_pool_list_map, &staker)
    }

    inline fun mut_staker_pool_list(staker: address): &mut vector<Object<Metadata>> acquires PoolManagerConfigs {
      let staker_pool_list_map = &mut mut_pool_manager_configs().staker_pool_list;
      if(!simple_map::contains_key(staker_pool_list_map, &staker)){
        simple_map::add(staker_pool_list_map, staker, vector<Object<Metadata>>[]);
      };

      simple_map::borrow_mut(staker_pool_list_map, &staker)
    }

    #[view]
    public fun staker_shares(staker: address): (vector<Object<Metadata>>, vector<u64>) acquires PoolManagerConfigs {
      
      let tokens = vector<Object<Metadata>>[];
      let shares = vector<u64>[];
      let idx: u64 = 0;

      let staker_pool_list = staker_pool_list(staker);

      let pool_length = vector::length(&staker_pool_list);

      while(idx < pool_length){
        let token = *vector::borrow(&staker_pool_list, idx);
        vector::push_back(&mut tokens, token);
        
        let key = &StakerShareKey {
          staker,
          token,
        };

        vector::push_back(&mut shares, *simple_map::borrow(&pool_manager_configs().staker_shares, key));
        idx = idx + 1;
      };

      (tokens, shares)
    }

    inline fun pool_manager_configs(): &PoolManagerConfigs acquires PoolManagerConfigs {
      borrow_global<PoolManagerConfigs>(pool_manager_address())
    }
    inline fun mut_pool_manager_configs(): &mut PoolManagerConfigs acquires PoolManagerConfigs {
      borrow_global_mut<PoolManagerConfigs>(pool_manager_address())
    }

}