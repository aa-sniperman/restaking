#[test_only]
module restaking::test_helpers {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
  use aptos_framework::object::{Self, Object, ConstructorRef};
  use aptos_framework::primary_fungible_store;

  use std::option;
  use std::string;
  use std::bcs;
  use std::vector;
  use std::debug;

  use aptos_std::aptos_hash;

  use restaking::package_manager;
  use restaking::staker_manager;
  use restaking::operator_manager;
  use restaking::earner_manager;
  use restaking::slasher;
  use restaking::withdrawal;
  use restaking::rewards_coordinator;
  use restaking::avs_manager;
  
  public fun set_up(deployer: &signer, ra: &signer){
    package_manager::initialize_for_test(deployer, ra);
    staker_manager::initialize();
    operator_manager::initialize();
    slasher::initialize();
    withdrawal::initialize();
    rewards_coordinator::initialize();
    avs_manager::initialize();
    earner_manager::initialize();

    assert!(staker_manager::is_initialized(), 0);
    assert!(operator_manager::is_initialized(), 0);
    assert!(slasher::is_initialized(), 0);
    assert!(withdrawal::is_initialized(), 0);
    assert!(rewards_coordinator::is_initialized(), 0);
    assert!(avs_manager::is_initialized(), 0);
    assert!(earner_manager::is_initialized(), 0);
  }

  public fun create_fungible_asset(creator: &signer, name: vector<u8>): ConstructorRef {
    let token_ctor = object::create_named_object(creator, name);
    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      &token_ctor,
      option::none(),
      string::utf8(name),
      string::utf8(name),
      8,
      string::utf8(b""),
      string::utf8(b""),
    );
    token_ctor
  }

  public fun create_fungible_asset_and_mint(creator: &signer, name: vector<u8>, amount: u64): FungibleAsset {
    let token_ctor = create_fungible_asset(creator, name);
    let mint_ref = &fungible_asset::generate_mint_ref(&token_ctor);
    fungible_asset::mint(mint_ref, amount)
  }

  #[view]
  public fun calculate_token_leaf_hash(
    token: Object<Metadata>,
    cummulative_earnings: u64
  ): vector<u8> {
    let leaf_payload = vector<u8>[];
    let token_addr = object::object_address(&token);
    vector::append(&mut leaf_payload, bcs::to_bytes(&token_addr));
    vector::append(&mut leaf_payload, bcs::to_bytes(&cummulative_earnings));
    aptos_hash::keccak256(leaf_payload)
  }

  #[view]
  public fun calculate_earner_leaf_hash(
    earner: address,
    earner_token_root: vector<u8>
  ): vector<u8> {
    let leaf_payload = vector<u8>[];
    vector::append(&mut leaf_payload, bcs::to_bytes(&earner));
    vector::append(&mut leaf_payload, bcs::to_bytes(&earner_token_root));

    debug::print(&bcs::to_bytes(&earner));
    debug::print(&bcs::to_bytes(&earner_token_root));
    debug::print(&leaf_payload);
    aptos_hash::keccak256(leaf_payload)
  }

  #[view]
  public fun hash2(left: vector<u8>, right: vector<u8>): vector<u8>{
    let payload = vector<u8>[];
    vector::append(&mut payload, left);
    vector::append(&mut payload, right);
    aptos_hash::keccak256(payload)
  }

  #[view]
  public fun zero_leaf(): vector<u8>{
    let leaf = vector<u8>[];
    let idx = 0;
    while(idx < 32){
      vector::push_back(&mut leaf, 0u8);
      idx = idx + 1;
    };
    leaf
  }
}