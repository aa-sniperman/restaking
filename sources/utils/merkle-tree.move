module restaking::merkle_tree {
  use std::bcs;
  use std::vector;
  
  use aptos_std::comparator;
  use aptos_std::aptos_hash;

  const EOVERFLOW: u64 = 1101;
  const EINVALID_PROOF_LENGTH: u64 = 1102;
  
  #[view]
  public fun verify_inclusion_keccak(
    proof: vector<u8>,
    leaf: vector<u8>,
    index: u32,
    root: vector<u8>,
  ): bool {
    comparator::is_equal(&comparator::compare_u8_vector(root, process_inclusion_proof_keccak(
      proof,
      leaf,
      index
    )))
  }

  fun process_inclusion_proof_keccak(
    proof: vector<u8>,
    leaf: vector<u8>,
    index: u32
  ): vector<u8> {
    let proof_length: u64 = vector::length(&proof);
    assert!(proof_length % 32 == 0, EINVALID_PROOF_LENGTH);
    let computed_hash: vector<u8> = leaf;
    let i: u64 = 32;
    while(i < proof_length) {
      let sibling = vector::slice(&proof, i, i + 32);
      let hash_data = vector<u8>[];

      if(index % 2 == 0){
        vector::append(&mut hash_data, computed_hash);
        vector::append(&mut hash_data, sibling);
      }else {
        vector::append(&mut hash_data, sibling);
        vector::append(&mut hash_data, computed_hash);
      };

      index = index / 2;
      computed_hash = aptos_hash::keccak256(hash_data);
      i = i + 1;
    };

    computed_hash
  }
}