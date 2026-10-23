///|
fn http_trait(shape : Shape, name : String) -> Bool {
  shape.trait_value("smithy.api#" + name) is Some(_)
}

///|
fn http_string(shape : Shape, name : String) -> String? {
  match shape.trait_value("smithy.api#" + name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn http_ticked(names : Array[String]) -> String {
  let names = names.copy()
  names.sort()
  names.map(name => "`" + name + "`").join(", ")
}

///|
fn Model::http_members(self : Model, id : ShapeId) -> Array[Shape] {
  match self.shapes.get(id) {
    Some({ body: Structure(members), .. }) =>
      members.iter().filter_map(id => self.shapes.get(id)).to_array()
    _ => []
  }
}

///|
// Binding precedence follows HttpBindingIndex.createStructureBindings.
fn http_binding(member_ : Shape, request : Bool) -> String {
  for name in ["httpHeader", "httpPrefixHeaders"] {
    if http_trait(member_, name) {
      return name
    }
  }
  if request {
    for name in ["httpQuery", "httpQueryParams"] {
      if http_trait(member_, name) {
        return name
      }
    }
  }
  if http_trait(member_, "httpPayload") {
    return "httpPayload"
  }
  if request && http_trait(member_, "httpLabel") {
    return "httpLabel"
  }
  if !request && http_trait(member_, "httpResponseCode") {
    return "httpResponseCode"
  }
  "document"
}

///|
fn http_labels(pattern : String) -> Array[(String, Bool)] {
  let labels : Array[(String, Bool)] = []
  let mut offset = 0
  while offset < pattern.length() {
    guard pattern[offset:].find("{") is Some(start) else { break }
    let start = offset + start + 1
    guard pattern[start:].find("}") is Some(end) else { break }
    let value = pattern[start:start + end].to_owned()
    let greedy = value.has_suffix("+")
    labels.push(
      (
        if greedy {
          value[:value.length() - 1].to_owned()
        } else {
          value
        },
        greedy,
      ),
    )
    offset = start + end + 1
  }
  labels
}

///|
fn Model::http_structure_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let blocked = [
    "authorization", "connection", "content-length", "expect", "host", "max-forwards",
    "proxy-authenticate", "server", "te", "trailer", "transfer-encoding", "upgrade",
    "user-agent", "www-authenticate", "x-forwarded-for",
  ]
  for _, shape in self.shapes {
    if shape.body is Member(..) &&
      http_string(shape, "httpHeader") is Some(header) {
      let invalid = header
        .iter()
        .any(c => {
          !((c >= '0' && c <= '9') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= 'a' && c <= 'z') ||
          "!#$%&'*+-.^_`|~".contains(c.to_string()))
        })
      let message = if blocked.contains(header.to_lower()) {
        Some("`" + header + "` is not an allowed HTTP header binding")
      } else if invalid {
        Some(
          "`" +
          header +
          "` is not a valid HTTP header field name according to section 5.6.2 of RFC 9110",
        )
      } else {
        None
      }
      if message is Some(message) {
        events.push(
          validation_event("HttpHeaderTrait", "DANGER", Some(shape), message),
        )
      }
    }
    guard shape.body is Structure(_) else { continue }
    let members = self.http_members(shape.id)
    for
      (trait_name, validator, description) in [
        (
          "httpHeader", "HttpHeaderTrait", "field name binding conflicts found for the",
        ),
        (
          "httpQuery", "HttpQueryTrait", "parameter name binding conflicts found for the",
        ),
      ] {
      let groups : Map[String, Array[String]] = Map([])
      for member_ in members {
        if http_string(member_, trait_name) is Some(value) {
          let key = if trait_name == "httpHeader" {
            value.to_lower()
          } else {
            value
          }
          let names = groups.get(key).unwrap_or([])
          names.push(member_.id.member.unwrap())
          groups[key] = names
        }
      }
      for name, names in groups {
        if names.length() > 1 {
          events.push(
            validation_event(
              validator,
              "ERROR",
              Some(shape),
              "`" +
              trait_name +
              "` " +
              description +
              " `" +
              name +
              "` " +
              (if trait_name == "httpHeader" { "header" } else { "parameter" }) +
              " in the following structure members: " +
              http_ticked(names),
            ),
          )
        }
      }
    }
    let queries = members
      .filter(m => http_trait(m, "httpQuery"))
      .map(m => m.id.member.unwrap())
    for member_ in members {
      if http_string(member_, "httpPrefixHeaders") is Some(prefix) {
        let prefix = prefix.to_lower()
        for other in members {
          if http_string(other, "httpHeader") is Some(header) &&
            header.to_lower().has_prefix(prefix) {
            let detail = if prefix.is_empty() {
              "The service will not be able to disambiguate between header parameters intended for the `" +
              member_.id.to_string() +
              "` member and those explicitly bound to the `httpHeader` members."
            } else {
              "`httpHeader` bindings must not case-insensitively start with any `httpPrefixHeaders` bindings."
            }
            events.push(
              validation_event(
                "HttpPrefixHeadersTrait",
                if prefix.is_empty() {
                  "NOTE"
                } else {
                  "ERROR"
                },
                Some(other),
                "`httpHeader` binding of `" +
                header.to_lower() +
                "` conflicts with the `httpPrefixHeaders` binding of `" +
                member_.id.to_string() +
                "` to `" +
                prefix +
                "`. " +
                detail,
              ),
            )
          }
        }
      }
      if http_trait(member_, "httpQueryParams") && !queries.is_empty() {
        let name = member_.id.member.unwrap()
        events.push(
          validation_event(
            "HttpQueryParamsTrait",
            "NOTE",
            Some(shape),
            "Structure member `" +
            name +
            "` is marked with the `httpQueryParams` trait, and `httpQuery` traits are applied to the following members: " +
            http_ticked(queries) +
            ". The service will not be able to disambiguate between query string parameters intended for the `" +
            name +
            "` member and those explicitly bound to the `httpQuery` members.",
          ),
        )
      }
    }
  }
  events
}

