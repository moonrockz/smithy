///|
/// The kind of a codec finding. Constraint findings come from Smithy value validation.
pub(all) enum CodecCode {
  Constraint(@validation.FindingCode)
  InvalidJson
  DuplicateName
  KindMismatch
  UnknownMember
  MissingMember
  MemberCollision
  UnknownTag
  Arity
  AmbiguousForm
  AdapterFailure
  DuplicateKey
  IncompatibleValue
  UnrepresentableValue
  MissingVersion
  InvalidVersion
  UnsupportedVersion
  VersionConflict
  LimitExceeded
} derive(Eq, Debug)

///|
pub fn CodecCode::to_string(self : CodecCode) -> String {
  match self {
    Constraint(code) => code.to_string()
    InvalidJson => "InvalidJson"
    DuplicateName => "DuplicateName"
    KindMismatch => "KindMismatch"
    UnknownMember => "UnknownMember"
    MissingMember => "MissingMember"
    MemberCollision => "MemberCollision"
    UnknownTag => "UnknownTag"
    Arity => "Arity"
    AmbiguousForm => "AmbiguousForm"
    AdapterFailure => "AdapterFailure"
    DuplicateKey => "DuplicateKey"
    IncompatibleValue => "IncompatibleValue"
    UnrepresentableValue => "UnrepresentableValue"
    MissingVersion => "MissingVersion"
    InvalidVersion => "InvalidVersion"
    UnsupportedVersion => "UnsupportedVersion"
    VersionConflict => "VersionConflict"
    LimitExceeded => "LimitExceeded"
  }
}

///|
pub impl Show for CodecCode with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// One finding. The path is the original input location when reading, and the logical location when
/// encoding a value.
pub(all) struct CodecFinding {
  code : CodecCode
  path : @validation.InstancePath
  shape : @smithy.ShapeId
  message : String
} derive(Eq, Debug)

///|
/// The result of a check. A value is valid only when the check is complete and has no findings.
pub(all) struct CodecResult {
  findings : Array[CodecFinding]
  complete : Bool
} derive(Eq, Debug)

///|
pub fn CodecResult::is_valid(self : CodecResult) -> Bool {
  self.complete && self.findings.is_empty()
}

///|
pub impl ToJson for CodecFinding with fn to_json(self) {
  Json::object({
    "code": Json::string(self.code.to_string()),
    "severity": Json::string("error"),
    "path": self.path.to_json(),
    "pointer": Json::string(self.path.pointer()),
    "shape": Json::string(self.shape.to_string()),
    "message": Json::string(self.message),
  })
}

///|
pub impl ToJson for CodecResult with fn to_json(self) {
  Json::object({
    "valid": Json::boolean(self.is_valid()),
    "complete": Json::boolean(self.complete),
    "findings": Json::array(self.findings.map(f => f.to_json())),
  })
}

///|
/// A refused check, decode or encode. The result holds the findings; no value or output exists.
pub(all) suberror CodecFailure {
  CodecFailure(CodecResult)
} derive(Debug)

///|
/// Findings and the shared work meter of one request.
priv struct Request {
  limits : CodecLimits
  meter : @validation.WorkMeter
  findings : Array[CodecFinding]
  mut complete : Bool
}

///|
fn Request::new(limits : CodecLimits) -> Request {
  {
    limits,
    meter: @validation.WorkMeter::new(limits.work) catch {
      _ => panic()
    },
    findings: [],
    complete: true,
  }
}

///|
fn Request::stop(
  self : Request,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
  reason : String,
) -> Unit {
  if !self.complete {
    return
  }
  self.complete = false
  self.findings.push({
    code: LimitExceeded,
    path,
    shape,
    message: "I reached the " + reason + " limit before completing the request.",
  })
}

///|
fn Request::charge(
  self : Request,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
  units~ : Int32 = 1,
) -> Bool {
  if !self.complete {
    return false
  }
  if !self.meter.charge(units) {
    self.stop(path, shape, "work")
    return false
  }
  true
}

///|
fn Request::emit(
  self : Request,
  code : CodecCode,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
  message : String,
) -> Unit {
  if !self.complete {
    return
  }
  if self.findings.length() >= self.limits.findings - 1 {
    self.stop(path, shape, "findings")
    return
  }
  self.findings.push({ code, path, shape, message, })
}

///|
fn Request::result(self : Request) -> CodecResult {
  { findings: self.findings.copy(), complete: self.complete, }
}
