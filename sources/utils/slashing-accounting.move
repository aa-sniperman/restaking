module restaking::slashing_accounting {
  const SHARE_CONVERSION_SCALE: u64 = 1_000_000_000;
  const BIPS_FACTOR: u64 = 10000;
  const BIPS_FACTOR_SQUARE: u64 = 100000000;
  const MAX_VALID_SHARES: u128 = 1u128 << 96 - 1;

  const EZERO_RATE_TO_SLASH: u64 = 1301;
  const ERATE_TO_SLASH_TOO_BIG: u64 = 1302;
  
  #[view]
  public fun denormalize(shares: u128, scaling_factor: u64): u128 {
    (shares * (scaling_factor as u128)) / (SHARE_CONVERSION_SCALE as u128)
  }

  #[view]
  public fun normalize(non_normalize_shares: u128, scaling_factor: u64): u128 {
    (non_normalize_shares * (SHARE_CONVERSION_SCALE as u128)) / (scaling_factor as u128)
  }

  #[view]
  public fun find_new_scaling_factor(scaling_factor_before: u64, rate_to_slash: u64): u64 {
    assert!(rate_to_slash > 0, EZERO_RATE_TO_SLASH);
    assert!(rate_to_slash <= BIPS_FACTOR_SQUARE, ERATE_TO_SLASH_TOO_BIG);
    if(rate_to_slash == BIPS_FACTOR_SQUARE){
      return ((1u128 << 64) as u64) - 1u64
    };
    (scaling_factor_before * BIPS_FACTOR_SQUARE) / (BIPS_FACTOR_SQUARE - rate_to_slash)
  }

  #[view]
  public fun bips_factor_square(): u64 {
    BIPS_FACTOR_SQUARE
  }

  #[view]
  public fun share_conversion_scale(): u64{
    SHARE_CONVERSION_SCALE
  }
}