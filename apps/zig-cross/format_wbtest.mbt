///|
fn elf(machine : Int32) -> Bytes {
  let b = Array::make(64, b'\x00')
  b[0] = b'\x7F'
  b[1] = b'E'
  b[2] = b'L'
  b[3] = b'F'
  b[18] = (machine & 0xFF).to_byte()
  b[19] = ((machine >> 8) & 0xFF).to_byte()
  Bytes::from_array(b)
}

///|
fn macho(cputype : Int32) -> Bytes {
  let b = Array::make(32, b'\x00')
  b[0] = b'\xCF'
  b[1] = b'\xFA'
  b[2] = b'\xED'
  b[3] = b'\xFE'
  b[4] = (cputype & 0xFF).to_byte()
  b[5] = ((cputype >> 8) & 0xFF).to_byte()
  b[6] = ((cputype >> 16) & 0xFF).to_byte()
  b[7] = ((cputype >> 24) & 0xFF).to_byte()
  Bytes::from_array(b)
}

///|
fn pe(machine : Int32, lfanew : Int32) -> Bytes {
  let b = Array::make(lfanew + 8, b'\x00')
  b[0] = b'M'
  b[1] = b'Z'
  b[0x3C] = (lfanew & 0xFF).to_byte()
  b[0x3D] = ((lfanew >> 8) & 0xFF).to_byte()
  b[lfanew] = b'P'
  b[lfanew + 1] = b'E'
  b[lfanew + 4] = (machine & 0xFF).to_byte()
  b[lfanew + 5] = ((machine >> 8) & 0xFF).to_byte()
  Bytes::from_array(b)
}

///|
test "detect_format reads the ELF machine" {
  assert_eq(detect_format(elf(62)), Elf(62))
  assert_eq(detect_format(elf(183)), Elf(183))
}

///|
test "detect_format reads the Mach-O cputype" {
  assert_eq(detect_format(macho(0x01000007)), MachO(16777223))
  assert_eq(detect_format(macho(0x0100000C)), MachO(16777228))
}

///|
test "detect_format reads the PE machine" {
  assert_eq(detect_format(pe(0x8664, 0x80)), Pe(34404))
}

///|
test "detect_format gives Unknown for junk and short input" {
  assert_eq(detect_format(b"\x00\x00"), Unknown)
  assert_eq(detect_format(b""), Unknown)
  assert_eq(detect_format(b"\x7FELF"), Unknown)
  assert_eq(detect_format(b"\xCF\xFA\xED\xFE\x07"), Unknown)
  assert_eq(detect_format(b"MZ"), Unknown)
  // e_lfanew points past the end of the input.
  let b = Array::make(0x40, b'\x00')
  b[0] = b'M'
  b[1] = b'Z'
  b[0x3C] = b'\xFF'
  assert_eq(detect_format(Bytes::from_array(b)), Unknown)
}

///|
test "expected_format per target" {
  assert_eq(expected_format(LinuxX64), Some(Elf(62)))
  assert_eq(expected_format(LinuxArm64), Some(Elf(183)))
  assert_eq(expected_format(DarwinArm64), Some(MachO(16777228)))
  assert_eq(expected_format(DarwinX64), Some(MachO(16777223)))
  assert_eq(expected_format(WindowsX64), Some(Pe(34404)))
  assert_eq(expected_format(Host), None)
}

///|
test "check_format reports a mismatch" {
  assert_eq(
    check_format(LinuxArm64, elf(62)),
    Some("linux-arm64: expected Elf(183), found Elf(62)"),
  )
}

///|
test "check_format accepts a match and skips the host" {
  assert_eq(check_format(LinuxArm64, elf(183)), None)
  assert_eq(check_format(WindowsX64, pe(0x8664, 0x80)), None)
  assert_eq(check_format(Host, b"\x00"), None)
}

///|
test "check_format rejects an unknown format" {
  assert_eq(
    check_format(DarwinX64, b"junk"),
    Some("darwin-x64: expected MachO(16777223), found Unknown"),
  )
}
