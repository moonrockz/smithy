///|
let encoding_trait : String = "smithy.serialization#jsonEncoding"

///|
let profiles_trait : String = "smithy.serialization#jsonProfiles"

///|
let untagged_trait : String = "smithy.serialization#untagged"

///|
let empty_as_absent_trait : String = "smithy.serialization#emptyAsAbsent"

///|
let bundle_trait : String = "smithy.serialization#jsonBundle"

///|
/// The capabilities that this contract preparation implements.
pub let capabilities : Array[String] = [
  "external", "internal", "adjacent", "tagArray", "untagged", "tuple", "dictionary",
  "entries", "forms", "adapters", "aliases", "bundles", "expandedWriter",
]

///|
priv struct RawUnion {
  style : String
  tag : String?
  content : String?
  unit : String?
  accept : Array[RawUnion]
}

///|
priv struct RawTuple {
  members : Array[String]
  rest : String?
  optional : String?
}

///|
priv struct RawDictionary {
  layout : String
  key : String?
  order : String?
  accept : Array[String]
}

///|
priv struct RawForm {
  union_member : String?
  kind : String
  adapter : String?
  field : String?
  absent_field : String?
  bind : String?
  positions : Array[String]?
  rest : String?
  write : (Array[String], Array[String])?
}

///|
priv struct RawRule {
  union_ : RawUnion?
  tuple : RawTuple?
  dictionary : RawDictionary?
  adapter : String?
  name : String?
  tag : String?
  aliases : Array[String]?
  absent : String?
  flatten : Bool
  forms : Array[RawForm]?
}

///|
fn empty_rule() -> RawRule {
  {
    union_: None,
    tuple: None,
    dictionary: None,
    adapter: None,
    name: None,
    tag: None,
    aliases: None,
    absent: None,
    flatten: false,
    forms: None,
  }
}

///|
fn fields(
  owner : @smithy.ShapeId,
  value : @smithy.NodeValue,
  what : String,
  allowed : Array[String],
) -> Map[String, @smithy.NodeValue] raise ContractError {
  guard value is Object(fields) else {
    raise InvalidDeclaration(owner, "I expected \{what} to be an object.")
  }
  for name, _ in fields {
    if !allowed.contains(name) {
      raise UnsupportedDeclaration(
        owner,
        "I do not implement the \{what} setting \{name.escape()}.",
      )
    }
  }
  fields
}

///|
fn text_field(
  owner : @smithy.ShapeId,
  fields : Map[String, @smithy.NodeValue],
  name : String,
  what : String,
) -> String? raise ContractError {
  match fields.get(name) {
    None => None
    Some(String(text)) => Some(text)
    Some(_) =>
      raise InvalidDeclaration(
        owner,
        "I expected the \{what} setting \{name} to be a string.",
      )
  }
}

///|
fn texts_field(
  owner : @smithy.ShapeId,
  fields : Map[String, @smithy.NodeValue],
  name : String,
  what : String,
) -> Array[String]? raise ContractError {
  match fields.get(name) {
    None => None
    Some(Array(items)) => {
      let out : Array[String] = []
      for item in items {
        guard item is String(text) else {
          raise InvalidDeclaration(
            owner,
            "I expected the \{what} setting \{name} to list strings.",
          )
        }
        out.push(text)
      }
      Some(out)
    }
    Some(_) =>
      raise InvalidDeclaration(
        owner,
        "I expected the \{what} setting \{name} to be a list.",
      )
  }
}

///|
fn parse_union_rule(
  owner : @smithy.ShapeId,
  value : @smithy.NodeValue,
) -> RawUnion raise ContractError {
  let f = fields(owner, value, "union rule", [
    "style", "tag", "content", "unit", "accept",
  ])
  guard text_field(owner, f, "style", "union rule") is Some(style) else {
    raise InvalidDeclaration(owner, "I expected a union rule style.")
  }
  let accept : Array[RawUnion] = []
  match f.get("accept") {
    None => ()
    Some(Array(items)) =>
      for item in items {
        let alternative = parse_union_rule(owner, item)
        if !alternative.accept.is_empty() {
          raise InvalidDeclaration(
            owner, "An accepted union layout cannot accept further layouts.",
          )
        }
        accept.push(alternative)
      }
    Some(_) =>
      raise InvalidDeclaration(
        owner, "I expected a list of accepted union layouts.",
      )
  }
  {
    style,
    tag: text_field(owner, f, "tag", "union rule"),
    content: text_field(owner, f, "content", "union rule"),
    unit: text_field(owner, f, "unit", "union rule"),
    accept,
  }
}

