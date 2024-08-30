module restaking::staker_manager {
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Self, FungibleAsset, Metadata,
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
  use restaking::operator_manager;
  use restaking::staking_pool;
  use restaking::slasher;
  use restaking::slashing_accounting;

  friend restaking::withdrawal;

  const STAKER_MANAGER_NAME: vector<u8> = b"STAKER_MANAGER_NAME";
  const STAKER_PREFIX: vector<u8> = b"STAKER_PREFIX";

  const MAX_STAKER_POOL_LIST_LENGTH: u64 = 100;

  const EMAX_STAKER_POOL_LIST_LENGTH_EXCEEDED: u64 = 101;
  const EZERO_SHARES: u64 = 102;
  const ESHARES_TOO_HIGH: u64 = 103;
  const ESTAKER_ALREADY_DELEGATED: u64 = 104;
  const ENOT_OPERATOR: u64 = 105;
  const EZERO_ADDRESS: u64 = 106;
  const ENOT_STAKER_NOR_OPERATOR: u64 = 107;


  struct StakerStore has key {
    delegated_to: address,
    cummulative_withdrawals_queued: u256,
    pool_list: SmartVector<Object<Metadata>>,
    nonnormalized_shares: SimpleMap<Object<Metadata>, u128>
  }

  struct StakerManagerConfigs has key {
    signer_cap: SignerCapability
  }

  #[event]
  struct Deposit has drop, store {
    staker: address,
    token: Object<Metadata>,
    nonnormalized_shares: u128,
  }

  #[event]
  struct StakerDelegated has drop, store {
    operator: address,
    staker: address,
  }

  #[event]
  struct StakerUndelegated has drop, store {
    operator: address,
    staker: address,
  }

  #[event]
  struct StakerForcedUndelegated has drop, store {
    operator: address,
    staker: address
  }


    /// Create the share account to host all the staker & operator shares.
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from signer to manage User share Account
        let staking_signer = &package_manager::get_signer();
        let (staker_manager_signer, signer_cap) = account::create_resource_account(staking_signer, STAKER_MANAGER_NAME);
        package_manager::add_address(string::utf8(STAKER_MANAGER_NAME), signer::address_of(&staker_manager_signer));
        move_to(&staker_manager_signer, StakerManagerConfigs {
            signer_cap,
        });
    }

  #[view]
  public fun is_initialized(): bool{
    package_manager::address_exists(string::utf8(STAKER_MANAGER_NAME))
  }


    public(friend) fun add_shares(staker: address, token: Object<Metadata>, nonnormalized_shares: u128) acquires StakerStore {
      ensure_staker_store(staker);

      let store = mut_staker_store(staker);

      if(!simple_map::contains_key(&store.nonnormalized_shares, &token)){
        simple_map::add(&mut store.nonnormalized_shares, token, 0);
      };

      let current_shares = simple_map::borrow_mut(&mut store.nonnormalized_shares, &token);
      let staker_pool_list = &mut store.pool_list;

      let current_list_length = smart_vector::length(staker_pool_list);

      if(*current_shares == 0){
        assert!(current_list_length < MAX_STAKER_POOL_LIST_LENGTH, EMAX_STAKER_POOL_LIST_LENGTH_EXCEEDED);
        if(!smart_vector::contains(staker_pool_list, &token)){
          smart_vector::push_back(staker_pool_list, token);
        }
      };

      *current_shares = *current_shares + nonnormalized_shares;

      event::emit(Deposit {
        staker, 
        token,
        nonnormalized_shares
      })
    }

    public(friend) fun remove_shares(staker: address, token: Object<Metadata>, nonnormalized_shares: u128) acquires StakerStore {
      assert!(nonnormalized_shares > 0, EZERO_SHARES);
      let store = mut_staker_store(staker);

      if(!simple_map::contains_key(&store.nonnormalized_shares, &token)){
        simple_map::add(&mut store.nonnormalized_shares, token, 0);
      };

      let current_shares = simple_map::borrow_mut(&mut store.nonnormalized_shares, &token);
      assert!(nonnormalized_shares <= *current_shares, ESHARES_TOO_HIGH);
      *current_shares = *current_shares - nonnormalized_shares;

      if(*current_shares <= 0){
        let staker_pool_list = &mut store.pool_list;
        let (found, idx) = smart_vector::index_of(staker_pool_list, &token);
        if(found){
          smart_vector::remove(staker_pool_list, idx);
        };
      };
    }

    public(friend) fun deposit(staker: &signer, token: Object<Metadata>, asset: FungibleAsset) acquires StakerStore{
      let pool = staking_pool::ensure_staking_pool(token);

      let store = staking_pool::token_store(pool);

      let token = fungible_asset::metadata_from_asset(&asset);
      let amount = fungible_asset::amount(&asset);

      fungible_asset::deposit(store, asset);
      let nonnormalized_shares = staking_pool::deposit(pool, amount);
      
      let staker_addr = signer::address_of(staker);
      add_shares(staker_addr, token, nonnormalized_shares);

      // delegation: increase operator shares
      let operator = delegate_of(staker_addr);
      if(operator != @0x0){
        operator_manager::increase_operator_shares(operator, staker_addr, token, nonnormalized_shares);
      }
    }

    public(friend) fun withdraw(recipient: address, token: Object<Metadata>, nonnormalized_shares: u128){
      let pool = staking_pool::ensure_staking_pool(token);
      staking_pool::withdraw(recipient, pool, nonnormalized_shares);
    }

    public entry fun delegate(staker: &signer, operator: address){
      let staker_addr = signer::address_of(staker);
      let current_delegate = delegate_of(staker_addr);
      assert!(current_delegate == @0x0, ESTAKER_ALREADY_DELEGATED);
      assert!(is_operator(operator), ENOT_OPERATOR);
      delegate_internal(staker_addr, operator);
    }

    public(friend) fun undelegate(sender: &signer, staker: address): address acquires StakerStore{
      assert!(staker != @0x0, EZERO_ADDRESS);
      let operator = delegate_of(staker);
      assert!(operator == @0x0, ESTAKER_ALREADY_DELEGATED);
      assert!(is_operator(operator), ENOT_OPERATOR);
      let sender_addr = signer::address_of(sender);
      assert!(sender_addr == staker || sender_addr == operator, ENOT_STAKER_NOR_OPERATOR);

      if(sender_addr != staker){
        event::emit(StakerForcedUndelegated{
          operator,
          staker,
        });
      };

      event::emit(StakerUndelegated{
        operator,
        staker,
      });

      let store = mut_staker_store(staker);

      store.delegated_to = @0x0;

      operator
    }

  fun delegate_internal(staker: address, operator: address) acquires StakerStore {
    let store = mut_staker_store(staker);

    store.delegated_to = operator;

    let (tokens, nonnormalized_token_shares) = staker_nonormalized_shares(staker);

    let tokens_length = vector::length(&tokens);

    let idx = 0;
    while(idx < tokens_length){
      let token = *vector::borrow(&tokens, idx);
      let nonnormalized_shares = *vector::borrow(&nonnormalized_token_shares, idx);
      operator_manager::increase_operator_shares(operator, staker, token, nonnormalized_shares);
      idx = idx + 1;
    };
    
    event::emit(StakerDelegated {
      operator,
      staker,
    });
  }

  #[view]
  public fun delegate_of(staker: address): address acquires StakerStore{
    if(!staker_store_exists(staker)) return @0x0;
    let store = staker_store(staker);
    store.delegated_to
  }

  #[view]
  public fun is_operator(operator: address): bool acquires StakerStore{
    if(operator == @0x0) return false;
    delegate_of(operator) == operator
  }

    #[view]
    public fun staker_token_shares(staker: address, token: Object<Metadata>): u128 acquires StakerStore {
      if(!staker_store_exists(staker)){
        return 0;
      };

      let store = staker_store(staker);
      let nonnormalized_shares = *simple_map::borrow(&store.nonnormalized_shares, &token);

      let operator = delegate_of(staker);

      let scaling_factor = slasher::share_scaling_factor(operator, token);

      slashing_accounting::normalize(nonnormalized_shares, scaling_factor)
    }

  #[view]
  public fun staker_nonormalized_shares(staker: address): (vector<Object<Metadata>>, vector<u128>) acquires StakerStore {
    if(!staker_store_exists(staker)){
        return (vector[], vector[]);
      };

    let store = staker_store(staker);
    (simple_map::keys(&store.nonnormalized_shares), simple_map::values(&store.nonnormalized_shares))
  }

  fun ensure_staker_store(staker: address) acquires StakerStore{
    if(!staker_store_exists(staker)){
      create_staker_store(staker);
    };
  }

  #[view]
  public fun staker_store_exists(staker: address): bool acquires StakerStore{
    exists<StakerStore>(staker)
  }

  #[view]
  public fun cummulative_withdrawals_queued(staker: address): u256 acquires StakerStore {
    if(!staker_store_exists(staker)){
      return 0;
    };
    staker_store(staker).cummulative_withdrawals_queued
  }

  public(friend) fun increment_cummulative_withdrawals_queued(staker: address) acquires StakerStore {
    ensure_staker_store(staker);
    let current_nonce = &mut mut_staker_store(staker).cummulative_withdrawals_queued;
    *current_nonce = *current_nonce + 1;
  }

  fun create_staker_store(staker: address){
    let staker_manager_signer = staker_manager_signer();
    let ctor = &object::create_named_object(staker_manager_signer, staker_store_seeds(staker));
    let staker_store_signer = object::generate_signer(ctor);
    move_to(&staker_store_signer, StakerStore {
      delegated_to: @0x0,
      cummulative_withdrawals_queued: 0,
      nonnormalized_shares: simple_map::new(),
      pool_list: smart_vector::new(),
    });
  }


  inline fun staker_store_address(staker: address): address {
    object::create_object_address(&staker_manager_address(), staker_store_seeds(staker))
  }

  inline fun staker_manager_address(): address {
    package_manager::get_address(string::utf8(STAKER_MANAGER_NAME))
  }

  inline fun staker_manager_signer(): &signer acquires StakerManagerConfigs{
    &account::create_signer_with_capability(&borrow_global<StakerManagerConfigs>(staker_manager_address()).signer_cap)
  }

  inline fun staker_store_seeds(staker: address): vector<u8>{
    let seeds = vector<u8>[];
    vector::append(&mut seeds, STAKER_PREFIX);
    vector::append(&mut seeds, bcs::to_bytes(&staker));
    seeds
  }

  inline fun staker_store(staker: address): &StakerStore acquires StakerStore {
    borrow_global<StakerStore>(staker_store_address(staker))
  }

  inline fun mut_staker_store(staker: address): &mut StakerStore acquires StakerStore {
    borrow_global_mut<StakerStore>(staker_store_address(staker))
  }
}