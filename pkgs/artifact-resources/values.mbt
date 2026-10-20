///|
fn valid_value(text : String) -> Bool {
  !text.is_empty() &&
  !text.iter().all(c => c == ' ') &&
  !text.iter().any(c => c.to_int() < 32 || c.to_int() == 127)
}

///|
pub struct RepositoryId {
  priv value : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn RepositoryId::parse(text : String) -> RepositoryId? {
  if valid_value(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn RepositoryId::to_string(self : RepositoryId) -> String {
  self.value
}

///|
pub impl Show for RepositoryId with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
pub struct ProviderId {
  priv value : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn ProviderId::parse(text : String) -> ProviderId? {
  if valid_value(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn ProviderId::to_string(self : ProviderId) -> String {
  self.value
}

///|
pub impl Show for ProviderId with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
pub struct ArtifactKey {
  priv value : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn ArtifactKey::parse(text : String) -> ArtifactKey? {
  if valid_value(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn ArtifactKey::to_string(self : ArtifactKey) -> String {
  self.value
}

///|
pub impl Show for ArtifactKey with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
pub struct ArtifactIdentity {
  priv value : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn ArtifactIdentity::parse(text : String) -> ArtifactIdentity? {
  if valid_value(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn ArtifactIdentity::to_string(self : ArtifactIdentity) -> String {
  self.value
}

///|
pub impl Show for ArtifactIdentity with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
pub struct RepositoryLocation {
  priv value : String
} derive(Eq, Hash, Compare, Debug)

///|
pub fn RepositoryLocation::parse(text : String) -> RepositoryLocation? {
  if valid_value(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn RepositoryLocation::to_string(self : RepositoryLocation) -> String {
  self.value
}

///|
pub impl Show for RepositoryLocation with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
pub struct EntryPath {
  priv value : String
} derive(Eq, Hash, Debug)

///|
pub impl Compare for EntryPath with fn compare(self, other) {
  self.value.lexical_compare(other.value)
}

///|
pub fn EntryPath::parse(text : String) -> EntryPath? {
  if valid_path(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn EntryPath::to_string(self : EntryPath) -> String {
  self.value
}

///|
pub impl Show for EntryPath with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
pub struct ResourceName {
  priv value : String
} derive(Eq, Hash, Debug)

///|
pub impl Compare for ResourceName with fn compare(self, other) {
  self.value.lexical_compare(other.value)
}

///|
pub fn ResourceName::parse(text : String) -> ResourceName? {
  if valid_path(text) {
    Some({ value: text, })
  } else {
    None
  }
}

///|
pub fn ResourceName::to_string(self : ResourceName) -> String {
  self.value
}

///|
pub impl Show for ResourceName with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
/// A relative entry path joined without normalizing or escaping its container.
pub fn EntryPath::join(self : EntryPath, child : EntryPath) -> EntryPath {
  { value: self.value + "/" + child.value, }
}

///|
pub fn EntryPath::relative_to(self : EntryPath, root : EntryPath) -> EntryPath? {
  let prefix = root.value + "/"
  if self.value.has_prefix(prefix) {
    Some({ value: self.value[prefix.length():].to_owned(), })
  } else {
    None
  }
}

///|
pub fn EntryPath::resource_name(self : EntryPath) -> ResourceName {
  { value: self.value, }
}

///|
pub(all) enum PathStyle {
  Slash
  Backslash
} derive(Eq, Debug)

///|
/// Physical location relationships remain data until a presentation boundary.
pub(all) enum Location {
  Source(RepositoryLocation)
  DirectoryEntry(Location, EntryPath, PathStyle)
  ArchiveEntry(Location, EntryPath)
} derive(Eq, Debug)

///|
pub fn Location::parse(text : String) -> Location? {
  RepositoryLocation::parse(text).map(value => Source(value))
}

///|
pub fn Location::directory_entry(
  self : Location,
  path : EntryPath,
  style~ : PathStyle = Slash,
) -> Location {
  DirectoryEntry(self, path, style)
}

///|
pub fn Location::archive_entry(self : Location, path : EntryPath) -> Location {
  ArchiveEntry(self, path)
}

///|
fn Location::within(self : Location, parent : Location) -> Bool {
  let mut current = self
  while true {
    if current == parent {
      return true
    }
    match current {
      Source(_) => return false
      DirectoryEntry(container, _, _) | ArchiveEntry(container, _) =>
        current = container
    }
  }
  false
}

///|
pub fn Location::to_string(self : Location) -> String {
  let suffixes = []
  let mut current = self
  let mut base = ""
  while true {
    match current {
      Source(location) => {
        base = location.to_string()
        break
      }
      DirectoryEntry(container, path, style) => {
        let separator = if style == Backslash { "\\" } else { "/" }
        suffixes.push(
          separator + path.value.replace_all(old="/", new=separator),
        )
        current = container
      }
      ArchiveEntry(container, path) => {
        suffixes.push("!/" + path.value)
        current = container
      }
    }
  }
  let out = StringBuilder()
  out.write_string(base)
  for i = suffixes.length() - 1; i >= 0; i = i - 1 {
    let suffix = suffixes[i]
    if i == suffixes.length() - 1 &&
      (
        (base.has_suffix("/") && suffix.has_prefix("/")) ||
        (base.has_suffix("\\") && suffix.has_prefix("\\"))
      ) {
      out.write_string(suffix[1:].to_owned())
    } else {
      out.write_string(suffix)
    }
  }
  out.to_string()
}

///|
pub impl Show for Location with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) struct Resolution {
  reference : ArtifactRef
  identity : ArtifactIdentity?
} derive(Eq, Debug)

///|
pub(all) enum ProvenanceStep {
  ResolutionStep(Resolution)
  ContainerStep(Location)
} derive(Eq, Debug)

///|
pub(all) enum ProvenanceOrigin {
  Physical(Location)
  ProviderRegistration(ProviderId)
  RepositoryReference(RepositoryId)
} derive(Eq, Debug)

///|
pub struct Provenance {
  origin : ProvenanceOrigin
  priv history : Array[ProvenanceStep]
} derive(Eq, Debug)

///|
pub fn Provenance::new(location : Location) -> Provenance {
  { origin: Physical(location), history: [], }
}

///|
pub fn Provenance::provider_registration(provider : ProviderId) -> Provenance {
  { origin: ProviderRegistration(provider), history: [], }
}

///|
pub fn Provenance::repository_reference(
  repository : RepositoryId,
) -> Provenance {
  { origin: RepositoryReference(repository), history: [], }
}

///|
pub fn Provenance::location(self : Provenance) -> Location? {
  match self.origin {
    Physical(location) => Some(location)
    _ => None
  }
}

///|
pub fn Provenance::steps(self : Provenance) -> Array[ProvenanceStep] {
  self.history.copy()
}

///|
pub fn Provenance::resolved(
  self : Provenance,
  reference : ArtifactRef,
  identity : ArtifactIdentity?,
) -> Provenance {
  let history = [ResolutionStep({ reference, identity, })]
  history.append(self.history)
  { ..self, history, }
}

///|
/// Compose histories and locations structurally, without inspecting rendered paths.
pub fn Provenance::through(
  self : Provenance,
  parent : Provenance,
) -> Provenance {
  let history = parent.history.copy()
  if parent.location() is Some(container) &&
    !(self.location() is Some(location) && location.within(container)) {
    history.push(ContainerStep(container))
  }
  history.append(self.history)
  { ..self, history, }
}

///|
pub fn Provenance::at(self : Provenance, location : Location) -> Provenance {
  { ..self, origin: Physical(location), }
}

///|
pub fn Provenance::to_string(self : Provenance) -> String {
  let parts = []
  for step in self.history {
    match step {
      ResolutionStep(resolution) => {
        parts.push(resolution.reference.to_string())
        if resolution.identity is Some(identity) {
          parts.push(identity.to_string())
        }
      }
      ContainerStep(location) => parts.push(location.to_string())
    }
  }
  parts.push(
    match self.origin {
      Physical(location) => location.to_string()
      ProviderRegistration(provider) => provider.to_string()
      RepositoryReference(repository) => repository.to_string()
    },
  )
  parts.join(" -> ")
}

///|
pub impl Show for Provenance with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub struct ContentDigest {
  priv bytes : FixedArray[Byte]
} derive(Eq, Debug)

///|
pub fn ContentDigest::sha256(data : Bytes) -> ContentDigest {
  { bytes: @crypto.sha256(data), }
}

///|
pub fn ContentDigest::parse(text : String) -> ContentDigest? {
  if !text.has_prefix("sha256:") || text.length() != 71 {
    return None
  }
  let bytes = FixedArray::make(32, b'\x00')
  fn digit(c : UInt16) -> Int32? {
    let n = c.to_int()
    if n >= 48 && n <= 57 {
      Some(n - 48)
    } else if n >= 97 && n <= 102 {
      Some(n - 87)
    } else if n >= 65 && n <= 70 {
      Some(n - 55)
    } else {
      None
    }
  }
  for i in 0..<32 {
    guard digit(text.code_unit_at(7 + i * 2)) is Some(high) &&
      digit(text.code_unit_at(8 + i * 2)) is Some(low) else {
      return None
    }
    bytes[i] = (high * 16 + low).to_byte()
  }
  Some({ bytes, })
}

///|
pub fn ContentDigest::to_string(self : ContentDigest) -> String {
  "sha256:" + @crypto.bytes_to_hex_string(self.bytes)
}

///|
pub impl Show for ContentDigest with fn output(self, logger) {
  logger.write_string(self.to_string())
}
