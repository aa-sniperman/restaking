module restaking::epoch {
  use aptos_framework::timestamp;

  const EPOCH_LENGTH: u64 = 3600;

  inline fun get_epoch_from_time(time: u64): u64 {
    time / EPOCH_LENGTH
  }

  public fun current_epoch(): u64 {
    get_epoch_from_time(timestamp::now_seconds())
  }

  public fun next_slashing_parameter_effect_epoch(): u64 {
    current_epoch() + 3
  }

  public fun min_execution_epoch_from_request_epoch(request_epoch: u64): u64{
    request_epoch + 2
  }

  public fun end_of_slashability_epoch(queued_epoch: u64): u64 {
    queued_epoch + 1
  }
}