///|
fn Model::http_payload_events(
  self : Model,
  structure : ShapeId,
  request : Bool,
) -> Array[ValidationEvent] {
  let members = self.http_members(structure)
  if !members.iter().any(m => http_binding(m, request) == "httpPayload") {
    return []
  }
  let unbound = members
    .filter(m => http_binding(m, request) == "document")
    .map(m => m.id.member.unwrap())
  if unbound.is_empty() {
    return []
  }
  [
    validation_event(
      "HttpPayload",
      "ERROR",
      self.shapes.get(structure),
      "A member of this structure is marked with the `httpPayload` trait, but the following structure members are not explicitly bound to the HTTP message: " +
      http_ticked(unbound),
    ),
  ]
}

///|
fn Model::http_operation_events(
  self : Model,
  operation : Shape,
  config : NodeValue,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  guard operation.body is Operation(input~, output~, ..) else { return events }
  let uri = validation_string(config, "uri").unwrap_or("/")
  let path = uri.split("?").to_array()[0].to_owned()
  let members = self.http_members(input)
  let labels = http_labels(path)
  let missing = labels
    .filter(p => {
      !members
      .iter()
      .any(m => m.id.member == Some(p.0) && http_trait(m, "httpLabel"))
    })
    .map(p => p.0)
  if !missing.is_empty() {
    events.push(
      validation_event(
        "HttpLabelTrait",
        "ERROR",
        Some(operation),
        "This operation uses `" +
        input.to_string() +
        "` as input, but the following URI labels found in the operation's `http` trait do not have a corresponding member marked with the `httpLabel` trait: " +
        http_ticked(missing),
      ),
    )
  }
  for member_ in members {
    let name = member_.id.member.unwrap()
    if http_trait(member_, "httpLabel") {
      if !labels.iter().any(p => p.0 == name) {
        events.push(
          validation_event(
            "HttpLabelTrait",
            "ERROR",
            Some(member_),
            "This `" +
            name +
            "` structure member is marked with the `httpLabel` trait, but no corresponding `http` URI label could be found when used as the input of the `" +
            operation.id.to_string() +
            "` operation.",
          ),
        )
      } else if labels.iter().any(p => p == (name, true)) &&
        member_.body is Member(target~) &&
        self.shapes.get(target) is Some(target_shape) &&
        target_shape.body.keyword() != "string" &&
        target_shape.body.keyword() != "enum" {
        events.push(
          validation_event(
            "HttpLabelTrait",
            "ERROR",
            Some(member_),
            "The `" +
            name +
            "` structure member corresponds to a greedy label when used as the input of the `" +
            operation.id.to_string() +
            "` operation. This member targets (" +
            target_shape.body.keyword() +
            ": `" +
            target.to_string() +
            "`), but greedy labels must target string shapes.",
          ),
        )
      }
    }
  }
  if uri.find("?") is Some(at) {
    let keys : Set[String] = Set([])
    for pair in uri[at + 1:].split("&") {
      keys.add(pair.split("=").to_array()[0].to_owned())
    }
    let bound : Set[String] = Set([])
    for member_ in members {
      if http_string(member_, "httpQuery") is Some(name) && keys.contains(name) {
        bound.add(name)
      }
    }
    for name in bound {
      events.push(
        validation_event(
          "HttpQueryTrait",
          "ERROR",
          self.shapes.get(input),
          "`httpQuery` name `" +
          name +
          "` conflicts with the `http` trait of the `" +
          operation.id.to_string() +
          "` operation: `" +
          uri +
          "`",
        ),
      )
    }
  }
  if uri.iter().any(c => c.to_int() > 127) {
    events.push(
      validation_event(
        "HttpUriFormat",
        "ERROR",
        Some(operation),
        "@http trait `uri` is invalid: " + uri,
      ),
    )
  }
  for i, label in labels {
    if !label.1 {
      continue
    }
    for j = i + 1; j < labels.length(); j = j + 1 {
      if labels[j].1 {
        events.push(
          validation_event(
            "HttpUriGreedyLabel.MultipleGreedyLabels",
            "DANGER",
            Some(operation),
            "At most one greedy label segment may exist in a pattern: " + uri,
          ),
        )
      }
      events.push(
        validation_event(
          "HttpUriGreedyLabel.GreedyLabelIsNotLastLabel",
          "DANGER",
          Some(operation),
          "A greedy label must be the last label in its pattern: " + uri,
        ),
      )
    }
  }
  events.append(self.http_payload_events(input, true))
  events.append(self.http_payload_events(output, false))
  let code = match validation_field(config, "code") {
    Some(Number(n)) => @json.to_json(n).stringify()
    _ => "200"
  }
  if !code.has_prefix("2") || code.length() != 3 {
    events.push(
      validation_event(
        "HttpResponseCodeSemantics",
        "DANGER",
        Some(operation),
        "Expected an `http` code in the 2xx range, but found " + code,
      ),
    )
  } else if ["204", "205"].contains(code) &&
    self
    .http_members(output)
    .iter()
    .any(m => ["document", "httpPayload"].contains(http_binding(m, false))) {
    events.push(
      validation_event(
        "HttpResponseCodeSemantics",
        "WARNING",
        Some(operation),
        "The HTTP " +
        code +
        " status code does not allow a response body. To use this status code, all output members need to be bound to @httpHeader, @httpPrefixHeaders, @httpResponseCode, etc.",
      ),
    )
  }
  events.append(self.http_method_events(operation, config, members))
  events
}

