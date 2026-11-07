// Added for moonrockz/regex.

///|
priv suberror WorkExhausted

///|
priv struct Work {
  mut left : Int32
}

///|
fn Work::spend(self : Work, units : Int32) -> Unit raise WorkExhausted {
  if units < 0 || units > self.left {
    raise WorkExhausted
  }
  self.left -= units
}

///|
/// Explicit capacities give identical allocation charges on every backend.
priv struct Buffer[T] {
  mut data : FixedArray[T?]
  mut length : Int32
}

///|
fn[T] Buffer::new() -> Buffer[T] {
  { data: [], length: 0, }
}

///|
fn[T] Buffer::get(self : Buffer[T], index : Int32) -> T {
  self.data[index].unwrap()
}

///|
fn[T] Buffer::push(
  self : Buffer[T],
  value : T,
  work : Work,
) -> Unit raise WorkExhausted {
  if self.length == self.data.length() {
    // Each buffer cell has been charged, so length <= the public work bound.
    let capacity = Int32::max(4, self.data.length() * 2)
    work.spend(capacity + self.length)
    self.data = FixedArray::make_and_blit(
      self.data,
      allocate_len=capacity,
      init=None,
      len=self.length,
    )
  }
  work.spend(1)
  self.data[self.length] = Some(value)
  self.length += 1
}

///|
fn[T] Buffer::pop(self : Buffer[T], work : Work) -> T? raise WorkExhausted {
  if self.length == 0 {
    return None
  }
  work.spend(1)
  self.length -= 1
  let result = self.data[self.length]
  self.data[self.length] = None
  result
}

///|
fn[T] Buffer::clear(self : Buffer[T], work : Work) -> Unit raise WorkExhausted {
  work.spend(self.length)
  self.data.fill(None, end=self.length)
  self.length = 0
}
