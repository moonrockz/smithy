///|
/// A decoded document of a versioned bundle. It keeps the exact release that selected its root.
pub struct VersionedValue {
  priv release : @contract.Release
  priv profile : @contract.ProfileId
  priv value : CodecValue
} derive(Eq, Debug)

///|
pub fn VersionedValue::release(self : VersionedValue) -> @contract.Release {
  self.release
}

///|
/// The profile that read the document.
pub fn VersionedValue::profile(self : VersionedValue) -> @contract.ProfileId {
  self.profile
}

///|
pub fn VersionedValue::value(self : VersionedValue) -> CodecValue {
  self.value
}

///|
priv struct PreparedBinding {
  binding : @contract.ReleaseBinding
  codecs : Array[(@contract.ProfileId, PreparedCodec)]
}

///|
/// A prepared versioned document bundle. It selects one root and profile from the document's version
/// before it decodes the payload, and it never converts a document to another release.
pub struct PreparedBundle {
  priv declaration : @contract.BundleDeclaration
  priv bindings : Array[PreparedBinding]
  priv adapters : AdapterRegistry
  priv limits : CodecLimits
}

///|
pub fn PreparedBundle::prepare(
  model : @smithy.Model,
  bundle : @contract.BundleId,
  adapters~ : AdapterRegistry = AdapterRegistry::new(),
  limits~ : CodecLimits = CodecLimits::default(),
) -> PreparedBundle raise @contract.ContractError {
  let declarations = @contract.declared_bundles(model)
  guard declarations.get(bundle) is Some(declaration) else {
    raise @contract.UnknownBundle(bundle)
  }
  guard adapters.get(declaration.version_adapter) is Some(version) else {
    raise @contract.MissingAdapter(
      declaration.declared_on,
      declaration.version_adapter,
    )
  }
  guard version.signature.output == StringKind else {
    raise @contract.InvalidDeclaration(
      declaration.declared_on,
      "Version adapter \{declaration.version_adapter} must produce release text.",
    )
  }
  let bindings : Array[PreparedBinding] = []
  for binding in declaration.releases {
    let codecs : Array[(@contract.ProfileId, PreparedCodec)] = []
    for profile in binding.profiles {
      let codec = PreparedCodec::prepare(
        model,
        binding.root,
        profile=Some(profile),
        adapters~,
        limits~,
      )
      let field = codec.contract.shapes.get(binding.root).unwrap().members.search_by(m => {
          m.wire == declaration.version_field
        },
      )
      guard field is Some(_) else {
        raise @contract.InvalidDeclaration(
          binding.root,
          "The root has no member with the version field \{declaration.version_field}.",
        )
      }
      codecs.push((profile, codec))
    }
    bindings.push({ binding, codecs, })
  }
  { declaration, bindings, adapters, limits, }
}

///|
pub fn PreparedBundle::declaration(
  self : PreparedBundle,
) -> @contract.BundleDeclaration {
  self.declaration
}

///|
/// The codec of `release` under `profile`, or under the release's default profile.
pub fn PreparedBundle::codec(
  self : PreparedBundle,
  release : @contract.Release,
  profile~ : @contract.ProfileId? = None,
) -> PreparedCodec? {
  for prepared in self.bindings {
    if prepared.binding.interval.contains(release) {
      for entry in prepared.codecs {
        if profile is None || profile == Some(entry.0) {
          return Some(entry.1)
        }
      }
    }
  }
  None
}

///|
/// Read the version of a parsed document and select its codec. Findings go to the request.
fn PreparedBundle::dispatch(
  self : PreparedBundle,
  request : Request,
  json : Json,
  profile : @contract.ProfileId?,
) -> (@contract.Release, @contract.ProfileId, PreparedCodec)? {
  let root = @validation.InstancePath::root()
  let anchor = self.declaration.declared_on
  let field = self.declaration.version_field.to_string()
  let at = field_path(root, field)
  guard json is Object(fields) else {
    request.emit(KindMismatch, root, anchor, expected(ObjectKind, json))
    return None
  }
  guard fields.get(field) is Some(version) else {
    request.emit(
      MissingVersion,
      at,
      anchor,
      "I expected the version field \{field}, but found it absent.",
    )
    return None
  }
  let adapter = self.adapters.get(self.declaration.version_adapter).unwrap()
  if !adapter.signature.inputs.contains(@contract.JsonKind::of(version)) {
    request.emit(
      InvalidVersion,
      at,
      anchor,
      "I expected a version, but found \{@contract.JsonKind::of(version)}.",
    )
    return None
  }
  if !request.charge(at, anchor) {
    return None
  }
  let read = (adapter.reader)(version, { meter: request.meter, })
  if request.meter.exhausted() {
    request.stop(at, anchor, "work")
    return None
  }
  let release = match read {
    Ok(Text(text)) =>
      @contract.Release::parse(text) catch {
        _ => {
          request.emit(
            InvalidVersion,
            at,
            anchor,
            "Version adapter \{adapter.id()} produced \{text.escape()}, which is not a release.",
          )
          return None
        }
      }
    Ok(_) => {
      request.emit(InvalidVersion, at, anchor, "I expected release text.")
      return None
    }
    Err(failure) => {
      request.emit(
        InvalidVersion,
        at.append(failure.path),
        anchor,
        failure.message,
      )
      return None
    }
  }
  guard self.bindings.search_by(b => b.binding.interval.contains(release))
    is Some(i) else {
    let supported = self.bindings
      .map(b => b.binding.interval.to_string())
      .join(", ")
    request.emit(
      UnsupportedVersion,
      at,
      anchor,
      "Release \{release} is outside the supported releases \{supported} of bundle \{self.declaration.id}.",
    )
    return None
  }
  let prepared = self.bindings[i]
  match profile {
    None => {
      let (id, codec) = prepared.codecs[0]
      Some((release, id, codec))
    }
    Some(wanted) =>
      match prepared.codecs.search_by(entry => entry.0 == wanted) {
        Some(j) => Some((release, wanted, prepared.codecs[j].1))
        None => {
          request.emit(
            VersionConflict,
            at,
            anchor,
            "The document declares release \{release}, which profile \{wanted} does not read.",
          )
          None
        }
      }
  }
}

