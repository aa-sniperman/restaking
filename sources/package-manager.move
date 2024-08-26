module restaking::package_manager {
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::resource_account;
    use aptos_std::simple_map::{Self, SimpleMap};
    use std::string::String;

    friend restaking::coin_wrapper;

    /// Stores permission config such as SignerCapability for controlling the resource account.
    struct PermissionConfig has key {
        /// Required to obtain the resource account signer.
        signer_cap: SignerCapability,
        /// Track the addresses created by the modules in this package.
        addresses: SimpleMap<String, address>,
    }

    /// Initialize PermissionConfig to establish control over the resource account.
    /// This function is invoked only when this package is deployed the first time.
    fun init_module(swap_signer: &signer) {
        let signer_cap = resource_account::retrieve_resource_account_cap(swap_signer, @deployer);
        move_to(swap_signer, PermissionConfig {
            addresses: simple_map::new<String, address>(),
            signer_cap,
        });
    }

    /// Can be called by friended modules to obtain the resource account signer.
    public(friend) fun get_signer(): signer acquires PermissionConfig {
        let signer_cap = &borrow_global<PermissionConfig>(@restaking).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    /// Can be called by friended modules to keep track of a system address.
    public(friend) fun add_address(name: String, object: address) acquires PermissionConfig {
        let addresses = &mut borrow_global_mut<PermissionConfig>(@restaking).addresses;
        simple_map::add(addresses, name, object);
    }

    public fun address_exists(name: String): bool acquires PermissionConfig {
        simple_map::contains_key(&safe_permission_config().addresses, &name)
    }

    public fun get_address(name: String): address acquires PermissionConfig {
        let addresses = &borrow_global<PermissionConfig>(@restaking).addresses;
        *simple_map::borrow(addresses, &name)
    }

    inline fun safe_permission_config(): &PermissionConfig acquires PermissionConfig {
        borrow_global<PermissionConfig>(@restaking)
    }

    #[test_only]
    public fun initialize_for_test(deployer: &signer, resource_account: &signer) {
        use std::vector;
        use std::signer;

        account::create_account_for_test(signer::address_of(deployer));

        // create a resource account from the origin account, mocking the module publishing process
        resource_account::create_resource_account(deployer, vector::empty<u8>(), vector::empty<u8>());
        init_module(resource_account);
    }

    #[test_only]
    friend restaking::package_manager_tests;
}