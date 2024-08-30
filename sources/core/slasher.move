module restaking::slasher {
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Self, FungibleStore, Metadata,
  };
  use aptos_framework::object::{Self, Object};
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_framework::primary_fungible_store;

  use aptos_std::simple_map::{Self, SimpleMap};
  use aptos_std::smart_vector::{Self, SmartVector};

  use std::string;
  use std::bcs;
  use std::vector;
  use std::signer;

  use restaking::epoch;
  use restaking::slashing_accounting;
  use restaking::package_manager;

  const SLASHER_NAME: vector<u8> = b"SLASHER_NAME";
  const SLASHER_PREFIX: vector<u8> = b"SLASHER_PREFIX";

  const EMIN_EXCECUTION_EPOCH_NOT_PASSED: u64 = 801;
  const EEXCECUTED_SLASHINGS_NOT_IN_ORDER: u64 = 802;


  struct SlashingRequestIds has drop, store{
    last_created: u32,
    last_executed: u32,
  }
  struct SlashingRequest has copy, drop, store {
    id: u32,
    slashing_rate: u64,
    scaling_factor: u64
  }
  struct OperatorSlashingStore has key {
    slashing_request_ids: SlashingRequestIds,
    slashing_requests: SimpleMap<u64, SlashingRequest>,
    share_scaling_factor: u64,
    slashed_epoch_history: SmartVector<u64>,
  }

  struct SlasherConfigs has key {
    signer_cap: SignerCapability
  }

  #[event]
  struct SlashingExecuted has drop, store{
    epoch: u64,
    operator: address,
    token: Object<Metadata>,
    slashing_rate: u64,
  }
      /// Create the share account to host all the staker & operator shares.
  public entry fun initialize() {
    if (is_initialized()) {
      return
    };

    // derive a resource account from signer to manage User share Account
    let staking_signer = &package_manager::get_signer();
    let (slasher_signer, signer_cap) = account::create_resource_account(staking_signer, SLASHER_NAME);
    package_manager::add_address(string::utf8(SLASHER_NAME), signer::address_of(&slasher_signer));
    move_to(&slasher_signer, SlasherConfigs {
      signer_cap,
    });
  }

  #[view]
  public fun is_initialized(): bool{
    package_manager::address_exists(string::utf8(SLASHER_NAME))
  }

  public entry fun execute_slashing(
    operator: address,
    tokens: vector<Object<Metadata>>,
    epoch: u64
  ) acquires OperatorSlashingStore {
    assert!(epoch::current_epoch() > epoch::min_execution_epoch_from_request_epoch(epoch), EMIN_EXCECUTION_EPOCH_NOT_PASSED);
    vector::for_each(tokens, |token| execute_slashing_for_a_token(operator, token, epoch));
  }

  fun execute_slashing_for_a_token(
    operator: address,
    token: Object<Metadata>,
    epoch: u64
  ) acquires OperatorSlashingStore {
    let operator_slashing_store = mut_operator_slashing_store(operator, token);
    let request = simple_map::borrow_mut(&mut operator_slashing_store.slashing_requests, &epoch);
    assert!(request.id == operator_slashing_store.slashing_request_ids.last_executed + 1, EEXCECUTED_SLASHINGS_NOT_IN_ORDER);
    operator_slashing_store.slashing_request_ids.last_executed = request.id;
    if(request.slashing_rate > slashing_accounting::bips_factor_square()){
      request.slashing_rate = slashing_accounting::bips_factor_square();
    } else if(request.slashing_rate == 0){
      return
    };

    let scaling_factor_before = operator_slashing_store.share_scaling_factor;
    let scaling_factor_after = slashing_accounting::find_new_scaling_factor(scaling_factor_before, request.slashing_rate);

    operator_slashing_store.share_scaling_factor = scaling_factor_after;
    smart_vector::push_back(&mut operator_slashing_store.slashed_epoch_history, epoch);
    request.scaling_factor = scaling_factor_after;

    event::emit(SlashingExecuted {
      operator,
      epoch,
      token,
      slashing_rate: request.slashing_rate
    });
  }

  #[view]
  public fun get_withdrawability_and_scaling_factor_at_epoch(
    operator: address,
    token: Object<Metadata>,
    epoch: u64
  ): (bool, u64) acquires OperatorSlashingStore {
    let can_withdraw = true;
    let scaling_factor = slashing_accounting::share_conversion_scale();
    let (found, lookup_epoch) = get_lookup_epoch(operator, token, epoch);
    if(found){
      can_withdraw = can_withdraw_internal(operator, token, lookup_epoch);
      let store = operator_slashing_store(operator, token);
      scaling_factor = simple_map::borrow(&store.slashing_requests, &lookup_epoch).scaling_factor;
    };
    (can_withdraw, scaling_factor)
  }

  fun get_lookup_epoch(
    operator: address,
    token: Object<Metadata>,
    epoch: u64
  ): (bool, u64) acquires OperatorSlashingStore {
    let store = operator_slashing_store(operator, token);
    let history = &store.slashed_epoch_history;
    let epoch_for_lookup: u64 = 0;
    let found = false;
    let history_length = smart_vector::length(history);
    if(history_length == 0) return (false, 0);
    let i: u64 = history_length - 1;
    while(i > 0){
      epoch_for_lookup = *smart_vector::borrow(history, i);
      if(epoch <= epoch_for_lookup){
        return (true, epoch_for_lookup);
      };
      i = i - 1;
    };
    (false, 0)
  } 

  #[view]
  public fun can_withdraw(
    operator: address,
    token: Object<Metadata>,
    epoch: u64
  ): bool acquires OperatorSlashingStore {
    let (found, lookup_epoch) = get_lookup_epoch(operator, token, epoch);
    if(!found) return true;
    can_withdraw_internal(operator, token, lookup_epoch)
  }
  fun can_withdraw_internal(
    operator: address,
    token: Object<Metadata>,
    epoch: u64
  ): bool acquires OperatorSlashingStore {
    let store = operator_slashing_store(operator, token);
    let id_at_epoch = simple_map::borrow(&store.slashing_requests, &epoch).id;
    let last_executed_id = store.slashing_request_ids.last_executed;
    id_at_epoch <= last_executed_id
  }

  fun create_operator_slasher_store(operator: address, token: Object<Metadata>){
    let slasher_signer = slasher_signer();
    let ctor = &object::create_named_object(slasher_signer, operator_slashing_seeds(operator, token));
    let operator_store_signer = object::generate_signer(ctor);
    move_to(&operator_store_signer, OperatorSlashingStore {
      slashing_request_ids: SlashingRequestIds {
        last_created: 0,
        last_executed: 0,
      },
      slashing_requests: simple_map::new(),
      share_scaling_factor: 0,
      slashed_epoch_history: smart_vector::new(),
    });
  }

  #[view]
  public fun share_scaling_factor(operator: address, token: Object<Metadata>): u64 acquires OperatorSlashingStore{
    let store = operator_slashing_store(operator, token);
    let scaling_factor = store.share_scaling_factor;
    if(scaling_factor == 0){
      return slashing_accounting::share_conversion_scale();
    };
    scaling_factor
  }

  inline fun operator_slashing_store_address(operator: address, token: Object<Metadata>): address {
    object::create_object_address(&slasher_address(), operator_slashing_seeds(operator, token))
  }

  inline fun slasher_address(): address {
    package_manager::get_address(string::utf8(SLASHER_NAME))
  }

  inline fun slasher_signer(): &signer acquires SlasherConfigs{
    &account::create_signer_with_capability(&borrow_global<SlasherConfigs>(slasher_address()).signer_cap)
  }

  inline fun operator_slashing_seeds(operator: address, token: Object<Metadata>): vector<u8>{
    let seeds = vector<u8>[];
    vector::append(&mut seeds, bcs::to_bytes(&operator));
    let token_addr = object::object_address(&token);
    vector::append(&mut seeds, bcs::to_bytes(&token_addr));
    seeds
  }

  inline fun operator_slashing_store(operator: address, token: Object<Metadata>): &OperatorSlashingStore acquires OperatorSlashingStore {
    borrow_global<OperatorSlashingStore>(operator_slashing_store_address(operator, token))
  }

  inline fun mut_operator_slashing_store(operator: address, token: Object<Metadata>): &mut OperatorSlashingStore acquires OperatorSlashingStore {
    borrow_global_mut<OperatorSlashingStore>(operator_slashing_store_address(operator, token))
  }


}