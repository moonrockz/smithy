///|
fn Model::service_conflict_severity(
  self : Model,
  left : Shape,
  right : Shape,
) -> String {
  let pending = [(left, right)]
  let seen : Set[String] = Set([])
  let mut severity = "NOTE"
  while pending.pop() is Some((a, b)) {
    let key = a.id.to_string() + ":" + b.id.to_string()
    if seen.contains(key) {
      continue
    }
    seen.add(key)
    if a.body.keyword() != b.body.keyword() || a.traits != b.traits {
      return "ERROR"
    }
    match (a.body, b.body) {
      (Simple(_), Simple(_)) => ()
      (List(a_member), List(b_member)) => {
        severity = "WARNING"
        if self.shapes.get(a_member) is Some(a) &&
          self.shapes.get(b_member) is Some(b) {
          pending.push((a, b))
        }
      }
      (Member(target=a_target), Member(target=b_target)) =>
        if self.shapes.get(a_target) is Some(a) &&
          self.shapes.get(b_target) is Some(b) {
          pending.push((a, b))
        }
      _ => return "ERROR"
    }
  }
  severity
}

///|
fn Model::service_events(self : Model) -> Array[ValidationEvent] {
  let events : Array[ValidationEvent] = []
  let edges = selector_edges(self)
  for _, service in self.shapes {
    guard service.body is Service(rename~, ..) else { continue }
    let closure : Map[ShapeId, Shape] = Map([])
    let pending = [service.id]
    while pending.pop() is Some(id) {
      if closure.contains(id) {
        continue
      }
      guard self.shapes.get(id) is Some(shape) else { continue }
      closure[id] = shape
      for edge in edges {
        if edge.from == id && edge.label != "trait" {
          pending.push(edge.to)
        }
      }
    }
    let names : Map[String, Array[Shape]] = Map([])
    for id, shape in closure {
      if id.member is Some(_) {
        continue
      }
      let name = rename.get(id).unwrap_or(id.name).to_lower()
      let group = names.get(name).unwrap_or([])
      group.push(shape)
      names[name] = group
    }
    for _, group in names {
      if group.length() < 2 {
        continue
      }
      for subject in group {
        for other in group {
          if subject.id == other.id {
            continue
          }
          let severity = self.service_conflict_severity(subject, other)
          let subject_name = match rename.get(subject.id) {
            Some(name) => "Renamed shape name \"" + name + "\""
            None => "Shape name `" + subject.id.to_string() + "`"
          }
          let other_name = match rename.get(other.id) {
            Some(name) => " (renamed to \"" + name + "\")"
            None => ""
          }
          let obligation = if severity == "ERROR" { "must" } else { "should" }
          events.push(
            validation_event(
              "Service",
              severity,
              Some(subject),
              subject_name +
              " conflicts with `" +
              other.id.to_string() +
              "`" +
              other_name +
              " in the `" +
              service.id.to_string() +
              "` service closure. Shapes in the closure of a service " +
              obligation +
              " have case-insensitively unique names regardless of their namespaces. " +
              "Use the `rename` property of the service to disambiguate shape names.",
            ),
          )
        }
      }
    }
    for from, to in rename {
      if !identifier(to) {
        events.push(
          validation_event(
            "Service",
            "ERROR",
            Some(service),
            "Service attempts to rename `" +
            from.to_string() +
            "` to an invalid identifier, \"" +
            to +
            "\"",
          ),
        )
      } else if from.name == to {
        events.push(
          validation_event(
            "Service",
            "ERROR",
            Some(service),
            "Service rename for `" +
            from.to_string() +
            "` does not actually change the name from `" +
            to +
            "`",
          ),
        )
      }
      if closure.get(from) is Some(shape) {
        if shape.body is (Member(..) | Resource(..) | Operation(..)) {
          let kind = shape.body.keyword()
          events.push(
            validation_event(
              "Service",
              "ERROR",
              Some(service),
              "Service attempts to rename a " +
              kind +
              " shape from `" +
              from.to_string() +
              "` to \"" +
              to +
              "\"; " +
              kind +
              "s cannot be renamed",
            ),
          )
        }
      } else {
        events.push(
          validation_event(
            "Service",
            "ERROR",
            Some(service),
            "Service attempts to rename a shape not in the service: " +
            from.to_string(),
          ),
        )
      }
    }
  }
  events
}
