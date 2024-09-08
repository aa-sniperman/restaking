module restaking::staking_pool {
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Self, FungibleStore, Metadata,
  };
  use aptos_framework::object::{Self, Object};
  use aptos_framework::primary_fungible_store;
  use std::bcs;
  use std::vector;
  use std::signer;

  use restaking::package_manager;

  friend restaking::staker_manager;

  const SHARES_OFFSET: u128 = 1000;
  const BALANCE_OFFSET: u64 = 1000;
  const MAX_TOTAL_SHARES: u128 = 1_000_000_000_000_000_000_000_000; // 10^24

  const ENEW_SHARES_NOT_POSITIVE: u64 = 201;
  const EMAX_TOTAL_SHARES_EXCEEDED: u64 = 202;
  const ETOTAL_SHARES_EXCEEDED: u64 = 203;

  struct StakingPool has key {
    token_store: Object<FungibleStore>,
    total_shares: u128,
  }

  #[event]
  struct ExchangeRateEmitted has drop, store {
    exchange_rate: u128,
  }

  /// Create the pool manager account to host all the staking pools.
  public(friend) fun ensure_staking_pool(token: Object<Metadata>): Object<StakingPool> {
    let seeds = get_pool_seeds(token);

    let package_signer = &package_manager::get_signer();
    let staking_pool_addr = object::create_object_address(&signer::address_of(package_signer), seeds);

    if(object::object_exists<StakingPool>(staking_pool_addr)){
      return object::address_to_object<StakingPool>(staking_pool_addr)
    };
    let ctor = &object::create_named_object(package_signer, seeds);
    
    let pool_signer = &object::generate_signer(ctor);

    let store = fungible_asset::create_store(ctor, token);

    let pool = StakingPool {
      token_store: store,
      total_shares: 0,
    };

    move_to(pool_signer, pool);

    object::object_from_constructor_ref(ctor)
  }

  // assume that the asset has already been transferred to the store
  public(friend) fun deposit(pool: Object<StakingPool>, amount: u64): u128 acquires StakingPool {
    let staking_pool = mut_staking_pool(&pool);

    let total_shares = &mut staking_pool.total_shares;
    let total_balance = fungible_asset::balance(staking_pool.token_store);


    let virtual_shares = *total_shares + SHARES_OFFSET;
    let virtual_balance = total_balance + BALANCE_OFFSET;

    let virtual_prior_balance = virtual_balance - amount;

    let new_shares = ((amount as u128) * virtual_shares) / (virtual_prior_balance as u128);

    assert!(new_shares > 0, ENEW_SHARES_NOT_POSITIVE);

    *total_shares = *total_shares + new_shares;

    assert!(*total_shares <= MAX_TOTAL_SHARES, EMAX_TOTAL_SHARES_EXCEEDED);

    emit_exchange_rate(virtual_balance, *total_shares + SHARES_OFFSET);

    new_shares
  }

  public(friend) fun withdraw(recipient: address, pool: Object<StakingPool>, amount_shares: u128) acquires StakingPool {

    let staking_pool = mut_staking_pool(&pool);

    let total_shares = &mut staking_pool.total_shares;

    let token = fungible_asset::store_metadata(staking_pool.token_store);

    assert!(amount_shares <= *total_shares, ETOTAL_SHARES_EXCEEDED);

    let total_balance = fungible_asset::balance(staking_pool.token_store);

    let virtual_shares = *total_shares + SHARES_OFFSET;
    let virtual_balance = total_balance + BALANCE_OFFSET;

    let amount = (((virtual_balance as u128) * amount_shares) / virtual_shares as u64);

    *total_shares = *total_shares - amount_shares;

    let pool_signer = &package_manager::get_signer();
    let withdrawal = fungible_asset::withdraw(pool_signer, staking_pool.token_store, amount);

    let to = primary_fungible_store::ensure_primary_store_exists(recipient, token);

    emit_exchange_rate(virtual_balance - amount, *total_shares + SHARES_OFFSET);

    fungible_asset::deposit(to, withdrawal);
  }

  #[view]
  public fun token_store(pool: Object<StakingPool>): Object<FungibleStore> acquires StakingPool {
    staking_pool(&pool).token_store
  }

  #[view]
  public fun token_metadata(pool: Object<StakingPool>): Object<Metadata> acquires StakingPool {
    fungible_asset::store_metadata(token_store(pool))
  }

  #[view]
  public fun total_shares(pool: Object<StakingPool>): u128 acquires StakingPool {
    let staking_pool = staking_pool(&pool);
    staking_pool.total_shares
  }

  inline fun get_pool_seeds(token: Object<Metadata>): vector<u8>{
    let seeds = vector[];
    vector::append(&mut seeds, bcs::to_bytes(&object::object_address(&token)));
    seeds
  }
    
  inline fun staking_pool(pool: &Object<StakingPool>): &StakingPool acquires StakingPool {
    borrow_global<StakingPool>(object::object_address(pool))
  }

  inline fun mut_staking_pool(pool: &Object<StakingPool>): &mut StakingPool acquires StakingPool {
    borrow_global_mut<StakingPool>(object::object_address(pool))
  }

  inline fun create_token_store(pool_signer: &signer, token: Object<Metadata>): Object<FungibleStore> {
    let constructor_ref = &object::create_object_from_object(pool_signer);
    fungible_asset::create_store(constructor_ref, token)
  }

  inline fun emit_exchange_rate(virtual_balance: u64, virtual_shares: u128){
    event::emit(ExchangeRateEmitted {
      exchange_rate: 1_000_000_000u128 * (virtual_balance as u128) / virtual_shares
    });
  }

  #[test_only]
  friend restaking::staking_pool_tests;

  #[test_only]
  friend restaking::delegation_tests;
}