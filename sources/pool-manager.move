module restaking::pool_manager {
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Self, FungibleAsset, FungibleStore, Metadata,
  };
  use aptos_framework::object::{Self, ConstructorRef, Object};
  use aptos_framework::primary_fungible_store;
  use aptos_std::simple_map::{Self, SimpleMap};

  use std::vector;

  const POOL_MANAGER_NAME: vector<u8> = b"COIN_WRAPPER";

  struct StakerShareKey has store {
    staker: address,
    token: Object<Metadata>,
  }

  struct PoolManagerConfigs has key {
    staking_pools: SimpleMap<Object<Metadata>, Object<FungibleStore>>,
    staker_shares: SimpleMap<StakerShareKey, u64>,
    staker_pool_list: SimpleMap<address, vector<Object<Metadata>>>
  }


}