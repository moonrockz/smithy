///|
/// One supported release interval of a bundle, with its semantic root and allowed profiles. The first
/// profile is the default.
pub struct ReleaseBinding {
  interval : ReleaseInterval
  root : @smithy.ShapeId
  profiles : Array[ProfileId]
} derive(Debug)

///|
/// A versioned document bundle declared with the jsonBundle trait.
pub struct BundleDeclaration {
  id : BundleId
  declared_on : @smithy.ShapeId
  version_field : WireName
  version_adapter : AdapterId
  releases : Array[ReleaseBinding]
} derive(Debug)

///|
/// The binding that supports `release`, if any.
pub fn BundleDeclaration::binding(
  self : BundleDeclaration,
  release : Release,
) -> ReleaseBinding? {
  for binding in self.releases {
    if binding.interval.contains(release) {
      return Some(binding)
    }
  }
  None
}

///|
fn parse_bundle(
  model : @smithy.Model,
  owner : @smithy.ShapeId,
  value : @smithy.NodeValue,
  profiles : Map[ProfileId, ProfileDeclaration],
) -> BundleDeclaration raise ContractError {
  let f = fields(owner, value, "jsonBundle trait", ["id", "version", "releases"])
  guard text_field(owner, f, "id", "jsonBundle trait") is Some(id) else {
    raise InvalidDeclaration(owner, "I expected a bundle identifier.")
  }
  let id = BundleId::parse(id) catch {
    InvalidIdentity(_, message) => raise InvalidDeclaration(owner, message)
  }
  guard f.get("version") is Some(version) else {
    raise InvalidDeclaration(owner, "I expected the bundle version location.")
  }
  let v = fields(owner, version, "bundle version", ["field", "adapter"])
  guard text_field(owner, v, "field", "bundle version") is Some(field) &&
    text_field(owner, v, "adapter", "bundle version") is Some(adapter) else {
    raise InvalidDeclaration(
      owner, "I expected the version field and its adapter.",
    )
  }
  guard f.get("releases") is Some(Array(items)) && !items.is_empty() else {
    raise InvalidDeclaration(owner, "I expected release bindings.")
  }
  let releases : Array[ReleaseBinding] = []
  for item in items {
    let r = fields(owner, item, "release binding", [
      "since", "until", "root", "profiles",
    ])
    guard text_field(owner, r, "since", "release binding") is Some(since) &&
      text_field(owner, r, "until", "release binding") is Some(until) &&
      text_field(owner, r, "root", "release binding") is Some(root) &&
      texts_field(owner, r, "profiles", "release binding") is Some(names) &&
      !names.is_empty() else {
      raise InvalidDeclaration(
        owner, "I expected since, until, root and profiles in each release binding.",
      )
    }
    let interval = ReleaseInterval::new(
      Release::parse(since),
      Release::parse(until),
    ) catch {
      InvalidIdentity(_, message) => raise InvalidDeclaration(owner, message)
    }
    guard @smithy.ShapeId::parse(root) is Some(root) &&
      model.shapes.get(root) is Some(root_shape) &&
      root_shape.body is (Structure(_) | Union(_)) else {
      raise InvalidDeclaration(
        owner,
        "I expected release root \{root.escape()} to be a structure or union.",
      )
    }
    let ids : Array[ProfileId] = []
    for name in names {
      let profile = ProfileId::parse(name) catch {
        InvalidIdentity(_, message) => raise InvalidDeclaration(owner, message)
      }
      guard profiles.contains(profile) else {
        raise InvalidDeclaration(
          owner,
          "Release \{interval} names the undeclared profile \{profile}.",
        )
      }
      ids.push(profile)
    }
    for previous in releases {
      if previous.interval.overlaps(interval) {
        raise InvalidDeclaration(
          owner,
          "Release intervals \{previous.interval} and \{interval} overlap.",
        )
      }
    }
    releases.push({ interval, root, profiles: ids, })
  }
  {
    id,
    declared_on: owner,
    version_field: wire_name(owner, field),
    version_adapter: adapter_id(owner, adapter),
    releases,
  }
}

///|
/// Every bundle declared in the model, by identifier.
pub fn declared_bundles(
  model : @smithy.Model,
) -> Map[BundleId, BundleDeclaration] raise ContractError {
  let profiles = declared_profiles(model)
  let out : Map[BundleId, BundleDeclaration] = Map([])
  let ids = model.shapes.keys().to_array()
  ids.sort_by((a, b) => a.to_string().compare(b.to_string()))
  for id in ids {
    let shape = model.shapes.get(id).unwrap()
    guard shape.trait_value(bundle_trait) is Some(value) else { continue }
    let bundle = parse_bundle(model, id, value, profiles)
    if out.get(bundle.id) is Some(previous) {
      raise ConflictingDeclaration(
        id,
        "Bundle \{bundle.id} is already declared on \{previous.declared_on}.",
      )
    }
    out[bundle.id] = bundle
  }
  out
}
