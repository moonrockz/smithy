///|
/// Every diagnostic code with its one-line description. The scanner and
/// the parser emit only codes from this table; the laws check that.
let table : Array[(String, String)] = [
  ("SM-SCAN-001", "Unexpected character"),
  ("SM-SCAN-002", "Unterminated string"),
  ("SM-SCAN-003", "Unterminated text block"),
  ("SM-SCAN-004", "Text block must start with a line break"),
  ("SM-SCAN-005", "Unknown escape sequence"),
  ("SM-SCAN-006", "Invalid unicode escape"),
  ("SM-SCAN-007", "Invalid number"),
  ("SM-PARSE-001", "Unexpected token"),
  ("SM-PARSE-002", "Unexpected end of file"),
  ("SM-PARSE-003", "Missing line break between statements"),
  ("SM-PARSE-004", "Expected a statement"),
  ("SM-PARSE-005", "Invalid shape ID or shape name"),
  ("SM-PARSE-006", "Unsupported Smithy version"),
  ("SM-PARSE-007", "Syntax that needs Smithy IDL version 2"),
  ("SM-PARSE-008", "Documentation comment before apply (warning)"),
  ("SM-PARSE-009", "Detached documentation comment (warning)"),
  ("SM-PARSE-010", "Too much nesting"),
  ("SM-PARSE-011", "Unknown operation property"),
  ("SM-PARSE-012", "Duplicate operation property"),
  ("SM-PARSE-013", "Duplicate control statement"),
  ("SM-PARSE-014", "Duplicate member name"),
  ("SM-PARSE-015", "Syntax that needs Smithy IDL version 1"),
]

///|
/// Every diagnostic code, in table order.
pub fn codes() -> ArrayView[String] {
  table.map(entry => entry.0)[:]
}

///|
/// The one-line description of a code, or `None` for an unknown code.
pub fn description(code : String) -> String? {
  for entry in table {
    if entry.0 == code {
      return Some(entry.1)
    }
  }
  None
}
