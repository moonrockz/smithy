///|
/// The shapes of the lesson model that an example is checked against.
pub(all) enum Kind {
  Name
  Path
  FQName
  Type
  TypeAttributes
  SourceLocation
} derive(Eq, Debug)

///|
/// The shape id of the lesson model for this kind.
pub fn Kind::shape(self : Kind) -> String {
  match self {
    Name => "morphir.ir.v4#Name"
    Path => "morphir.ir.v4#Path"
    FQName => "morphir.ir.v4#FQName"
    Type => "morphir.ir.v4#Type"
    TypeAttributes => "morphir.ir.v4#TypeAttributes"
    SourceLocation => "morphir.ir.v4#SourceLocation"
  }
}

///|
/// What Morphir says about an example in its own source.
pub(all) enum Verdict {
  Accepted
  Legacy(String)
  Rejected(String)
} derive(Eq, Debug)

///|
/// A Morphir spelling that is not the expanded spelling. `Compact` is a bare
/// string for a node. `Wrapper` is a node wrapper with a string or an array
/// payload, which the schema lists as an accepted format. `Legacy` is an array
/// for a name, a path, an FQName or a node.
pub(all) enum Spelling {
  Compact
  Wrapper
  Legacy
} derive(Eq, Debug)

///|
/// The label of the spelling in the review snapshot.
pub fn Spelling::label(self : Spelling) -> String {
  match self {
    Compact => "compact"
    Wrapper => "accepted"
    Legacy => "legacy"
  }
}

///|
/// One finding that the value check must report for an example in another
/// spelling.
pub(all) struct Expected {
  code : String
  pointer : String
  message : String
  spelling : Spelling
} derive(Eq, Debug)

///|
/// How an example is spelled. `Other` holds the findings of the spellings that
/// are not expanded. `Unknown` holds the JSON pointer of a spelling that the
/// sort does not know.
pub(all) enum Form {
  Expanded
  Other(Array[Expected])
  Unknown(String)
} derive(Eq, Debug)

///|
/// These are the messages of the value check of the core. The check of the
/// tour proves them against the core.
let union_string : String = "I expected a union value, but found string."

///|
let union_array : String = "I expected a union value, but found array."

///|
let structure_string : String = "I expected a structure value, but found string."

///|
let structure_array : String = "I expected a structure value, but found array."

///|
let string_array : String = "I expected a string value, but found array."

///|
/// What a member of a type payload holds.
priv enum Member {
  Leaf(Kind)
  Types
  TypeMap
}

///|
fn members_of(tag : String) -> Array[(String, Member)]? {
  match tag {
    "Variable" => Some([("name", Leaf(Name))])
    "Reference" => Some([("fqname", Leaf(FQName)), ("args", Types)])
    "Tuple" => Some([("elements", Types)])
    "Record" => Some([("fields", TypeMap)])
    "ExtensibleRecord" => Some([("variable", Leaf(Name)), ("fields", TypeMap)])
    "Function" =>
      Some([("parameterType", Leaf(Type)), ("returnType", Leaf(Type))])
    "Unit" => Some([])
    _ => None
  }
}

///|
/// A token of a JSON pointer (RFC 6901).
fn escape_token(token : String) -> String {
  token.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
priv struct Sorter {
  found : Array[Expected]
  mut unknown : String?
}

///|
fn Sorter::other(
  self : Sorter,
  pointer : String,
  spelling : Spelling,
  message : String,
) -> Unit {
  self.found.push({ code: "TypeMismatch", pointer, message, spelling, })
}

///|
fn Sorter::unknown_at(self : Sorter, pointer : String) -> Unit {
  if self.unknown is None {
    self.unknown = Some(pointer)
  }
}

///|
fn Sorter::node(
  self : Sorter,
  kind : Kind,
  value : Json,
  pointer : String,
) -> Unit {
  match kind {
    Name | Path | FQName =>
      match value {
        String(_) => ()
        Array(_) => self.other(pointer, Legacy, string_array)
        _ => self.unknown_at(pointer)
      }
    TypeAttributes | SourceLocation =>
      match value {
        Object(_) => ()
        _ => self.unknown_at(pointer)
      }
    Type => self.type_node(value, pointer)
  }
}

///|
fn Sorter::type_node(self : Sorter, value : Json, pointer : String) -> Unit {
  match value {
    String(_) => self.other(pointer, Compact, union_string)
    Array(_) => self.other(pointer, Legacy, union_array)
    Object(wrapper) => {
      if wrapper.length() != 1 {
        self.unknown_at(pointer)
        return
      }
      for tag, payload in wrapper {
        let at_tag = "\{pointer}/\{tag}"
        guard members_of(tag) is Some(members) else {
          self.unknown_at(pointer)
          continue
        }
        match payload {
          String(_) => self.other(at_tag, Wrapper, structure_string)
          Array(_) => self.other(at_tag, Wrapper, structure_array)
          Object(payload) =>
            for name, child in payload {
              let at_child = "\{at_tag}/\{escape_token(name)}"
              if name == "attributes" {
                self.node(TypeAttributes, child, at_child)
                continue
              }
              match members.search_by(fn(m) { m.0 == name }) {
                Some(i) => self.member_node(members[i].1, child, at_child)
                None => self.unknown_at(at_child)
              }
            }
          _ => self.unknown_at(pointer)
        }
      }
    }
    _ => self.unknown_at(pointer)
  }
}

///|
fn Sorter::member_node(
  self : Sorter,
  slot : Member,
  value : Json,
  pointer : String,
) -> Unit {
  match slot {
    Leaf(kind) => self.node(kind, value, pointer)
    Types =>
      match value {
        Array(items) =>
          for i, item in items {
            self.type_node(item, "\{pointer}/\{i}")
          }
        _ => self.unknown_at(pointer)
      }
    TypeMap =>
      match value {
        Object(fields) =>
          for name, field in fields {
            self.type_node(field, "\{pointer}/\{escape_token(name)}")
          }
        _ => self.unknown_at(pointer)
      }
  }
}

///|
/// Sorts an example by its JSON spelling. Expanded: every node has the
/// spelling of a Smithy value. Other: another spelling that Morphir accepts,
/// with the findings that the value check must report. Unknown: a spelling
/// that the sort does not know, so a person must look at it.
pub fn sort(kind : Kind, value : Json) -> Form {
  let sorter : Sorter = { found: [], unknown: None, }
  sorter.node(kind, value, "")
  match sorter.unknown {
    Some(pointer) => Unknown(pointer)
    None => if sorter.found.is_empty() { Expanded } else { Other(sorter.found) }
  }
}
