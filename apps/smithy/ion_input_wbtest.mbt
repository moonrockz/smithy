///|
test "Ion input stops after the first excess byte and closes the source" {
  let mut consumed = 0
  let mut closes = 0
  let source : InputSource = {
    read: requested => {
      let count = Int32::min(requested, 100 - consumed)
      consumed += count
      Bytes::make(count, b'x')
    },
    close: () => closes += 1,
  }
  let limited = try {
    let _ = collect_ion_bytes(source, max_bytes=3)
    false
  } catch {
    IonInputError("IonInputLimit", _, None) => true
    _ => false
  }
  assert_true(limited)
  assert_eq(consumed, 4)
  assert_eq(closes, 1)
}

///|
test "Ion input preserves read errors and closes the source" {
  let mut closes = 0
  let source : InputSource = {
    read: _ => raise CliError("read failed", 1),
    close: () => {
      closes += 1
      raise CliError("close failed", 1)
    },
  }
  let read_error = try {
    let _ = collect_ion_bytes(source, max_bytes=3)
    false
  } catch {
    CliError("read failed", 1) => true
    _ => false
  }
  assert_true(read_error)
  assert_eq(closes, 1)
}

///|
test "Ion input accepts an exact limit and closes after EOF" {
  let mut reads = 0
  let mut closes = 0
  let source : InputSource = {
    read: requested => {
      reads += 1
      if reads == 1 {
        assert_eq(requested, 4)
        b"abc"
      } else {
        assert_eq(requested, 1)
        b""
      }
    },
    close: () => closes += 1,
  }
  assert_eq(collect_ion_bytes(source, max_bytes=3), b"abc")
  assert_eq(reads, 2)
  assert_eq(closes, 1)
}

///|
test "Ion input rejects the first byte at a zero limit" {
  let mut reads = 0
  let mut closes = 0
  let source : InputSource = {
    read: requested => {
      assert_eq(requested, 1)
      reads += 1
      b"x"
    },
    close: () => closes += 1,
  }
  let limited = try {
    let _ = collect_ion_bytes(source, max_bytes=0)
    false
  } catch {
    IonInputError("IonInputLimit", _, None) => true
    _ => false
  }
  assert_true(limited)
  assert_eq(reads, 1)
  assert_eq(closes, 1)
}

///|
test "Ion input reports close errors without closing twice" {
  let mut closes = 0
  let source : InputSource = {
    read: _ => b"",
    close: () => {
      closes += 1
      raise CliError("close failed", 1)
    },
  }
  let close_error = try {
    let _ = collect_ion_bytes(source, max_bytes=3)
    false
  } catch {
    CliError("close failed", 1) => true
    _ => false
  }
  assert_true(close_error)
  assert_eq(closes, 1)
}
