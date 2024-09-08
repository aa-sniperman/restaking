#[test_only]
module restaking::package_manager_tests {
    use std::signer;
    use std::string;
    use restaking::package_manager;

    #[test(deployer = @0xcafe, resource_account=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun test_can_get_signer(deployer: &signer, resource_account: &signer) {
        package_manager::initialize_for_test(deployer, resource_account);
        let ra_addr = signer::address_of(resource_account);
        let staking_signer_addr = signer::address_of(&package_manager::get_signer());
        assert!(staking_signer_addr == ra_addr, 0);
    }

    #[test(deployer = @0xcafe, resource_account=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun test_can_set_and_get_address(deployer: &signer, resource_account: &signer) {
        package_manager::initialize_for_test(deployer, resource_account);
        package_manager::add_address(string::utf8(b"test"), @0xdeadbeef);
        assert!(package_manager::get_address(string::utf8(b"test")) == @0xdeadbeef, 0);
    }

    #[test(deployer = @0xcafe, resource_account=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun ensure_deployer_is_package_owner(deployer: &signer, resource_account: &signer) {
        package_manager::initialize_for_test(deployer, resource_account);
        package_manager::only_owner(signer::address_of(deployer));
    }

    #[test(deployer = @0xcafe, new_owner = @0xfeca, resource_account=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun test_change_owner(deployer: &signer, new_owner: &signer, resource_account: &signer) {
        package_manager::initialize_for_test(deployer, resource_account);
        package_manager::set_owner(deployer, signer::address_of(new_owner));
        package_manager::only_owner(signer::address_of(new_owner));
    }
}