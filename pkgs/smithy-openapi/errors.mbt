///|
/// Mirror the reference model transform before preparing the shared schema
/// index. Hoisted headers become optional strings and leave the original error
/// documents; the original caller's graph is never mutated.
fn deconflict_errors(
  model : @smithy.Model,
  service : @smithy.Shape,
) -> (@smithy.Model, Map[@smithy.ShapeId, Array[@smithy.ShapeId]]) raise OpenApiError {
  let shapes : Map[@smithy.ShapeId, @smithy.Shape] = Map([])
  for id, shape in model.shapes {
    shapes[id] = shape
  }
  let groups : Map[@smithy.ShapeId, Array[@smithy.ShapeId]] = Map([])
  let service_errors = match service.body {
    @smithy.Service(errors~, ..) => errors
    _ => []
  }
  for operation in service_operations(model, service) {
    guard operation.body is @smithy.Operation(input~, output~, errors~) else {
      continue
    }
    let by_status : Map[Int32, Array[@smithy.ShapeId]] = Map([])
    let seen : Set[@smithy.ShapeId] = Set([])
    for id in errors + service_errors {
      if seen.contains(id) {
        continue
      }
      seen.add(id)
      if model.shapes.get(id) is Some(error) {
        let code = error_code(error)
        let entries = by_status.get_or_init(code, () => [])
        entries.push(id)
      }
    }
    let replacement : Array[@smithy.ShapeId] = []
    for code, ids in by_status {
      if ids.length() == 1 {
        replacement.push(ids[0])
        continue
      }
      let synthetic = @smithy.ShapeId::parse(
        service.id.namespace() +
        "#" +
        operation.id.name() +
        code.to_string() +
        "Error",
      ).unwrap()
      let union_id = @smithy.ShapeId::parse(
        service.id.namespace() + "#" + synthetic.name() + "Content",
      ).unwrap()
      let headers : Map[String, @smithy.NodeValue] = Map([])
      let union_members : Array[@smithy.ShapeId] = []
      for id in ids {
        guard model.shapes.get(id) is Some(error) &&
          error.body is @smithy.Structure(members) else {
          continue
        }
        let retained : Array[@smithy.ShapeId] = []
        for field_id in members {
          guard model.shapes.get(field_id) is Some(field) else { continue }
          if field.trait_value("smithy.api#httpHeader") is Some(header) {
            let name = field_id.member_name().unwrap()
            if headers.get(name) is Some(previous) && previous != header {
              raise InvalidConfiguration(
                "Conflicting header when de-conflicting errors",
              )
            }
            headers[name] = header
          } else {
            retained.push(field_id)
          }
        }
        shapes[id] = { ..error, body: @smithy.Structure(retained), }
        let member_id = union_id.with_member(id.name()).unwrap()
        union_members.push(member_id)
        shapes[member_id] = {
          ..error,
          id: member_id,
          body: @smithy.Member(target=id),
          traits: Map([]),
          mixins: [],
          provenance: None,
        }
      }
      shapes[union_id] = {
        ..operation,
        id: union_id,
        body: @smithy.Union(union_members),
        traits: Map([]),
        mixins: [],
        provenance: None,
      }
      let payload = synthetic.with_member("errorUnion").unwrap()
      let synthetic_members = [payload]
      shapes[payload] = {
        ..operation,
        id: payload,
        body: @smithy.Member(target=union_id),
        traits: Map([]),
        mixins: [],
        provenance: None,
      }
      for name, header in headers {
        let id = synthetic.with_member(name).unwrap()
        synthetic_members.push(id)
        let traits : Map[@smithy.ShapeId, @smithy.NodeValue] = Map([])
        traits[@smithy.ShapeId::parse("smithy.api#httpHeader").unwrap()] = header
        shapes[id] = {
          ..operation,
          id,
          body: @smithy.Member(
            target=@smithy.ShapeId::parse("smithy.api#String").unwrap(),
          ),
          traits,
          mixins: [],
          provenance: None,
        }
      }
      let traits : Map[@smithy.ShapeId, @smithy.NodeValue] = Map([])
      traits[@smithy.ShapeId::parse("smithy.api#error").unwrap()] = @smithy.String(
        if code >= 400 && code < 500 {
          "client"
        } else {
          "server"
        },
      )
      traits[@smithy.ShapeId::parse("smithy.api#httpError").unwrap()] = @smithy.Number(
        @smithy.NodeNumber::parse(code.to_string()).unwrap(),
      )
      shapes[synthetic] = {
        ..operation,
        id: synthetic,
        body: @smithy.Structure(synthetic_members),
        traits,
        mixins: [],
        provenance: None,
      }
      groups[synthetic] = ids
      replacement.push(synthetic)
    }
    shapes[operation.id] = {
      ..operation,
      body: @smithy.Operation(input~, output~, errors=replacement),
    }
  }
  ({ ..model, shapes, }, groups)
}

///|
fn Context::response_phase(
  self : Context,
  subject : @smithy.Shape,
) -> ExamplePhase {
  if subject.trait_value("smithy.api#error") is Some(_) {
    FailedExample(self.error_groups.get(subject.id).unwrap_or([subject.id]))
  } else {
    ResponseExample
  }
}
