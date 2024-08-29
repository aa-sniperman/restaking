module restaking::operator_manager {
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

  friend restaking::staker_manager;
  friend restaking::withdrawal;

  const OPERATOR_MANAGER_NAME: vector<u8> = b"OPERATOR_MANAGER_NAME";
  const OPERATOR_PREFIX: vector<u8> = b"OPERATOR_PREFIX";

  const MAX_STAKER_POOL_LIST_LENGTH: u64 = 100;

  const EMAX_STAKER_POOL_LIST_LENGTH_EXCEEDED: u64 = 101;
  const EZERO_SHARES: u64 = 102;
  const ESHARES_TOO_HIGH: u64 = 103;


  struct OperatorStore has key {
    shares: SimpleMap<Object<Metadata>, u128>,
    salt_spent: SimpleMap<u256, bool>,
  }

  struct StakerManagerConfigs has key {
    signer_cap: SignerCapability
  }

  #[event]
  struct OperatorShareIncreased has drop, store {
    operator: address,
    staker: address,
    token: Object<Metadata>,
    shares: u128,
  }

  #[event]
  struct OperatorShareDecreased has drop, store {
    operator: address,
    staker: address,
    token: Object<Metadata>,
    shares: u128,
  }

    /// Create the share account to host all the staker & operator shares.
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from signer to manage User share Account
        let staking_signer = &package_manager::get_signer();
        let (operator_manager_signer, signer_cap) = account::create_resource_account(staking_signer, OPERATOR_MANAGER_NAME);
        package_manager::add_address(string::utf8(OPERATOR_MANAGER_NAME), signer::address_of(&operator_manager_signer));
        move_to(&operator_manager_signer, StakerManagerConfigs {
            signer_cap,
        });
    }

  #[view]
  public fun is_initialized(): bool{
    package_manager::address_exists(string::utf8(OPERATOR_MANAGER_NAME))
  }


    #[view]
    public fun operator_token_shares(operator: address, token: Object<Metadata>): u128 acquires OperatorStore {
      if(!operator_store_exists(operator)){
        return 0;
      };

      let store = operator_store(operator);
      *simple_map::borrow(&store.shares, &token)
    }

    #[view]
    public fun operator_shares(operator: address): (vector<Object<Metadata>>, vector<u128>) acquires OperatorStore {
      if(!operator_store_exists(operator)){
        return (vector[], vector[]);
      };

      let store = operator_store(operator);

      (simple_map::keys(&store.shares), simple_map::values(&store.shares))
    }

  fun ensure_operator_store(operator: address) acquires OperatorStore{
    if(!operator_store_exists(operator)){
      create_operator_store(operator);
    };
  }

  #[view]
  public fun operator_store_exists(operator: address): bool acquires OperatorStore{
    exists<OperatorStore>(operator)
  }

  public(friend) fun increase_operator_shares(operator: address, staker: address, token: Object<Metadata>, shares: u128) acquires OperatorStore {
    ensure_operator_store(operator);

    let store = mut_operator_store(operator);

    if(simple_map::contains_key(&store.shares, &token)){
      let current_shares = simple_map::borrow_mut(&mut store.shares, &token);
      *current_shares = *current_shares + shares;
    }else {
      simple_map::add(&mut store.shares, token, shares);
    };

    event::emit(OperatorShareIncreased {
      operator,
      staker,
      token,
      shares
    });
  }

  public(friend) fun decrease_operator_shares(operator: address, staker: address, token: Object<Metadata>, shares: u128) acquires OperatorStore {

    ensure_operator_store(operator);
   let store = mut_operator_store(operator);

    if(simple_map::contains_key(&store.shares, &token)){
      let current_shares = simple_map::borrow_mut(&mut store.shares, &token);
      *current_shares = *current_shares - shares;
    }else {
      simple_map::add(&mut store.shares, token, 0);
    };

    event::emit(OperatorShareDecreased {
      operator,
      staker,
      token,
      shares
    });
  }

  fun create_operator_store(operator: address){
    let operator_manager_signer = operator_manager_signer();
    let ctor = &object::create_named_object(operator_manager_signer, operator_store_seeds(operator));
    let operator_store_signer = object::generate_signer(ctor);
    move_to(&operator_store_signer, OperatorStore {
      shares: simple_map::new(),
      salt_spent: simple_map::new(),
    });
  }


  inline fun operator_store_address(operator: address): address {
    object::create_object_address(&staker_manager_address(), operator_store_seeds(operator))
  }

  inline fun staker_manager_address(): address {
    package_manager::get_address(string::utf8(OPERATOR_MANAGER_NAME))
  }

  inline fun operator_manager_signer(): &signer acquires StakerManagerConfigs{
    &account::create_signer_with_capability(&borrow_global<StakerManagerConfigs>(staker_manager_address()).signer_cap)
  }

  inline fun operator_store_seeds(operator: address): vector<u8>{
    let seeds = vector<u8>[];
    vector::append(&mut seeds, OPERATOR_PREFIX);
    vector::append(&mut seeds, bcs::to_bytes(&operator));
    seeds
  }

  inline fun operator_store(operator: address): &OperatorStore acquires OperatorStore {
    borrow_global<OperatorStore>(operator_store_address(operator))
  }

  inline fun mut_operator_store(operator: address): &mut OperatorStore acquires OperatorStore {
    borrow_global_mut<OperatorStore>(operator_store_address(operator))
  }
}