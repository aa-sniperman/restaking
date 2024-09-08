module restaking::package_manager {
    use aptos_framework::event;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::resource_account;
    use aptos_std::smart_table::{Self, SmartTable};
    use std::string::{Self, String};
    use std::signer;

    friend restaking::coin_wrapper;
    friend restaking::withdrawal;
    friend restaking::staker_manager;
    friend restaking::operator_manager;
    friend restaking::staking_pool;
    friend restaking::rewards_coordinator;
    friend restaking::avs_manager;
    friend restaking::earner_manager;
    friend restaking::slasher;

    const OWNER_NAME: vector<u8> = b"OWNER";

    const ENOT_OWNER: u64 = 1;

    /// Stores permission config such as SignerCapability for controlling the resource account.
    struct PermissionConfig has key {
        /// Required to obtain the resource account signer.
        signer_cap: SignerCapability,
        /// Track the addresses created by the modules in this package.
        addresses: SmartTable<String, address>,
    }

    #[event]
    struct OwnerChanged has drop, store {
        old_owner: address,
        new_owner: address,
    }

    /// Initialize PermissionConfig to establish control over the resource account.
    /// This function is invoked only when this package is deployed the first time.
    fun init_module(staking_signer: &signer) acquires PermissionConfig {
        let signer_cap = resource_account::retrieve_resource_account_cap(staking_signer, @deployer);
        move_to(staking_signer, PermissionConfig {
            addresses: smart_table::new<String, address>(),
            signer_cap,
        });
        add_address(string::utf8(OWNER_NAME), @deployer);
    }

    /// Can be called by friended modules to obtain the resource account signer.
    public(friend) fun get_signer(): signer acquires PermissionConfig {
        let signer_cap = &borrow_global<PermissionConfig>(@restaking).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    /// Can be called by friended modules to keep track of a system address.
    public(friend) fun add_address(name: String, object: address) acquires PermissionConfig {
        let addresses = &mut borrow_global_mut<PermissionConfig>(@restaking).addresses;
        smart_table::upsert(addresses, name, object);
    }

    public entry fun set_owner(owner: &signer, new_owner: address) acquires PermissionConfig{
        let owner_addr = signer::address_of(owner);
        only_owner(owner_addr);
        add_address(string::utf8(OWNER_NAME), new_owner);
        event::emit(OwnerChanged {
            old_owner: owner_addr,
            new_owner
        });
    }

    public fun only_owner(owner: address) acquires PermissionConfig{
        assert!(owner == get_address(string::utf8(OWNER_NAME)), ENOT_OWNER);
    }
    public fun address_exists(name: String): bool acquires PermissionConfig {
        smart_table::contains(&safe_permission_config().addresses, name)
    }

    public fun get_address(name: String): address acquires PermissionConfig {
        let addresses = &borrow_global<PermissionConfig>(@restaking).addresses;
        *smart_table::borrow(addresses, name)
    }

    inline fun safe_permission_config(): &PermissionConfig acquires PermissionConfig {
        borrow_global<PermissionConfig>(@restaking)
    }

    #[test_only]
    public fun initialize_for_test(deployer: &signer, resource_account: &signer) {
        use std::vector;
        use std::signer;

        let deployer_addr = signer::address_of(deployer);
        let resource_account_addr = signer::address_of(resource_account);
        if(!exists<PermissionConfig>(resource_account_addr)){
            aptos_framework::timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
            account::create_account_for_test(signer::address_of(deployer));

            resource_account::create_resource_account(deployer, vector::empty<u8>(), vector::empty<u8>());
            
            let addresses = smart_table::new<String, address>();
            smart_table::add(&mut addresses, string::utf8(OWNER_NAME), deployer_addr);
            move_to(resource_account, PermissionConfig {
                addresses,
                signer_cap: account::create_test_signer_cap(resource_account_addr),
            });
        };
    }

    #[test_only]
    friend restaking::package_manager_tests;
    #[test_only]
    friend restaking::rewards_tests;
}