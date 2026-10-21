///|
pub(all) suberror ConfigurationError {
  ConfigurationError(String)
} derive(Debug)

///|
pub struct Limits {
  depth : Int32
  work : Int32
  findings : Int32
} derive(Eq, Debug)

///|
pub fn Limits::new(
  depth~ : Int32 = 128,
  work~ : Int32 = 100000,
  findings~ : Int32 = 100,
) -> Limits raise ConfigurationError {
  guard depth > 0 &&
    depth <= 1024 &&
    work > 0 &&
    work <= 10000000 &&
    findings > 0 &&
    findings <= 10000 else {
    raise ConfigurationError(
      "I expected depth 1..1024, work 1..10000000 and findings 1..10000.",
    )
  }
  { depth, work, findings, }
}

///|
pub(all) enum UnknownMembers {
  Reject
  Ignore
} derive(Eq, Debug)

///|
pub(all) enum MemberNames {
  Smithy
  JsonName
} derive(Eq, Debug)

///|
pub(all) enum TimestampFormat {
  EpochSeconds
  DateTime
} derive(Eq, Debug)

///|
pub(all) enum ValueProfile {
  JsonProfile
  NativeProfile
} derive(Eq, Debug)

///|
pub struct Config {
  profile : ValueProfile
  limits : Limits
  unknown_members : UnknownMembers
  member_names : MemberNames
  timestamp_format : TimestampFormat
  nonnumeric_floats : Bool
} derive(Eq, Debug)

///|
pub fn Config::new(
  profile~ : ValueProfile = JsonProfile,
  limits~ : Limits = { depth: 128, work: 100000, findings: 100, },
  unknown_members~ : UnknownMembers = Reject,
  member_names~ : MemberNames = Smithy,
  timestamp_format~ : TimestampFormat = EpochSeconds,
  nonnumeric_floats~ : Bool = false,
) -> Config {
  {
    profile,
    limits,
    unknown_members,
    member_names,
    timestamp_format,
    nonnumeric_floats,
  }
}

///|
pub(all) enum FindingSeverity {
  Error
  Advisory
} derive(Eq, Debug)

///|
pub(all) enum FindingCode {
  TypeMismatch
  RequiredMember
  UnknownMember
  DuplicateMember
  InvalidNumber
  NumericBounds
  Range
  Length
  Pattern
  UniqueItems
  EnumValue
  UnionMember
  InvalidEncoding
  InvalidTimestamp
  UnsupportedValue
  LimitExceeded
} derive(Eq, Debug)

///|
pub fn FindingCode::to_string(self : FindingCode) -> String {
  match self {
    TypeMismatch => "TypeMismatch"
    RequiredMember => "RequiredMember"
    UnknownMember => "UnknownMember"
    DuplicateMember => "DuplicateMember"
    InvalidNumber => "InvalidNumber"
    NumericBounds => "NumericBounds"
    Range => "Range"
    Length => "Length"
    Pattern => "Pattern"
    UniqueItems => "UniqueItems"
    EnumValue => "EnumValue"
    UnionMember => "UnionMember"
    InvalidEncoding => "InvalidEncoding"
    InvalidTimestamp => "InvalidTimestamp"
    UnsupportedValue => "UnsupportedValue"
    LimitExceeded => "LimitExceeded"
  }
}

///|
pub(all) struct Finding {
  code : FindingCode
  severity : FindingSeverity
  path : InstancePath
  shape : @smithy.ShapeId
  message : String
} derive(Eq, Debug)

///|
pub(all) struct ValidationResult {
  findings : Array[Finding]
  complete : Bool
} derive(Eq, Debug)

///|
pub fn ValidationResult::is_valid(self : ValidationResult) -> Bool {
  self.complete && !self.findings.iter().any(f => f.severity == Error)
}

///|
pub impl @json.ToJson for Finding with fn to_json(self) {
  Json::object({
    "code": Json::string(self.code.to_string()),
    "severity": Json::string(
      if self.severity == Error {
        "error"
      } else {
        "advisory"
      },
    ),
    "path": @json.to_json(self.path),
    "pointer": Json::string(self.path.pointer()),
    "shape": Json::string(self.shape.to_string()),
    "message": Json::string(self.message),
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

///|
pub fn Config::with_profile(self : Config, profile : ValueProfile) -> Config {
  { ..self, profile, }
}

///|
pub fn Config::profile(self : Config) -> ValueProfile {
  self.profile
}
