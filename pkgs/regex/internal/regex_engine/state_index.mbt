// Added for moonrockz/regex.

///|
/// Deterministic open addressing. State keys and probes are always metered.
priv struct StateIndex {
  mut slots : FixedArray[Int32]
  keys : Buffer[FixedArray[Int32]]
  hashes : Buffer[UInt32]
}

///|
fn StateIndex::new() -> StateIndex {
  { slots: [], keys: Buffer::new(), hashes: Buffer::new(), }
}

///|
fn key_hash(key : FixedArray[Int32], work : Work) -> UInt32 raise WorkExhausted {
  work.spend(key.length())
  let mut hash = 2166136261U
  for word in key {
    hash = (hash ^ word.reinterpret_as_uint()) * 16777619U
  }
  hash
}

///|
fn equal_key(
  a : FixedArray[Int32],
  b : FixedArray[Int32],
  work : Work,
) -> Bool raise WorkExhausted {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    work.spend(1)
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn StateIndex::grow(self : StateIndex, work : Work) -> Unit raise WorkExhausted {
  let capacity = Int32::max(8, self.slots.length() * 2)
  work.spend(capacity)
  let slots = FixedArray::make(capacity, -1)
  let mask = capacity - 1
  for id in 0..<self.keys.length {
    work.spend(1)
    let hash = self.hashes.get(id)
    let mut at = hash.reinterpret_as_int() & mask
    while true {
      work.spend(1)
      if slots[at] < 0 {
        slots[at] = id
        break
      }
      at = (at + 1) & mask
    }
  }
  self.slots = slots
}

///|
/// The key's ID and whether it was inserted. IDs follow first-visit order.
fn StateIndex::intern(
  self : StateIndex,
  key : FixedArray[Int32],
  work : Work,
) -> (Int32, Bool) raise WorkExhausted {
  let hash = key_hash(key, work)
  if self.slots.length() == 0 {
    self.grow(work)
  }
  let mut at = hash.reinterpret_as_int() & (self.slots.length() - 1)
  while true {
    work.spend(1)
    let id = self.slots[at]
    if id < 0 {
      break
    }
    if self.hashes.get(id) == hash && equal_key(key, self.keys.get(id), work) {
      return (id, false)
    }
    at = (at + 1) & (self.slots.length() - 1)
  }
  if self.keys.length >= self.slots.length() / 2 {
    self.grow(work)
    at = hash.reinterpret_as_int() & (self.slots.length() - 1)
    while true {
      work.spend(1)
      if self.slots[at] < 0 {
        break
      }
      at = (at + 1) & (self.slots.length() - 1)
    }
  }
  let id = self.keys.length
  self.keys.push(key, work)
  self.hashes.push(hash, work)
  self.slots[at] = id
  (id, true)
}