///|
fn Model::http_method_events(
  _self : Model,
  operation : Shape,
  config : NodeValue,
  members : Array[Shape],
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let raw = validation_string(config, "method").unwrap_or("")
  let method = raw.to_upper()
  if !["GET", "HEAD", "OPTIONS", "TRACE", "POST", "DELETE", "PUT", "PATCH"].contains(
      method,
    ) {
    return events
  }
  if raw != method {
    events.push(
      validation_event(
        "HttpMethodSemantics",
        "WARNING",
        Some(operation),
        "This operation uses the `" +
        raw +
        "` method in the `http` trait, but expected `" +
        method +
        "`.",
      ),
    )
  }
  if method == "OPTIONS" {
    events.push(
      validation_event(
        "HttpMethodSemantics.OPTIONS",
        "WARNING",
        Some(operation),
        "OPTIONS requests are typically used as part of CORS and should not be modeled explicitly. They are an implementation detail that should not appear in generated client or server code. Instead, tooling should use the `cors` trait on a service to automatically configure CORS on clients and servers. It is the responsibility of service frameworks and API gateways to automatically manage OPTIONS requests. For example, OPTIONS requests are automatically created when using Smithy models with Amazon API Gateway.",
      ),
    )
  }
  let is_readonly = ["GET", "HEAD", "OPTIONS", "TRACE"].contains(method)
  for
    (trait_name, expected, suffix) in [
      ("readonly", Some(is_readonly), "ReadonlyTrait"),
      (
        "idempotent",
        if ["POST", "PATCH"].contains(method) {
          None
        } else {
          Some(["DELETE", "PUT"].contains(method))
        },
        "IdempotentTrait",
      ),
    ] {
    if expected is Some(wanted) && http_trait(operation, trait_name) != wanted {
      let present = http_trait(operation, trait_name)
      events.push(
        validation_event(
          "HttpMethodSemantics." +
          (if present { "Unnecessary" } else { "Missing" }) +
          suffix,
          "WARNING",
          Some(operation),
          "This operation uses the `" +
          method +
          "` method in the `http` trait, but " +
          (if present { "is" } else { "is not" }) +
          " marked with the " +
          trait_name +
          " trait",
        ),
      )
    }
  }
  if ["GET", "HEAD", "TRACE", "DELETE"].contains(method) {
    let payload = members
      .iter()
      .find_first(m => http_binding(m, true) == "httpPayload")
    let document = members
      .filter(m => http_binding(m, true) == "document")
      .map(m => m.id.member.unwrap())
    let detail = if payload is Some(member_) {
      Some(
        "the `" +
        member_.id.member.unwrap() +
        "` member is sent as the payload of the request because it is marked with the `httpPayload` trait. Many HTTP clients do not support payloads with " +
        method +
        " requests. Consider binding this member to other parts of the HTTP request such as a query string parameter using the `httpQuery` trait, a header using the `httpHeader` trait, or a path segment using the `httpLabel` trait.",
      )
    } else if !document.is_empty() {
      Some(
        "the following members are sent as part of the payload of the request: " +
        http_ticked(document) +
        ". These members are sent as part of the payload because they are not explicitly configured to be sent in headers, in the query string, or in a URI segment. Many HTTP clients do not support payloads with " +
        method +
        " requests. Consider binding these members to other parts of the HTTP request such as query string parameters using the `httpQuery` trait, headers using the `httpHeader` trait, or URI segments using the `httpLabel` trait.",
      )
    } else {
      None
    }
    if detail is Some(detail) {
      events.push(
        validation_event(
          "HttpMethodSemantics.UnexpectedPayload",
          "DANGER",
          Some(operation),
          "This operation uses the `" +
          method +
          "` method in the `http` trait, but " +
          detail,
        ),
      )
    }
  }
  events
}

