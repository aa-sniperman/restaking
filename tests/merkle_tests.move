#[test_only]
module restaking::merkle_tests {
  use std::vector;
  use std::string;
  use std::bcs;
  use std::signer;
  use std::debug;

  use aptos_framework::fungible_asset::{Self, Metadata};
  use aptos_framework::primary_fungible_store;
  use aptos_framework::object;

  use aptos_std::aptos_hash;
  use aptos_std::comparator;

  use restaking::test_helpers;
  use restaking::merkle_tree;
  use restaking::rewards_coordinator::{Self, TokenMerkleTreeLeaf, EarnerMerkleTreeLeaf};

  #[test(deployer = @0xcafe, ra=@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
  public fun test_calculate_token_leaf_hash(deployer: &signer, ra: &signer){
    test_helpers::set_up(deployer, ra);
    let token_ctor = &test_helpers::create_fungible_asset(deployer, b"Token 1");
    let token = object::object_from_constructor_ref(token_ctor);

    let cummulative_earnings = 1000u64;
    let actual_hash = rewards_coordinator::calculate_token_leaf_hash(
      token,
      cummulative_earnings
    );

    let expected_hash = test_helpers::calculate_token_leaf_hash(token, cummulative_earnings);
    
    assert!(comparator::is_equal(&comparator::compare_u8_vector(actual_hash, expected_hash)), 1);

    assert!(vector::length(&actual_hash) == 32, 0);

    let hash_value = vector<u8>[
      0,  60, 202,  83,  30,  92, 151, 200,
      158,  67,  71, 136,  76, 190,  57, 138,
      181, 126, 121, 251, 152,  74, 145, 209,
      38, 170,  49, 114, 211, 152, 234, 118
    ];

    assert!(comparator::is_equal(&comparator::compare_u8_vector(actual_hash, hash_value)), 1);
  }

  #[test]
  public fun test_calculate_earner_leaf_hash(){

    let earner = @0x34162865fa;
    let earner_token_root = vector<u8>[
      3,  49,  26,  37, 139, 239, 224, 244,
      103, 189, 225, 158,  85, 238,  21,  67,
      52, 187, 194,  20, 132,  93,   0,   6,
      89, 169,  68, 176,  84, 153, 144, 195
    ];
    let actual_hash = rewards_coordinator::calculate_earner_leaf_hash(
      earner,
      earner_token_root
    );

    let expected_hash = test_helpers::calculate_earner_leaf_hash(earner, earner_token_root);

    assert!(comparator::is_equal(&comparator::compare_u8_vector(actual_hash, expected_hash)), 1);

    let hash_value = vector<u8>[
      70,  73, 205, 208, 186, 83, 200, 249,
      20, 177,  13,  68, 138,  3, 182,  49,
      239, 203, 144,  22,  66, 67,  69, 155,
      95, 232,  15,  58, 135, 24, 146, 165
    ];

    debug::print(&actual_hash);
    debug::print(&hash_value);
    assert!(comparator::is_equal(&comparator::compare_u8_vector(actual_hash, hash_value)), 1);
  }

  #[test(deployer = @0xcafe)]
  public fun test_merkle_tree_proofs(deployer: &signer){
    let token_ctor = &test_helpers::create_fungible_asset(deployer, b"Token 1");
    let token = object::object_from_constructor_ref(token_ctor);

    let cummulative_earnings = 1000u64;
    let actual_hash = rewards_coordinator::calculate_token_leaf_hash(
      token,
      cummulative_earnings
    );

    let token_leaf = test_helpers::calculate_token_leaf_hash(token, cummulative_earnings);
  
    let token_index = 2u32;
    let token_proof = vector<u8>[
      112, 137, 187,  16,  74, 149, 187,   1, 254,  76, 201,
      37, 136, 245, 164, 229, 183,  36, 227,  73, 139, 155,
      67,  36,  85,  93,  45,  80, 204, 206, 200,  61,  49,
      178, 232, 160,  30,  18, 225,  68,  10, 205, 180, 139,
      2, 169, 134, 176,  15, 119, 227,  40, 109, 130,  29,
      215, 101, 127, 199, 199,  57, 171, 172, 114
    ];

    let token_root = vector<u8>[
      3,  49,  26,  37, 139, 239, 224, 244,
      103, 189, 225, 158,  85, 238,  21,  67,
      52, 187, 194,  20, 132,  93,   0,   6,
      89, 169,  68, 176,  84, 153, 144, 195
    ];

    let token_proof_valid = merkle_tree::verify_inclusion_keccak(
      token_proof,
      token_leaf,
      token_index,
      token_root
    );

    assert!(token_proof_valid, 0);

    let earner = @0x34162865fa;

    let earner_leaf = test_helpers::calculate_earner_leaf_hash(earner, token_root);

    let earner_index = 3;

    let earner_root = vector<u8>[
      240,  47, 223, 182, 233, 180, 130,
      92, 171,  45, 252, 183, 234, 179,
      173, 128, 249, 250,   3, 103, 139,
      188,  70, 165,  90, 171, 153, 232,
      157, 132,  91, 168
    ];

    let earner_proof = vector<u8>[
      162, 184, 188, 164, 152,  16, 100, 214,  33, 197, 201,  47,
      242, 181, 125, 177,  38, 248,  19, 123,  39, 227,   2, 255,
      4,  79,  24, 131,  25,   8, 167,  54, 237, 128,  35, 189,
      169, 143, 171, 225,  90, 143, 188, 194, 207,  13,  47, 103,
      239, 161, 168, 182, 152, 163, 164, 111,   1, 106, 161, 240,
      25,  76, 170, 214,  89,  37, 215, 219,  40,  14, 240, 146,
      41, 127,  82, 185, 248,  77,  91, 195,  50, 124, 173, 231,
      95, 140, 101, 112,  19, 198, 134,  16, 127,  24,  30,  89
    ];

    let earner_proof_valid = merkle_tree::verify_inclusion_keccak(
      earner_proof,
      earner_leaf,
      earner_index,
      earner_root
    );

    assert!(earner_proof_valid, 0);
  }
}