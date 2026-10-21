///|
/// Serialized HTTP messages. Query strings retain wire spelling and duplicates;
/// headers retain repeated values. The host is the resolved destination host.
pub(all) enum HttpMessage {
  Request(
    verb~ : String,
    uri~ : String,
    query~ : Array[String],
    host~ : String?,
    headers~ : Array[(String, String)],
    body~ : Bytes
  )
  Response(code~ : Int32, headers~ : Array[(String, String)], body~ : Bytes)
} derive(Eq, Debug)

///|
pub(all) enum Field {
  MessageKind
  Method
  Uri
  Host
  QueryParameter(String)
  ForbiddenQueryParameter(String)
  RequiredQueryParameter(String)
  Status
  Header(String)
  ForbiddenHeader(String)
  RequiredHeader(String)
  Body
  Implementation
} derive(Eq, Debug)

///|
pub(all) struct Mismatch {
  field : Field
  expected : String
  actual : String
} derive(Eq, Debug)

///|
pub(all) enum Outcome {
  Matched
  Mismatched(Array[Mismatch])
  Skipped
} derive(Eq, Debug)

///|
/// An adapter supplies the protocol implementation, configuration and model.
/// It receives one complete case and returns the produced HTTP message.
pub(open) trait Protocol {
  fn produce(Self, Case) -> HttpMessage raise
}

///|
fn header_values(
  headers : Array[(String, String)],
  name : String,
) -> Array[String] {
  headers
  .iter()
  .filter_map(pair => {
    if pair.0.to_lower() == name.to_lower() {
      Some(pair.1)
    } else {
      None
    }
  })
  .collect()
}

///|
fn query_name(param : String) -> String {
  param.split("=").to_array()[0].to_owned()
}

///|
/// JSON compares native values with exact numbers; text compares UTF-8 bytes.
/// Binary media types use the specification's base64 representation.
/// Supply a comparator for XML or other formats with semantic equivalence.
pub fn default_body_matches(
  expected : String,
  actual : Bytes,
  media : String?,
) -> Bool {
  let media = media.unwrap_or("").split(";").to_array()[0]
    .trim()
    .to_owned()
    .to_lower()
  try {
    if media == "application/json" || media.has_suffix("+json") {
      @smithy.NodeValue::from_json(@json.parse(expected)) ==
      @smithy.NodeValue::from_json(@json.parse(@utf8.decode(actual)))
    } else if media == "" ||
      media.has_prefix("text/") ||
      media.has_suffix("xml") ||
      media == "application/x-www-form-urlencoded" {
      @utf8.encode(expected) == actual
    } else {
      @base64.decode(expected) == actual
    }
  } catch {
    _ => false
  }
}

///|
pub fn Case::compare(
  self : Case,
  actual : HttpMessage,
  body_matches~ : (String, Bytes, String?) -> Bool = default_body_matches,
) -> Outcome {
  let mismatches : Array[Mismatch] = []
  let expected = self.definition
  fn mismatch(field : Field, expected : String, actual : String) -> Unit {
    mismatches.push({ field, expected, actual, })
  }
  let (headers, body) = match (self.subject, actual) {
    (
      Subject::Request(..),
      HttpMessage::Request(verb~, uri~, query~, host~, headers~, body~),
    ) => {
      for (key, field, actual) in [("method", Method, verb), ("uri", Uri, uri)] {
        if text(expected, key) is Some(wanted) && wanted != actual {
          mismatch(field, wanted, actual)
        }
      }
      let wanted_host = text(expected, "resolvedHost")
      if wanted_host is Some(wanted) && Some(wanted) != host {
        mismatch(Host, wanted, host.unwrap_or("<absent>"))
      }
      let expected_query = strings(expected, "queryParams")
      let names : Set[String] = Set([])
      for param in expected_query {
        names.add(query_name(param))
      }
      let sorted_names = names.to_array()
      sorted_names.sort()
      for name in sorted_names {
        let wanted = expected_query.filter(p => query_name(p) == name)
        let found = query.filter(p => query_name(p) == name)
        wanted.sort()
        found.sort()
        if wanted != found {
          mismatch(QueryParameter(name), wanted.join("&"), found.join("&"))
        }
      }
      for name in strings(expected, "forbidQueryParams") {
        if query.iter().any(p => query_name(p) == name) {
          mismatch(ForbiddenQueryParameter(name), "absent", "present")
        }
      }
      for name in strings(expected, "requireQueryParams") {
        if !query.iter().any(p => query_name(p) == name) {
          mismatch(RequiredQueryParameter(name), "present", "absent")
        }
      }
      (headers, body)
    }
    (
      Subject::Response(..)
      | ErrorResponse(..),
      HttpMessage::Response(code~, headers~, body~),
    ) => {
      let wanted = field(expected, "code")
        .map(v => v.to_json().stringify())
        .unwrap_or("")
      if @smithy.NodeNumber::parse(wanted) !=
        @smithy.NodeNumber::parse(code.to_string()) {
        mismatch(Status, wanted, code.to_string())
      }
      (headers, body)
    }
    _ => {
      mismatch(MessageKind, "matching request/response kind", "different kind")
      return Mismatched(mismatches)
    }
  }
  if field(expected, "headers") is Some(Object(wanted)) {
    let names = wanted.keys().to_array()
    names.sort()
    for name in names {
      guard wanted.get(name) is Some(String(value)) else { continue }
      let found = header_values(headers, name)
      if found.join(", ") != value || found.is_empty() {
        mismatch(
          Header(name),
          value,
          if found.is_empty() {
            "<absent>"
          } else {
            found.join(", ")
          },
        )
      }
    }
  }
  for name in strings(expected, "forbidHeaders") {
    if !header_values(headers, name).is_empty() {
      mismatch(ForbiddenHeader(name), "absent", "present")
    }
  }
  for name in strings(expected, "requireHeaders") {
    if header_values(headers, name).is_empty() {
      mismatch(RequiredHeader(name), "present", "absent")
    }
  }
  if text(expected, "body") is Some(wanted) &&
    !body_matches(wanted, body, text(expected, "bodyMediaType")) {
    mismatch(Body, wanted, @base64.encode(body))
  }
  if mismatches.is_empty() {
    Matched
  } else {
    Mismatched(mismatches)
  }
}

///|
pub fn[P : Protocol] run(
  protocol : P,
  case_ : Case,
  side~ : Side,
  body_matches~ : (String, Bytes, String?) -> Bool = default_body_matches,
) -> Outcome {
  if !case_.applies_to(side) {
    return Skipped
  }
  let actual = protocol.produce(case_) catch {
    error =>
      return Mismatched([
        {
          field: Implementation,
          expected: "produced HTTP message",
          actual: error.to_string(),
        },
      ])
  }
  case_.compare(actual, body_matches~)
}
