module restaking::operator_manager {
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Metadata,
  };
  use aptos_framework::object::{Self, Object};
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_std::smart_table::{Self, SmartTable};
  use std::string;
  use std::bcs;
  use std::vector;
  use std::signer;

  use restaking::package_manager;
  use restaking::slasher;
  use restaking::slashing_accounting;
  use restaking::math_utils;

  friend restaking::staker_manager;
  friend restaking::withdrawal;

  const OPERATOR_MANAGER_NAME: vector<u8> = b"OPERATOR_MANAGER_NAME";
  const OPERATOR_PREFIX: vector<u8> = b"OPERATOR_PREFIX";

  const MAX_STAKER_POOL_LIST_LENGTH: u64 = 100;

  const EMAX_STAKER_POOL_LIST_LENGTH_EXCEEDED: u64 = 401;
  const EZERO_SHARES: u64 = 402;
  const ESHARES_TOO_HIGH: u64 = 403;


  struct OperatorStore has key {
    nonnormalized_shares: SmartTable<Object<Metadata>, u128>,
    salt_spent: SmartTable<u256, bool>,
  }

  struct OperatorManagerConfigs has key {
    signer_cap: SignerCapability
  }

  #[event]
  struct OperatorShareIncreased has drop, store {
    operator: address,
    staker: address,
    token: Object<Metadata>,
    nonnormalized_shares: u128,
  }

  #[event]
  struct OperatorShareDecreased has drop, store {
    operator: address,
    staker: address,
    token: Object<Metadata>,
    nonnormalized_shares: u128,
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
        move_to(&operator_manager_signer, OperatorManagerConfigs {
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
        return 0
      };

      let store = operator_store(operator);
      let nonnormalized_shares = *smart_table::borrow_with_default(&store.nonnormalized_shares, token, &0);
      let scaling_factor = slasher::share_scaling_factor(operator, token);
      slashing_accounting::normalize(nonnormalized_shares, scaling_factor)
    }

    #[view]
    public fun operator_shares(operator: address, tokens: vector<Object<Metadata>>): vector<u128> acquires OperatorStore {

      let tokens_length = vector::length(&tokens);

      if(!operator_store_exists(operator)){
        return math_utils::vector_of_zeros(tokens_length)
      };

      let shares = vector<u128>[];
      let store = operator_store(operator);

      let i = 0;
      while(i < tokens_length){
        let token = *vector::borrow(&tokens, i);
        let nonnormalized_shares = *smart_table::borrow_with_default(&store.nonnormalized_shares, token, &0);
        let scaling_factor = slasher::share_scaling_factor(operator, token);
        vector::push_back(&mut shares, slashing_accounting::normalize(nonnormalized_shares, scaling_factor));
        i = i + 1;
      };
      shares
    }

  fun ensure_operator_store(operator: address) acquires OperatorManagerConfigs{
    if(!operator_store_exists(operator)){
      create_operator_store(operator);
    };
  }

  #[view]
  public fun operator_store_exists(operator: address): bool {
    exists<OperatorStore>(operator_store_address(operator))
  }

  public(friend) fun increase_operator_shares(operator: address, staker: address, token: Object<Metadata>, nonnormalized_shares: u128) acquires OperatorStore, OperatorManagerConfigs {
    ensure_operator_store(operator);

    let store = mut_operator_store(operator);

    if(smart_table::contains(&store.nonnormalized_shares, token)){
      let current_shares = smart_table::borrow_mut(&mut store.nonnormalized_shares, token);
      *current_shares = *current_shares + nonnormalized_shares;
    }else {
      smart_table::add(&mut store.nonnormalized_shares, token, nonnormalized_shares);
    };

    event::emit(OperatorShareIncreased {
      operator,
      staker,
      token,
      nonnormalized_shares
    });
  }

  public(friend) fun decrease_operator_shares(operator: address, staker: address, token: Object<Metadata>, nonnormalized_shares: u128) acquires OperatorStore, OperatorManagerConfigs {

    ensure_operator_store(operator);
    let store = mut_operator_store(operator);

    let current_shares = smart_table::borrow_mut_with_default(&mut store.nonnormalized_shares, token, 0);

    assert!(*current_shares >= nonnormalized_shares, ESHARES_TOO_HIGH);
    *current_shares = *current_shares - nonnormalized_shares;

    event::emit(OperatorShareDecreased {
      operator,
      staker,
      token,
      nonnormalized_shares
    });
  }

  fun create_operator_store(operator: address) acquires OperatorManagerConfigs{
    let operator_manager_signer = operator_manager_signer();
    let ctor = &object::create_named_object(operator_manager_signer, operator_store_seeds(operator));
    let operator_store_signer = object::generate_signer(ctor);
    move_to(&operator_store_signer, OperatorStore {
      nonnormalized_shares: smart_table::new(),
      salt_spent: smart_table::new(),
    });
  }


  inline fun operator_store_address(operator: address): address {
    object::create_object_address(&operator_manager_address(), operator_store_seeds(operator))
  }

  inline fun operator_manager_address(): address {
    package_manager::get_address(string::utf8(OPERATOR_MANAGER_NAME))
  }

  inline fun operator_manager_signer(): &signer acquires OperatorManagerConfigs{
    &account::create_signer_with_capability(&borrow_global<OperatorManagerConfigs>(operator_manager_address()).signer_cap)
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

  #[test_only]
  friend restaking::delegation_tests;
}