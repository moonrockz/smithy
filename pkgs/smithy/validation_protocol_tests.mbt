///|
/// Protocol test parameters are native Smithy values, not wire JSON values:
/// timestamps use epoch seconds, blobs are plain text, and optional nulls are allowed.
fn Model::protocol_test_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let id_refs = IdRefSelections::new(self)
  for trait_name in ["httpRequestTests", "httpResponseTests"] {
    let trait_id = "smithy.test#" + trait_name
    let ids : Map[String, Array[Shape]] = Map([])
    for _, owner in self.shapes {
      let event_id = if trait_name == "httpRequestTests" {
        "HttpRequestTestsInput"
      } else if owner.body is Structure(_) {
        "HttpResponseTestsError"
      } else {
        "HttpResponseTestsOutput"
      }
      let target = match (trait_name, owner.body) {
        ("httpRequestTests", Operation(input~, ..)) => Some(input)
        ("httpResponseTests", Operation(output~, ..)) => Some(output)
        ("httpResponseTests", Structure(_)) if owner.trait_value(
            "smithy.api#error",
          )
          is Some(_) => Some(owner.id)
        _ => None
      }
      for i, case_ in validation_array(owner.trait_value(trait_id)) {
        if validation_string(case_, "id") is Some(id) {
          let owners = ids.get(id).unwrap_or([])
          owners.push(owner)
          ids[id] = owners
        }
        guard target is Some(target) else { continue }
        let params = validation_field(case_, "params").unwrap_or(
          Object(Map([])),
        )
        let checks = [(target, params, "params")]
        if validation_string(case_, "vendorParamsShape").bind(ShapeId::parse)
          is Some(vendor_shape) {
          let vendor = validation_field(case_, "vendorParams").unwrap_or(
            Object(Map([])),
          )
          if vendor == Object(Map([])) {
            events.push(
              validation_event(
                event_id,
                "WARNING",
                Some(owner),
                "Protocol test case defined a `vendorParamsShape` but no `vendorParams`",
              ),
            )
          } else {
            checks.push((vendor_shape, vendor, "vendorParams"))
          }
        }
        for (target, value, field) in checks {
          if !(value is Object(_)) {
            events.push(
              validation_event(
                event_id,
                "ERROR",
                Some(owner),
                "I expected an object for " +
                trait_id +
                "." +
                i.to_string() +
                "." +
                field +
                ".",
              ),
            )
            continue
          }
          for
            event in self.node_validation_events(
              value,
              target,
              Some(owner),
              event_id,
              "ERROR",
              id_refs~,
              protocol_params=true,
            ) {
            let id = if event.id.has_prefix(event_id + ".UnknownMember.") {
              event_id + ".UnknownMember"
            } else {
              event.id
            }
            events.push({
              ..event,
              id,
              message: trait_id +
              "." +
              i.to_string() +
              "." +
              field +
              ": " +
              event.message,
            })
          }
        }
        let media = validation_string(case_, "bodyMediaType")
          .unwrap_or("")
          .split(";")
          .to_array()[0]
          .trim()
          .to_owned()
          .to_lower()
        if validation_string(case_, "body") is Some(body) &&
          body != "" &&
          (media.has_suffix("/json") || media.has_suffix("+json")) {
          let valid = try {
            ignore(@json.parse(body))
            true
          } catch {
            _ => false
          }
          if !valid {
            events.push(
              validation_event(
                event_id,
                "DANGER",
                Some(owner),
                "I found invalid JSON body content in protocol test `" +
                validation_string(case_, "id").unwrap_or("") +
                "`.",
              ),
            )
          }
        }
      }
    }
    for id, owners in ids {
      if owners.length() > 1 {
        let names = owners.map(s => "`" + s.id.to_string() + "`")
        names.sort()
        for owner in owners {
          events.push(
            validation_event(
              "UniqueProtocolTestCaseId",
              "ERROR",
              Some(owner),
              "Conflicting `" +
              trait_id +
              "` test case IDs found for ID `" +
              id +
              "`: " +
              names.join(", "),
            ),
          )
        }
      }
    }
  }
  events
}