///|
fn parse_dictionary_rule(
  owner : @smithy.ShapeId,
  value : @smithy.NodeValue,
) -> RawDictionary raise ContractError {
  let f = fields(owner, value, "dictionary rule", [
    "layout", "key", "order", "accept",
  ])
  guard text_field(owner, f, "layout", "dictionary rule") is Some(layout) else {
    raise InvalidDeclaration(owner, "I expected a dictionary layout.")
  }
  {
    layout,
    key: text_field(owner, f, "key", "dictionary rule"),
    order: text_field(owner, f, "order", "dictionary rule"),
    accept: texts_field(owner, f, "accept", "dictionary rule").unwrap_or([]),
  }
}

///|
fn parse_rule(
  owner : @smithy.ShapeId,
  value : @smithy.NodeValue,
) -> RawRule raise ContractError {
  let f = fields(owner, value, "encoding rule", [
    "union", "tuple", "dictionary", "adapter", "name", "tag", "aliases", "absent",
    "flatten", "forms",
  ])
  let tuple = match f.get("tuple") {
    None => None
    Some(v) => {
      let t = fields(owner, v, "tuple rule", ["members", "rest", "optional"])
      guard texts_field(owner, t, "members", "tuple rule") is Some(members) else {
        raise InvalidDeclaration(
          owner, "I expected the tuple member positions.",
        )
      }
      Some({
        members,
        rest: text_field(owner, t, "rest", "tuple rule"),
        optional: text_field(owner, t, "optional", "tuple rule"),
      })
    }
  }
  let forms = match f.get("forms") {
    None => None
    Some(Array(items)) => {
      let out : Array[RawForm] = []
      for item in items {
        let g = fields(owner, item, "form", [
          "member", "read", "bind", "positions", "rest", "write",
        ])
        guard g.get("read") is Some(read) else {
          raise InvalidDeclaration(owner, "I expected a form reader guard.")
        }
        let r = fields(owner, read, "form reader guard", [
          "kind", "adapter", "field", "absent",
        ])
        guard text_field(owner, r, "kind", "form reader guard") is Some(kind) else {
          raise InvalidDeclaration(
            owner, "I expected the JSON kind of a form reader guard.",
          )
        }
        let write = match g.get("write") {
          None => None
          Some(w) => {
            let w = fields(owner, w, "form writer guard", ["empty", "present"])
            Some(
              (
                texts_field(owner, w, "empty", "form writer guard").unwrap_or([]),
                texts_field(owner, w, "present", "form writer guard").unwrap_or([],
                ),
              ),
            )
          }
        }
        out.push({
          union_member: text_field(owner, g, "member", "form"),
          kind,
          adapter: text_field(owner, r, "adapter", "form reader guard"),
          field: text_field(owner, r, "field", "form reader guard"),
          absent_field: text_field(owner, r, "absent", "form reader guard"),
          bind: text_field(owner, g, "bind", "form"),
          positions: texts_field(owner, g, "positions", "form"),
          rest: text_field(owner, g, "rest", "form"),
          write,
        })
      }
      Some(out)
    }
    Some(_) => raise InvalidDeclaration(owner, "I expected a list of forms.")
  }
  {
    union_: match f.get("union") {
      None => None
      Some(v) => Some(parse_union_rule(owner, v))
    },
    tuple,
    dictionary: match f.get("dictionary") {
      None => None
      Some(v) => Some(parse_dictionary_rule(owner, v))
    },
    adapter: text_field(owner, f, "adapter", "encoding rule"),
    name: text_field(owner, f, "name", "encoding rule"),
    tag: text_field(owner, f, "tag", "encoding rule"),
    aliases: texts_field(owner, f, "aliases", "encoding rule"),
    absent: text_field(owner, f, "absent", "encoding rule"),
    flatten: match f.get("flatten") {
      None | Some(Boolean(false)) => false
      Some(Boolean(true)) => true
      Some(_) =>
        raise InvalidDeclaration(owner, "I expected flatten to be a boolean.")
    },
    forms,
  }
}

///|
/// The base rule and the profile rules of one shape or member.
priv struct Encoding {
  base : RawRule?
  profiles : Map[String, RawRule]
}

///|
fn shape_encoding(
  shape : @smithy.Shape,
  declared : Map[ProfileId, ProfileDeclaration],
) -> Encoding raise ContractError {
  guard shape.trait_value(encoding_trait) is Some(value) else {
    return { base: None, profiles: Map([]), }
  }
  let f = fields(shape.id, value, "jsonEncoding trait", ["base", "profiles"])
  let profiles : Map[String, RawRule] = Map([])
  match f.get("profiles") {
    None => ()
    Some(Object(rules)) =>
      for name, rule in rules {
        let id = ProfileId::parse(name) catch {
          _ =>
            raise InvalidDeclaration(
              shape.id,
              "I expected a profile identifier, but found \{name.escape()}.",
            )
        }
        guard declared.contains(id) else {
          raise InvalidDeclaration(
            shape.id,
            "I found rules for the undeclared profile \{id}.",
          )
        }
        profiles[name] = parse_rule(shape.id, rule)
      }
    Some(_) =>
      raise InvalidDeclaration(
        shape.id,
        "I expected the profile rules to be an object.",
      )
  }
  {
    base: match f.get("base") {
      None => None
      Some(v) => Some(parse_rule(shape.id, v))
    },
    profiles,
  }
}

