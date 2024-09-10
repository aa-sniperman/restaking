module restaking::slashing_accounting {
  const SHARE_CONVERSION_SCALE: u64 = 1_000_000_000;
  
  #[view]
  public fun denormalize(shares: u128, scaling_factor: u64): u128 {
    (shares * (scaling_factor as u128)) / (SHARE_CONVERSION_SCALE as u128)
  }

  #[view]
  public fun normalize(non_normalize_shares: u128, scaling_factor: u64): u128 {
    (non_normalize_shares * (SHARE_CONVERSION_SCALE as u128)) / (scaling_factor as u128)
  }

  #[view]
  public fun share_conversion_scale(): u64{
    SHARE_CONVERSION_SCALE
  }
}