///|
fn Model::http_events(self : Model) -> Array[ValidationEvent] {
  let events = self.http_structure_events()
  events.append(self.http_ignored_events())
  events.append(self.http_service_events())
  for _, shape in self.shapes {
    if shape.body is Service(..) &&
      shape.trait_value("smithy.api#httpApiKeyAuth") is Some(config) &&
      validation_string(config, "scheme") is Some(_) &&
      validation_string(config, "in") is Some(location) &&
      location != "header" {
      events.push(
        validation_event(
          "HttpApiKeyAuthTrait",
          "ERROR",
          Some(shape),
          "The httpApiKeyAuth trait must have an `in` value of `header` when a `scheme` is provided, found: " +
          location,
        ),
      )
    }
    if shape.trait_value("smithy.api#endpoint") is Some(config) {
      events.append(self.http_host_events(shape, config))
    }
    if shape.trait_value("smithy.api#http") is Some(config) {
      events.append(self.http_operation_events(shape, config))
    }
    if shape.body is Structure(_) && http_string(shape, "error") is Some(error) {
      events.append(self.http_payload_events(shape.id, false))
      if shape.trait_value("smithy.api#httpError") is Some(Number(code)) {
        let code = @json.to_json(code).stringify()
        let range = if error == "client" { "4" } else { "5" }
        if code.length() != 3 || !code.has_prefix(range) {
          events.push(
            validation_event(
              "HttpResponseCodeSemantics",
              "DANGER",
              Some(shape),
              "Expected an `httpError` code in the " +
              range +
              "xx range for a `" +
              error +
              "` error, but found " +
              code,
            ),
          )
        }
      }
    }
  }
  events
}