///|
/// A declared serialization profile.
pub struct ProfileDeclaration {
  id : ProfileId
  declared_on : @smithy.ShapeId
  /// The profile whose shape rules this profile uses. It is `id` unless the declaration names another.
  rule_set : ProfileId
  writer : WriterMode
  unknown_members : UnknownMemberPolicy
  requires : Array[String]
  priv defaults : RawRule
}

///|
fn parse_profile(
  owner : @smithy.ShapeId,
  value : @smithy.NodeValue,
) -> ProfileDeclaration raise ContractError {
  let f = fields(owner, value, "profile declaration", [
    "id", "documentation", "ruleSet", "writer", "unknownMembers", "defaults", "requires",
  ])
  let parse_id = fn(text : String) raise ContractError {
    ProfileId::parse(text) catch {
      InvalidIdentity(_, message) => raise InvalidDeclaration(owner, message)
    }
  }
  guard text_field(owner, f, "id", "profile declaration") is Some(id) else {
    raise InvalidDeclaration(owner, "I expected a profile identifier.")
  }
  let id = parse_id(id)
  let rule_set = match text_field(owner, f, "ruleSet", "profile declaration") {
    None => id
    Some(text) => parse_id(text)
  }
  let writer = match text_field(owner, f, "writer", "profile declaration") {
    None | Some("canonical") => Canonical
    Some("expanded") => Expanded
    Some(other) =>
      raise UnsupportedDeclaration(
        owner,
        "I do not implement the writer mode \{other.escape()} of profile \{id}.",
      )
  }
  let unknown_members = match
    text_field(owner, f, "unknownMembers", "profile declaration") {
    None | Some("reject") => RejectUnknown
    Some("ignore") => IgnoreUnknown
    Some(other) =>
      raise UnsupportedDeclaration(
        owner,
        "I do not implement the unknown-member policy \{other.escape()} of profile \{id}.",
      )
  }
  let defaults = match f.get("defaults") {
    None => empty_rule()
    Some(v) => {
      let d = fields(owner, v, "profile defaults", ["union", "dictionary"])
      {
        ..empty_rule(),
        union_: match d.get("union") {
          None => None
          Some(u) => Some(parse_union_rule(owner, u))
        },
        dictionary: match d.get("dictionary") {
          None => None
          Some(u) => Some(parse_dictionary_rule(owner, u))
        },
      }
    }
  }
  let requires = texts_field(owner, f, "requires", "profile declaration").unwrap_or([],
  )
  for capability in requires {
    guard capabilities.contains(capability) else {
      raise UnsupportedDeclaration(
        owner,
        "Profile \{id} requires the capability \{capability.escape()}, which I do not implement.",
      )
    }
  }
  if rule_set != id && f.get("defaults") is Some(_) {
    raise InvalidDeclaration(
      owner,
      "Profile \{id} uses the rules of \{rule_set}, so it cannot declare its own defaults.",
    )
  }
  {
    id,
    declared_on: owner,
    rule_set,
    writer,
    unknown_members,
    requires,
    defaults,
  }
}

///|
/// Every profile declared in the model, by identifier. Two declarations of one identifier are a conflict.
pub fn declared_profiles(
  model : @smithy.Model,
) -> Map[ProfileId, ProfileDeclaration] raise ContractError {
  let out : Map[ProfileId, ProfileDeclaration] = Map([])
  let ids = model.shapes.keys().to_array()
  ids.sort_by((a, b) => a.to_string().compare(b.to_string()))
  for id in ids {
    let shape = model.shapes.get(id).unwrap()
    guard shape.trait_value(profiles_trait) is Some(value) else { continue }
    guard value is Array(items) else {
      raise InvalidDeclaration(id, "I expected a list of profile declarations.")
    }
    for item in items {
      let declaration = parse_profile(id, item)
      if out.get(declaration.id) is Some(previous) {
        raise ConflictingDeclaration(
          id,
          "Profile \{declaration.id} is already declared on \{previous.declared_on}.",
        )
      }
      out[declaration.id] = declaration
    }
  }
  for _, declaration in out {
    if declaration.rule_set != declaration.id {
      guard out.get(declaration.rule_set) is Some(base) else {
        raise InvalidDeclaration(
          declaration.declared_on,
          "Profile \{declaration.id} uses the rules of the undeclared profile \{declaration.rule_set}.",
        )
      }
      guard base.rule_set == base.id else {
        raise InvalidDeclaration(
          declaration.declared_on,
          "Profile \{declaration.id} uses the rules of \{base.id}, which uses the rules of another profile.",
        )
      }
    }
  }
  out
}
