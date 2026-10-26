///|
/// The runtime uses int64 codes. Compare exact values before expanding the
/// bounded integer. A zero with a large exponent needs no expansion.
fn code_text(
  code : @rpc.ErrorCode,
  construct : String,
) -> String raise @codegen.CodegenError {
  let number = code.number()
  if number.numeric_compare(
      @smithy.NodeNumber::parse("-9223372036854775808").unwrap(),
    ) <
    0 ||
    number.numeric_compare(
      @smithy.NodeNumber::parse("9223372036854775807").unwrap(),
    ) >
    0 {
    raise @codegen.InvalidSettings(
      "I expected an int64 error code for construct `\{construct}`; I found `\{code.to_string()}`.",
    )
  }
  if number.numeric_compare(@smithy.NodeNumber::parse("0").unwrap()) == 0 {
    return "0"
  }
  let parts = code
    .to_string()
    .replace_all(old="E", new="e")
    .split("e")
    .to_array()
  let mantissa = parts[0].to_owned()
  let fractional = match mantissa.find(".") {
    Some(at) => mantissa.length() - at - 1
    None => 0
  }
  let digits = mantissa.replace_all(old=".", new="")
  let trimmed = digits.trim_end(chars="0").to_owned()
  let coefficient = BigInt::from_string(trimmed).to_string()
  let power = if parts.length() == 2 {
    BigInt::from_string(parts[1].trim_start(chars="+").to_owned())
  } else {
    BigInt::from_int(0)
  }
  let exponent = power -
    BigInt::from_int(fractional) +
    BigInt::from_int(digits.length() - trimmed.length())
  coefficient + "0".repeat(exponent.to_int16().to_int())
}