///|
fn Model::http_ignored_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let graph = SelectorGraph::new(self)
  for _, container in self.shapes {
    guard container.body is Structure(_) && !http_trait(container, "mixin") else {
      continue
    }
    let relationships = graph
      .incoming(container.id)
      .filter(e => e.label != "trait")
    for member_ in self.http_members(container.id) {
      let bindings = [
        "httpHeader", "httpLabel", "httpPayload", "httpPrefixHeaders", "httpQueryParams",
        "httpQuery", "httpResponseCode",
      ].filter(t => http_trait(member_, t))
      if bindings.is_empty() {
        continue
      }
      let input = bindings
        .iter()
        .any(t => ["httpLabel", "httpQueryParams", "httpQuery"].contains(t))
      let output = bindings.contains("httpResponseCode")
      let ignored = relationships.filter(e => {
        if input {
          e.label != "input"
        } else if output {
          e.label != "output"
        } else {
          !["input", "output", "error"].contains(e.label)
        }
      })
      if ignored.is_empty() {
        continue
      }
      let trait_name = if input {
        bindings.filter(t => {
          ["httpLabel", "httpQueryParams", "httpQuery"].contains(t)
        })[0]
      } else if output {
        "httpResponseCode"
      } else {
        bindings[0]
      }
      let groups : Map[String, Array[String]] = Map([])
      for edge in ignored {
        let relationship = if edge.label == "" {
          "member target"
        } else {
          edge.label
        }
        let ids = groups.get(relationship).unwrap_or([])
        ids.push(edge.from.to_string())
        groups[relationship] = ids
      }
      let contexts : Array[String] = []
      for name, ids in groups {
        ids.sort()
        contexts.push(name + ": [" + ids.join(", ") + "]")
      }
      contexts.sort()
      let detail = if relationships.length() == groups.length() {
        "ignored in all contexts."
      } else {
        "ignored in some contexts: {" + contexts.join(", ") + "}"
      }
      events.push(
        validation_event(
          "HttpBindingTraitIgnored." +
          (if input { "Input" } else if output { "Output" } else { "TopLevel" }),
          "WARNING",
          Some(member_),
          "The `" +
          trait_name +
          "` trait applied to this" +
          (if member_.mixins.is_empty() { "" } else { " mixed in" }) +
          " member is " +
          detail,
        ),
      )
    }
  }
  events
}

///|
fn SelectorGraph::http_contained_operations(
  self : SelectorGraph,
  service : Shape,
) -> Array[Shape] {
  let result : Array[Shape] = []
  let pending = [service.id]
  let seen : Set[ShapeId] = Set([])
  while pending.pop() is Some(id) {
    if seen.contains(id) {
      continue
    }
    seen.add(id)
    guard self.model.shapes.get(id) is Some(shape) else { continue }
    if shape.body is Operation(..) {
      result.push(shape)
      continue
    }
    for edge in self.outgoing(id) {
      if edge.label != "trait" &&
        self.model.shapes.get(edge.to) is Some(target) &&
        target.body is (Operation(..) | Resource(..)) {
        pending.push(edge.to)
      }
    }
  }
  result
}

///|
fn http_uri_key(uri : String) -> (Array[String], Map[String, String]) {
  let portions = uri.split("?").to_array()
  let segments = portions[0]
    .split("/")
    .map(segment => {
      let segment = segment.to_owned()
      if segment.has_prefix("{") && segment.has_suffix("+}") {
        "{+}"
      } else if segment.has_prefix("{") && segment.has_suffix("}") {
        "{}"
      } else {
        segment
      }
    })
    .to_array()
  let query : Map[String, String] = Map([])
  if portions.length() > 1 {
    for pair in portions[1].split("&") {
      let pieces = pair.split("=").to_array()
      query[pieces[0].to_owned()] = if pieces.length() > 1 {
        pieces[1].to_owned()
      } else {
        ""
      }
    }
  }
  (segments, query)
}

