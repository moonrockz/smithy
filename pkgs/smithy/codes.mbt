///|
/// The assembly diagnostic codes. Parser diagnostics keep their syntax codes.
pub fn diagnostic_codes() -> Array[(String, String)] {
  [
    ("SM-MODEL-001", "Invalid input or unsupported version"),
    ("SM-MODEL-002", "Invalid shape ID or import"),
    ("SM-MODEL-003", "Conflicting shape definitions"),
    ("SM-MODEL-004", "Unresolved shape reference"),
    ("SM-MODEL-005", "Invalid reference target"),
    ("SM-MODEL-006", "Conflicting metadata"),
    ("SM-MODEL-007", "Conflicting trait values"),
    ("SM-MODEL-008", "Invalid mixin"),
    ("SM-MODEL-009", "Cyclic dependency"),
    ("SM-MODEL-010", "Invalid shape properties or members"),
    ("SM-MODEL-011", "Invalid trait application"),
    ("SM-MODEL-012", "Unresolved elided member"),
    ("SM-MODEL-013", "Unresolved apply target"),
    ("SM-MODEL-014", "Built-in model redefinition"),
    ("SM-MODEL-015", "Invalid JMESPath condition syntax"),
    ("SM-MODEL-016", "Invalid JMESPath condition operation"),
    ("SM-MODEL-017", "Non-boolean condition expression"),
  ]
}
