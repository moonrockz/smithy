///|
/// One example of the Morphir sources. `source` is the path in finos/morphir
/// and `at` is a JSON pointer, or "line N" for a row of the compatibility kit.
pub(all) struct Example {
  source : String
  at : String
  kind : Kind
  verdict : Verdict
  value : Json
} derive(Eq, Debug)

///|
/// A value of a lesson that quotes an example of the Morphir sources.
pub(all) struct Quote {
  lesson : String
  case_ : String
  file : String
  source : String
  at : String
}

///|
/// The quotes that the check proves: the lesson value must equal the upstream
/// node at the JSON pointer.
pub let quotes : Array[Quote] = [
  {
    lesson: "39-morphir-limits",
    case_: "start",
    file: "deal.json",
    source: "website/static/ir/examples/v4/books-and-records-example.json",
    at: "/distribution/Library/def/modules/books-and-records/Public/types/deal/Public/TypeAliasDefinition/typeExp",
  },
  {
    lesson: "39-morphir-limits",
    case_: "v3",
    file: "deal.json",
    source: "website/static/ir/examples/v3/greeting-example.json",
    at: "/distribution/3/modules/0/1/value/values/2/1/value/value/body/3/2/1/2/0/1/2/2/1",
  },
]

///|
/// The Morphir diagnostic of a rejected example, as the code that the value
/// check of the core gives. None for a diagnostic that the tour does not know.
pub fn rejected_code(diagnostic : String) -> String? {
  match diagnostic {
    "invalid_name" => Some("Pattern")
    "unknown_node" | "unknown_member" => Some("UnknownMember")
    "invalid_type" => Some("TypeMismatch")
    // The lesson model has no array form, so the check gives TypeMismatch.
    "breaks_max_items" => Some("TypeMismatch")
    _ => None
  }
}

///|
fn verdict_text(verdict : Verdict) -> String {
  match verdict {
    Accepted => "Accepted"
    Legacy(warning) => "Legacy(\{warning})"
    Rejected(diagnostic) => "Rejected(\{diagnostic})"
  }
}

///|
fn kind_text(kind : Kind) -> String {
  match kind {
    Name => "Name"
    Path => "Path"
    FQName => "FQName"
    Type => "Type"
    TypeAttributes => "TypeAttributes"
    SourceLocation => "SourceLocation"
  }
}

///|
/// One line of the review snapshot: `<verdict> <form> <kind> <source> <at>`.
/// The form is `expanded`, `unknown(<pointer>)`, or a `+` list of
/// `<spelling>(<pointer>,...)` in the order compact, accepted, legacy.
/// Each pointer is written as `#` and the JSON pointer, so the root is `#`.
/// Only an accepted example is sorted; the form of another verdict is `-`.
pub fn Example::line(self : Example) -> String {
  let form = match self.verdict {
    Accepted =>
      match sort(self.kind, self.value) {
        Expanded => "expanded"
        Other(found) => {
          let parts = []
          for spelling in [Compact, Wrapper, Legacy] {
            let pointers = found
              .filter(fn(f) { f.spelling == spelling })
              .map(fn(f) { "#" + f.pointer })
            if !pointers.is_empty() {
              parts.push("\{spelling.label()}(\{pointers.join(",")})")
            }
          }
          parts.join("+")
        }
        Unknown(pointer) => "unknown(#\{pointer})"
      }
    _ => "-"
  }
  "\{verdict_text(self.verdict)} \{form} \{kind_text(self.kind)} \{self.source} \{self.at}"
}

///|
fn field(json : Json, name : String) -> Json? {
  match json {
    Object(members) => members.get(name)
    _ => None
  }
}

///|
fn items(json : Json?) -> Array[Json] {
  match json {
    Some(Array(items)) => items
    _ => []
  }
}

///|
/// The verdict of the schema on an example of one of its `oneOf` arms. An
/// array with more items than the `maxItems` of its arm breaks the schema,
/// although the schema gives it as an example.
fn arm_verdict(arm : Json, value : Json) -> Verdict {
  match (field(arm, "maxItems"), value) {
    (Some(Number(max, ..)), Array(values)) if values.length().to_double() > max =>
      Rejected("breaks_max_items")
    _ => Accepted
  }
}