///|
/// The method and the `http_uri_key` of an `http` trait value, as one key:
/// two operations can conflict only when their keys are equal.
fn http_endpoint_group(config : NodeValue) -> String {
  let method = match validation_string(config, "method") {
    Some(method) => "=" + method
    None => "-"
  }
  let (segments, query) = http_uri_key(
    validation_string(config, "uri").unwrap_or("/"),
  )
  let pairs = query.iter().map(pair => pair.0 + "=" + pair.1).to_array()
  pairs.sort()
  method + "\u{0}" + segments.join("/") + "\u{0}" + pairs.join("&")
}

///|
fn Model::http_service_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let any_http = self.shapes.iter().any(p => http_trait(p.1, "http"))
  if !any_http {
    return events
  }
  let graph = SelectorGraph::new(self)
  for _, service in self.shapes {
    guard service.body is Service(..) else { continue }
    let operations = graph.http_contained_operations(service)
    let mut protocol : ShapeId? = None
    for trait_id, _ in service.traits {
      if self.shapes.get(trait_id) is Some(definition) &&
        definition.trait_value("smithy.api#protocolDefinition") is Some(config) &&
        validation_array(validation_field(config, "traits")).contains(
          String("smithy.api#http"),
        ) {
        protocol = Some(trait_id)
        break
      }
    }
    if protocol is Some(_) ||
      operations.iter().any(op => http_trait(op, "http")) {
      for operation in operations {
        if !http_trait(operation, "http") {
          let reason = match protocol {
            Some(id) => "The `" + id.to_string() + "` protocol requires all"
            None => "One or more"
          }
          events.push(
            validation_event(
              "HttpBindingsMissing",
              if protocol is Some(_) {
                "ERROR"
              } else {
                "WARNING"
              },
              Some(operation),
              reason +
              " operations in the `" +
              service.id.to_string() +
              "` service define the `http` trait, but this operation is missing the `http` trait.",
            ),
          )
        }
      }
    }
    // Only operations with the same method and URI key can conflict, so
    // compare each operation with its own group and not with all others.
    let groups : Map[String, Array[Shape]] = Map([])
    for operation in operations {
      guard operation.trait_value("smithy.api#http") is Some(config) else {
        continue
      }
      let key = http_endpoint_group(config)
      match groups.get(key) {
        Some(group) => group.push(operation)
        None => groups[key] = [operation]
      }
    }
    for operation in operations {
      guard operation.trait_value("smithy.api#http") is Some(config) else {
        continue
      }
      let uri = validation_string(config, "uri").unwrap_or("/")
      let conflicts : Array[String] = []
      for other in groups.get(http_endpoint_group(config)).unwrap_or([]) {
        guard other.id != operation.id &&
          other.trait_value("smithy.api#http") is Some(other_config) else {
          continue
        }
        let other_uri = validation_string(other_config, "uri").unwrap_or("/")
        if !self.http_endpoints_conflict(operation, other) {
          continue
        }
        conflicts.push("`" + other.id.to_string() + "` (" + other_uri + ")")
      }
      if !conflicts.is_empty() {
        conflicts.sort()
        events.push(
          validation_event(
            "HttpUriConflict",
            "ERROR",
            Some(operation),
            "Operation URI, `" +
            uri +
            "`, conflicts with other operation URIs in the same service: [" +
            conflicts.join(", ") +
            "]",
          ),
        )
      }
    }
  }
  events
}

