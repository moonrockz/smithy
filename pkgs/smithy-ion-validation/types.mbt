///|
pub(all) struct Finding {
  code : @validation.FindingCode
  severity : @validation.FindingSeverity
  path : @validation.InstancePath
  shape : @smithy.ShapeId
  message : String
  native_kind : @ion.IonType?
} derive(Eq, Debug)

///|
pub(all) struct ValidationResult {
  findings : Array[Finding]
  complete : Bool
} derive(Eq, Debug)

///|
pub fn ValidationResult::is_valid(self : ValidationResult) -> Bool {
  self.complete &&
  !self.findings.iter().any(f => f.severity == @validation.Error)
}

///|
pub impl @json.ToJson for Finding with fn to_json(self) {
  Json::object({
    "code": Json::string(self.code.to_string()),
    "severity": Json::string(
      if self.severity == @validation.Error {
        "error"
      } else {
        "advisory"
      },
    ),
    "path": @json.to_json(self.path),
    "pointer": Json::string(self.path.pointer()),
    "shape": Json::string(self.shape.to_string()),
    "message": Json::string(self.message),
    "nativeKind": match self.native_kind {
      Some(kind) => Json::string(kind.to_text())
      None => Json::null()
    },
  })
}

///|
pub impl @json.ToJson for ValidationResult with fn to_json(self) {
  Json::object({
    "valid": Json::boolean(self.is_valid()),
    "complete": Json::boolean(self.complete),
    "findings": Json::array(self.findings.map(f => @json.to_json(f))),
  })
}
