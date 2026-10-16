///|
/// The executable format of a binary, from its header. The payload is the machine field:
/// `e_machine` for ELF, `cputype` for Mach-O and `Machine` for PE.
pub(all) enum Format {
  Elf(Int32)
  MachO(Int32)
  Pe(Int32)
  Unknown
} derive(Eq, Debug)

///|
/// The text that the summary shows, for example `Elf(62)`.
fn Format::describe(self : Format) -> String {
  match self {
    Elf(machine) => "Elf(\{machine})"
    MachO(cputype) => "MachO(\{cputype})"
    Pe(machine) => "Pe(\{machine})"
    Unknown => "Unknown"
  }
}

///|
fn u16_le(bytes : Bytes, offset : Int32) -> Int32? {
  if offset < 0 || offset + 2 > bytes.length() {
    return None
  }
  Some(bytes[offset].to_int() | (bytes[offset + 1].to_int() << 8))
}

///|
fn u32_le(bytes : Bytes, offset : Int32) -> Int32? {
  guard u16_le(bytes, offset) is Some(low) else { return None }
  guard u16_le(bytes, offset + 2) is Some(high) else { return None }
  Some(low | (high << 16))
}

///|
fn starts_with(bytes : Bytes, magic : Bytes) -> Bool {
  if bytes.length() < magic.length() {
    return false
  }
  for i in 0..<magic.length() {
    if bytes[i] != magic[i] {
      return false
    }
  }
  true
}

///|
/// Read the format from the first bytes of a file. A short or unknown input gives `Unknown`.
pub fn detect_format(bytes : Bytes) -> Format {
  if starts_with(bytes, b"\x7FELF") {
    return match u16_le(bytes, 18) {
      Some(machine) => Elf(machine)
      None => Unknown
    }
  }
  // 64-bit little-endian Mach-O (MH_MAGIC_64 as it is stored on disk).
  if starts_with(bytes, b"\xCF\xFA\xED\xFE") {
    return match u32_le(bytes, 4) {
      Some(cputype) => MachO(cputype)
      None => Unknown
    }
  }
  if starts_with(bytes, b"MZ") {
    guard u32_le(bytes, 0x3C) is Some(lfanew) else { return Unknown }
    if lfanew < 0 || !starts_with(bytes[lfanew:].to_owned(), b"PE\x00\x00") {
      return Unknown
    }
    return match u16_le(bytes, lfanew + 4) {
      Some(machine) => Pe(machine)
      None => Unknown
    }
  }
  Unknown
}

///|
/// The format that a binary for `target` must have. `Host` has none, so it is not checked.
pub fn expected_format(target : Target) -> Format? {
  match target {
    LinuxX64 => Some(Elf(62))
    LinuxArm64 => Some(Elf(183))
    DarwinArm64 => Some(MachO(0x0100000C))
    DarwinX64 => Some(MachO(0x01000007))
    WindowsX64 => Some(Pe(0x8664))
    Host => None
  }
}

///|
/// `None` when the header in `bytes` is right for `target`, else the message for the summary.
pub fn check_format(target : Target, bytes : Bytes) -> String? {
  guard expected_format(target) is Some(expected) else { return None }
  let found = detect_format(bytes)
  if found == expected {
    None
  } else {
    Some(
      "\{target.name()}: expected \{expected.describe()}, found \{found.describe()}",
    )
  }
}