///|
fn Model::http_host_events(
  self : Model,
  operation : Shape,
  config : NodeValue,
) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  guard operation.body is Operation(input~, ..) &&
    validation_string(config, "hostPrefix") is Some(prefix) else {
    return events
  }
  let labels = http_labels(prefix)
  let mut expanded = prefix
  for (name, _) in labels {
    expanded = expanded.replace(old="{" + name + "}", new="foo")
  }
  let host = if expanded.has_suffix(".") {
    expanded[:expanded.length() - 1].to_owned()
  } else {
    expanded
  }
  let parts = host.split(".").to_array()
  let alpha_numeric = fn(c : Char) {
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  }
  let valid = !host.is_empty() &&
    alpha_numeric(host.iter().next().unwrap()) &&
    parts
    .iter()
    .all(p => {
      p.length() >= 1 &&
      p.length() <= 63 &&
      p.iter().all(c => alpha_numeric(c) || c == '-')
    })
  if !valid {
    events.push(
      validation_event(
        "HostLabelTrait",
        "ERROR",
        Some(operation),
        "The `endpoint` trait hostPrefix, " +
        prefix +
        ", could not expand in to a valid RFC 3986 host: " +
        expanded,
      ),
    )
  }
  if !labels.is_empty() && !prefix.has_suffix(".") {
    events.push(
      validation_event(
        "HostLabelTrait",
        "DANGER",
        Some(operation),
        "`endpoint` trait hostPrefix contains host labels and does not end in a period (`.`). This can result in clients inadvertently sending data to domains you do not control.",
      ),
    )
  }
  let members = self.http_members(input)
  let missing = labels
    .filter(p => {
      !members
      .iter()
      .any(m => m.id.member == Some(p.0) && http_trait(m, "hostLabel"))
    })
    .map(p => p.0)
  if !missing.is_empty() {
    events.push(
      validation_event(
        "HostLabelTrait",
        "ERROR",
        Some(operation),
        "This operation uses " +
        input.to_string() +
        " as input, but the following host labels found in the operation's `endpoint` trait do not have a corresponding member marked with the `hostLabel` trait: " +
        http_ticked(missing),
      ),
    )
  }
  for member_ in members {
    let name = member_.id.member.unwrap()
    if http_trait(member_, "hostLabel") && !labels.iter().any(p => p.0 == name) {
      events.push(
        validation_event(
          "HostLabelTrait",
          "ERROR",
          Some(member_),
          "This `" +
          name +
          "` structure member is marked with the `hostLabel` trait, but no corresponding `endpoint` label could be found when used as the input of the `" +
          operation.id.to_string() +
          "` operation.",
        ),
      )
    }
  }
  events
}

///|
fn http_host_segments(prefix : String) -> Array[(String, Bool)] {
  let result : Array[(String, Bool)] = []
  let mut offset = 0
  while offset < prefix.length() {
    match prefix[offset:].find("{") {
      None => {
        result.push((prefix[offset:].to_owned(), false))
        break
      }
      Some(start) => {
        let start = offset + start
        if start > offset {
          result.push((prefix[offset:start].to_owned(), false))
        }
        guard prefix[start + 1:].find("}") is Some(end) else { break }
        result.push((prefix[start + 1:start + 1 + end].to_owned(), true))
        offset = start + end + 2
      }
    }
  }
  result
}

///|
fn Model::http_host_pattern(
  self : Model,
  operation : Shape,
  name : String,
) -> String? {
  guard operation.body is Operation(input~, ..) else { return None }
  for member_ in self.http_members(input) {
    if member_.id.member == Some(name) && http_trait(member_, "hostLabel") {
      return http_string(member_, "pattern")
    }
  }
  None
}

///|
fn Model::http_endpoints_conflict(
  self : Model,
  operation : Shape,
  other : Shape,
) -> Bool {
  let endpoint = operation.trait_value("smithy.api#endpoint")
  let other_endpoint = other.trait_value("smithy.api#endpoint")
  match (endpoint, other_endpoint) {
    (None, None) => return true
    (Some(_), None) | (None, Some(_)) => return false
    _ => ()
  }
  let left = http_host_segments(
    validation_string(endpoint.unwrap(), "hostPrefix").unwrap_or(""),
  )
  let right = http_host_segments(
    validation_string(other_endpoint.unwrap(), "hostPrefix").unwrap_or(""),
  )
  let mut conflicts = false
  let mut allowable = true
  for i = 0; i < left.length() && i < right.length(); i = i + 1 {
    let a = left[i]
    let b = right[i]
    if a.1 != b.1 {
      conflicts = true
      let (pattern, literal) = if a.1 {
        (self.http_host_pattern(operation, a.0), b.0)
      } else {
        (self.http_host_pattern(other, b.0), a.0)
      }
      let excludes = match pattern {
        Some(pattern) =>
          try {
            let regex = @string.Regex::Regex(pattern)
            regex.execute(literal) is None
          } catch {
            _ => false
          }
        None => false
      }
      if !excludes {
        allowable = false
      }
    } else if !a.1 && a.0 != b.0 {
      break
    }
  }
  !(conflicts && allowable)
}
