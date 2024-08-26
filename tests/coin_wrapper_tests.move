#[test_only]
module restaking::coin_wrapper_tests {
  use aptos_framework::account;
  use aptos_framework::coin::{Self, Coin, FakeMoney};
  use aptos_framework::fungible_asset::{Self, FungibleAsset};
  use restaking::coin_wrapper;
  use std::signer;

  use restaking::test_helpers;

  public fun wrap<CoinType>(coin: Coin<CoinType>): FungibleAsset {
    coin_wrapper::wrap(coin)
  }

  #[test(user = @0x1, deployer = @0xcafe, resource_account = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  fun test_e2e(user: &signer, deployer: &signer, resource_account: &signer){
    test_helpers::set_up(deployer, resource_account);

    coin_wrapper::initialize();

    account::create_account_for_test(signer::address_of(user));

    let amount: u64 = 1000;
    coin::create_fake_money(user, user, amount);
    let coins = coin::withdraw<FakeMoney>(user, amount);
    let fa = coin_wrapper::wrap<FakeMoney>(coins);

    let metadata = fungible_asset::asset_metadata(&fa);
    assert!(fungible_asset::amount(&fa) == amount, 0);
    assert!(fungible_asset::name(metadata) == coin::name<FakeMoney>(), 1);
    assert!(fungible_asset::symbol(metadata) == coin::symbol<FakeMoney>(), 2);
    assert!(fungible_asset::decimals(metadata) == coin::decimals<FakeMoney>(), 3);

    let coins = coin_wrapper::unwrap<FakeMoney>(fa);
    assert!(coin::value(&coins) == amount, 4);
    coin::deposit(signer::address_of(user), coins);
  }
}