///|
fn PreparedBundle::read_text(
  self : PreparedBundle,
  request : Request,
  text : String,
  profile : @contract.ProfileId?,
) -> VersionedValue? {
  guard parse_text(request, text, self.declaration.declared_on) is Some(json) else {
    return None
  }
  guard self.dispatch(request, json, profile) is Some((release, id, codec)) else {
    return None
  }
  match codec.read_parsed(request, json) {
    Some(value) =>
      Some({ release, profile: id, value: { root: codec.root, value, }, })
    None => None
  }
}

///|
/// Check a versioned document. An explicit profile must read the document's release.
pub fn PreparedBundle::check(
  self : PreparedBundle,
  text : String,
  profile~ : @contract.ProfileId? = None,
) -> CodecResult {
  let request = Request::new(self.limits)
  ignore(self.read_text(request, text, profile))
  request.result()
}

///|
pub fn PreparedBundle::decode(
  self : PreparedBundle,
  text : String,
  profile~ : @contract.ProfileId? = None,
) -> VersionedValue raise CodecFailure {
  let request = Request::new(self.limits)
  match self.read_text(request, text, profile) {
    Some(value) => value
    None => raise CodecFailure(request.result())
  }
}

///|
fn PreparedBundle::encode_in(
  self : PreparedBundle,
  request : Request,
  value : VersionedValue,
  profile : @contract.ProfileId?,
) -> String? {
  let root = @validation.InstancePath::root()
  let anchor = self.declaration.declared_on
  let profile = match profile {
    Some(p) => p
    None => value.profile
  }
  guard self.codec(value.release, profile=Some(profile)) is Some(codec) else {
    request.emit(
      VersionConflict,
      root,
      anchor,
      "Profile \{profile} does not write release \{value.release} of bundle \{self.declaration.id}.",
    )
    return None
  }
  // The version member of the value must name the same release.
  let field = codec.contract.shapes.get(codec.contract.root).unwrap().members
    .search_by(m => m.wire == self.declaration.version_field)
    .unwrap()
  let name = codec.contract.shapes.get(codec.contract.root).unwrap().members[field].name
  match value.value.value.get(name) {
    Some(String(text)) =>
      if !same_release(text, value.release) {
        request.emit(
          VersionConflict,
          field_path(root, name),
          anchor,
          "The value's version \{text.escape()} differs from its release \{value.release}.",
        )
        return None
      }
    _ => {
      request.emit(
        VersionConflict,
        field_path(root, name),
        anchor,
        "I expected the value to hold its release text.",
      )
      return None
    }
  }
  codec.encode_in(request, value.value)
}

///|
/// Encode a versioned value with the canonical spelling of its own release. A profile that does not write
/// that release is refused; no value is converted to another release.
pub fn PreparedBundle::encode(
  self : PreparedBundle,
  value : VersionedValue,
  profile~ : @contract.ProfileId? = None,
) -> String raise CodecFailure {
  let request = Request::new(self.limits)
  match self.encode_in(request, value, profile) {
    Some(text) => text
    None => raise CodecFailure(request.result())
  }
}

///|
/// Decode with the document's release and re-encode with `profile`, or the reading profile. One request
/// budget covers both.
pub fn PreparedBundle::canonicalize(
  self : PreparedBundle,
  text : String,
  profile~ : @contract.ProfileId? = None,
  output~ : @contract.ProfileId? = None,
) -> String raise CodecFailure {
  let request = Request::new(self.limits)
  guard self.read_text(request, text, profile) is Some(value) else {
    raise CodecFailure(request.result())
  }
  match self.encode_in(request, value, output) {
    Some(out) => out
    None => raise CodecFailure(request.result())
  }
}

///|
fn same_release(text : String, release : @contract.Release) -> Bool {
  (@contract.Release::parse(text) catch { _ => return false }) == release
}