///|
/// The examples of the in-scope definitions of the JSON Schema, with the
/// examples of each `oneOf` arm.
pub fn schema_examples(schema : Json) -> Array[Example] {
  let source = "website/static/schemas/morphir-ir-v4.json"
  let definitions : Array[(String, Kind)] = [
    ("NameString", Name),
    ("Name", Name),
    ("PathString", Path),
    ("Path", Path),
    ("FQNameString", FQName),
    ("FQName", FQName),
    ("TypeAttributes", TypeAttributes),
    ("SourceLocation", SourceLocation),
    ("VariableType", Type),
    ("ReferenceType", Type),
    ("TupleType", Type),
    ("RecordType", Type),
    ("ExtensibleRecordType", Type),
    ("FunctionType", Type),
    ("UnitType", Type),
  ]
  let out = []
  for entry in definitions {
    let (name, kind) = entry
    guard field(schema, "definitions").bind(fn(d) { field(d, name) })
      is Some(definition) else {
      continue
    }
    let base = "/definitions/\{name}"
    for i, value in items(field(definition, "examples")) {
      out.push({
        source,
        at: "\{base}/examples/\{i}",
        kind,
        verdict: Accepted,
        value,
      })
    }
    for j, arm in items(field(definition, "oneOf")) {
      for i, value in items(field(arm, "examples")) {
        out.push({
          source,
          at: "\{base}/oneOf/\{j}/examples/\{i}",
          kind,
          verdict: arm_verdict(arm, value),
          value,
        })
      }
    }
  }
  out
}

///|
fn is_type_key(key : String) -> Bool {
  match key {
    "typeExp"
    | "baseType"
    | "partialTypeExp"
    | "outputType"
    | "output"
    | "expectedType"
    | "inferredType" => true
    _ => false
  }
}

///|
fn walk_document(
  source : String,
  node : Json,
  pointer : String,
  out : Array[Example],
) -> Unit {
  fn push(at : String, value : Json) {
    out.push({ source, at, kind: Type, verdict: Accepted, value, })
  }

  match node {
    Array(children) =>
      for i, child in children {
        walk_document(source, child, "\{pointer}/\{i}", out)
      }
    Object(members) =>
      for key, value in members {
        let at = "\{pointer}/\{escape_token(key)}"
        if is_type_key(key) {
          push(at, value)
        } else if (key == "inputs" || key == "inputTypes") &&
          value is Object(map) {
          for name, tpe in map {
            push("\{at}/\{escape_token(name)}", tpe)
          }
        } else if key == "inputs" && value is Array(pairs) {
          for i, pair in pairs {
            match pair {
              Array([_, tpe]) => push("\{at}/\{i}/1", tpe)
              _ => walk_document(source, pair, "\{at}/\{i}", out)
            }
          }
        } else if key == "constructors" && value is Object(map) {
          for name, args in map {
            let base = "\{at}/\{escape_token(name)}"
            for i, pair in items(Some(args)) {
              match pair {
                Array([_, tpe]) => push("\{base}/\{i}/1", tpe)
                _ => walk_document(source, pair, "\{base}/\{i}", out)
              }
            }
          }
        } else {
          walk_document(source, value, at, out)
        }
      }
    _ => ()
  }
}

///|
/// The type nodes of an IR example file: the value of a type key, the types
/// of the inputs, and the argument types of the constructors. A found node is
/// not walked into.
pub fn file_examples(source : String, document : Json) -> Array[Example] {
  let out = []
  walk_document(source, document, "", out)
  out
}

///|
/// The examples of the naming corpus of Morphir.
pub fn naming_examples(source : String, corpus : Json) -> Array[Example] {
  let out = []
  fn push(at : String, kind : Kind, verdict : Verdict, value : Json?) {
    if value is Some(value) {
      out.push({ source, at, kind, verdict, value, })
    }
  }

  fn canonical(case_ : Json) -> Json? {
    field(case_, "canonical").bind(fn(c) { field(c, "uppercase") })
  }

  for i, c in items(field(corpus, "roundTripCases")) {
    push(
      "/roundTripCases/\{i}/canonical/uppercase",
      Name,
      Accepted,
      canonical(c),
    )
  }
  for i, c in items(field(corpus, "legacyDecodeCases")) {
    let base = "/legacyDecodeCases/\{i}"
    push("\{base}/canonical/uppercase", Name, Accepted, canonical(c))
    push("\{base}/legacyArray", Name, Accepted, field(c, "legacyArray"))
  }
  for i, c in items(field(corpus, "rejectCases")) {
    let valid = match
      field(c, "validAs").bind(fn(v) { field(v, "uppercase") }) {
      Some(True) => true
      _ => false
    }
    let verdict = if valid { Accepted } else { Rejected("invalid_name") }
    push("/rejectCases/\{i}/input", Name, verdict, field(c, "input"))
  }
  for i, c in items(field(corpus, "pathCases")) {
    push("/pathCases/\{i}/canonical/uppercase", Path, Accepted, canonical(c))
  }
  for i, c in items(field(corpus, "fqNameCases")) {
    push(
      "/fqNameCases/\{i}/canonical/uppercase",
      FQName,
      Accepted,
      canonical(c),
    )
  }
  out
}
