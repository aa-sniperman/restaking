module restaking::math_utils {
  use std::vector;
  use std::bcs;

  const EOVERFLOW: u64 = 1001;

  #[view]
  public fun bytes32_to_u256(bytes32: vector<u8>): u256{
    let bytes_length = vector::length(&bytes32);
    assert!(bytes_length <= 32, EOVERFLOW);
    let res: u256 = 0;
    let i: u64 = 0;
    while(i < bytes_length){
      let byte = *vector::borrow(&bytes32, i);
      res = res | ((byte as u256) << ((i * 8) as u8));
      i = i + 1;
    };

    res
  }

  #[view]
  public fun u256_to_bytes32(value: u256): vector<u8>{
    bcs::to_bytes(&value)
  }

  #[view]
  public fun vector_of_zeros(length: u64): vector<u128>{
    let zeros = vector::empty<u128>();

    let i = 0;
    while (i < length) {
      vector::push_back(&mut zeros, 0u128);
      i = i + 1;
    };

    zeros 
  }
}