module restaking::delegation_manager {
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Self, FungibleAsset, FungibleStore, Metadata,
  };
  use aptos_framework::object::{Self, ConstructorRef, Object};
  use aptos_framework::primary_fungible_store;
  use aptos_std::simple_map::{Self, SimpleMap};

  use std::vector;

  const MAX_WITHDRAWAL_DELAY: u64 = 7 * 24 * 3600; // 7 days

  struct StakerDelegation {
    staker: address,
    operator: address,
    nonce: u256,
    expiry: u256
  }

  struct Withdrawal {
    staker: address,
    delegated_to: address,
    withdrawer: address,
    nonce: u256,
    start_time: u64,
    tokens: vector<Object<Metadata>>,
    shares: vector<u64>,
  }

  struct QueuedWithdrawalParams {
    tokens: vector<Object<Metadata>>,
    shares: vector<u64>,
    withdrawer: address,
  }

  struct StakerDelegationData has store {
    delegated_to: address,
    nonce: u256,
    cummulative_withdrawals_queued: u256,
  }

  struct OperatorShareKey has store {
    operator: address,
    token: Object<Metadata>,
  }

  struct DelegationMangerConfigs has key {
    operator_shares: SimpleMap<OperatorShareKey, u64>,
    staker_delegation: SimpleMap<address, StakerDelegationData>,
    min_withdrawal_delay: u64,
    pending_withdrawals: SimpleMap<vector<u8>, bool>,
    token_withdrawal_delay: SimpleMap<Object<Metadata>, u64>,
  }

  
}