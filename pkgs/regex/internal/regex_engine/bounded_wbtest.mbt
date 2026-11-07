///|
test "state index meters colliding probes growth and recovery" {
  let index = StateIndex::new()
  let work : Work = { left: 1000000, }
  // FNV maps these one-word keys to the same bucket for initial capacities.
  for i in 0..<200 {
    let key : FixedArray[Int32] = [i * 256]
    assert_eq(index.intern(key, work), (i, true))
  }
  assert_true(index.slots.length() >= 400)
  for i in 0..<200 {
    assert_eq(index.intern([i * 256], work), (i, false))
  }
  assert_true(work.left < 990000)
  let fresh = StateIndex::new()
  let tiny : Work = { left: 2, }
  let stopped = try {
    ignore(fresh.intern([1], tiny))
    false
  } catch {
    WorkExhausted => true
  }
  assert_true(stopped)
  assert_eq(fresh.slots.length(), 0)
}

///|
test "a work refusal never subtracts or wraps counters" {
  let work : Work = { left: 7, }
  let stopped = try {
    work.spend(0x7fffffff)
    false
  } catch {
    WorkExhausted => true
  }
  assert_true(stopped)
  assert_eq(work.left, 7)
}

///|
test "allocation stops before a table or buffer grows" {
  let buffer : Buffer[Int32] = Buffer::new()
  let work : Work = { left: 3, }
  let stopped = try {
    buffer.push(1, work)
    false
  } catch {
    WorkExhausted => true
  }
  assert_true(stopped)
  assert_eq(buffer.data.length(), 0)
  assert_eq(buffer.length, 0)
}
