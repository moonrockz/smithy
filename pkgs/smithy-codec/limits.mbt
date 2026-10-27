///|
/// Limits of one request: check, decode, encode or canonicalize. Work is one allowance shared by parsing,
/// form selection, adapters, constraint checks and output.
pub struct CodecLimits {
  input_bytes : Int32
  output_bytes : Int32
  depth : Int32
  work : Int32
  findings : Int32
} derive(Eq, Debug)

///|
pub fn CodecLimits::new(
  input_bytes~ : Int32 = 16777216,
  output_bytes~ : Int32 = 67108864,
  depth~ : Int32 = 128,
  work~ : Int32 = 2000000,
  findings~ : Int32 = 100,
) -> CodecLimits raise @validation.ConfigurationError {
  guard input_bytes > 0 &&
    input_bytes <= 16777216 &&
    output_bytes > 0 &&
    output_bytes <= 268435456 &&
    depth > 0 &&
    depth <= 1024 &&
    work > 0 &&
    work <= 10000000 &&
    findings > 1 &&
    findings <= 10000 else {
    raise @validation.ConfigurationError(
      "I expected input 1..16777216 bytes, output 1..268435456 bytes, depth 1..1024, work 1..10000000 and findings 2..10000.",
    )
  }
  { input_bytes, output_bytes, depth, work, findings, }
}

///|
pub fn CodecLimits::default() -> CodecLimits {
  {
    input_bytes: 16777216,
    output_bytes: 67108864,
    depth: 128,
    work: 2000000,
    findings: 100,
  }
}
