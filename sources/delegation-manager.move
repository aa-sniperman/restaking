module restaking::delegation_manager {
  use aptos_framework::event;
  use aptos_framework::fungible_asset::{
    Self, FungibleAsset, FungibleStore, Metadata,
  };
  use aptos_framework::object::{Self, ConstructorRef, Object};
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_framework::primary_fungible_store;
  use aptos_std::simple_map::{Self, SimpleMap};
  use std::string::{Self, String};


  use std::vector;
  use std::signer;
  use restaking::package_manager;

  const MAX_WITHDRAWAL_DELAY: u64 = 7 * 24 * 3600; // 7 days
  const DELEGATION_MANAGER_NAME: vector<u8> = b"POOL_MANAGER";

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
    signer_cap: SignerCapability,
    operator_shares: SimpleMap<OperatorShareKey, u64>,
    staker_delegation: SimpleMap<address, StakerDelegationData>,
    min_withdrawal_delay: u64,
    pending_withdrawals: SimpleMap<vector<u8>, bool>,
    token_withdrawal_delay: SimpleMap<Object<Metadata>, u64>,
  }

    /// Create the delegation manager account to host staking delegations.
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        // derive a resource account from swap signer to manage Wrapper Account
        let swap_signer = &package_manager::get_signer();
        let (delegation_manager_signer, signer_cap) = account::create_resource_account(swap_signer, DELEGATION_MANAGER_NAME);
        package_manager::add_address(string::utf8(DELEGATION_MANAGER_NAME), signer::address_of(&delegation_manager_signer));
        move_to(&delegation_manager_signer, DelegationMangerConfigs {
            signer_cap,
            operator_shares: simple_map::new(),
            staker_delegation: simple_map::new(),
            min_withdrawal_delay: 0,
            pending_withdrawals: simple_map::new(),
            token_withdrawal_delay: simple_map::new()
        });
    }

    #[view]
    public fun is_initialized(): bool {
        package_manager::address_exists(string::utf8(DELEGATION_MANAGER_NAME))
    }

  
}