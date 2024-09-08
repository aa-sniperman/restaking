#[test_only]
module restaking::test_helpers {
  use aptos_framework::coin::{Self, Coin};
  use aptos_framework::fungible_asset::{Self, FungibleAsset};
  use aptos_framework::object;
  use aptos_framework::primary_fungible_store;
  use std::option;
  use std::string;

  use restaking::package_manager;
  use restaking::staker_manager;
  use restaking::operator_manager;
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

    assert!(staker_manager::is_initialized(), 0);
    assert!(operator_manager::is_initialized(), 0);
    assert!(slasher::is_initialized(), 0);
    assert!(withdrawal::is_initialized(), 0);
    assert!(rewards_coordinator::is_initialized(), 0);
    assert!(avs_manager::is_initialized(), 0);
  }

  public fun create_fungible_asset_and_mint(creator: &signer, name: vector<u8>, amount: u64): FungibleAsset {
    let token_ctor = &object::create_named_object(creator, name);
    primary_fungible_store::create_primary_store_enabled_fungible_asset(
      token_ctor,
      option::none(),
      string::utf8(name),
      string::utf8(name),
      8,
      string::utf8(b""),
      string::utf8(b""),
    );
    let mint_ref = &fungible_asset::generate_mint_ref(token_ctor);
    fungible_asset::mint(mint_ref, amount)
  }
}