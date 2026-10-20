///|
pub(all) enum ResourceCode {
  UnsupportedTransport
  TransportFailure
  AcquisitionTimeout
  AuthenticationRequired
  MissingAsset
  HttpStatus
  InvalidArchive
  IntegrityFailure
  UnsafePath
  MissingResource
  DuplicateEntry
  DuplicateResource
  ResourceLimit
  InvalidLimits
  InvalidUtf8
  LocalIo
  DuplicateProvider
  DuplicateRepository
  UnknownProvider
  UnknownRepository
  InvalidResolution
  MissingSelection
  MissingRoot
  ProviderFailure
} derive(Eq, Debug)

///|
pub fn ResourceCode::to_string(self : ResourceCode) -> String {
  match self {
    UnsupportedTransport => "unsupported-transport"
    TransportFailure => "transport-failure"
    AcquisitionTimeout => "acquisition-timeout"
    AuthenticationRequired => "authentication-required"
    MissingAsset => "missing-asset"
    HttpStatus => "http-status"
    InvalidArchive => "invalid-archive"
    IntegrityFailure => "integrity-failure"
    UnsafePath => "unsafe-path"
    MissingResource => "missing-resource"
    DuplicateEntry => "duplicate-entry"
    DuplicateResource => "duplicate-resource"
    ResourceLimit => "resource-limit"
    InvalidLimits => "invalid-limits"
    InvalidUtf8 => "invalid-utf8"
    LocalIo => "local-io"
    DuplicateProvider => "duplicate-provider"
    DuplicateRepository => "duplicate-repository"
    UnknownProvider => "unknown-provider"
    UnknownRepository => "unknown-repository"
    InvalidResolution => "invalid-resolution"
    MissingSelection => "missing-selection"
    MissingRoot => "missing-root"
    ProviderFailure => "provider-failure"
  }
}

///|
pub impl Show for ResourceCode with fn output(self, logger) {
  logger.write_string(self.to_string())
}
