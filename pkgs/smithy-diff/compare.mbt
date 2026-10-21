///|
priv struct PreviewIndex {
  owners : Map[@smithy.ShapeId, Array[@smithy.ShapeId]]
  features : Map[@smithy.ShapeId, @smithy.NodeValue]
  feature_ids : Map[@smithy.ShapeId, String]
}

///|
priv struct ComparisonContext {
  old_index : PreviewIndex
  new_index : PreviewIndex
}

///|
fn preview_index(model : @smithy.Model) -> PreviewIndex {
  let feature_ids : Map[@smithy.ShapeId, String] = Map([])
  let services = []
  for id, shape in model.shapes {
    if string(field(shape.trait_value("smithy.api#unstable"), "featureId"))
      is Some(feature) {
      feature_ids[id] = feature
    }
    if shape.body is Service(..) {
      services.push(shape)
    }
  }
  let owners : Map[@smithy.ShapeId, Array[@smithy.ShapeId]] = Map([])
  let features : Map[@smithy.ShapeId, @smithy.NodeValue] = Map([])
  if feature_ids.is_empty() {
    return { owners, features, feature_ids, }
  }
  let stable : Set[@smithy.ShapeId] = Set([])
  let service_closures = services.map(service => {
    (service, closure(model, service.id))
  })
  for service in services {
    if feature_ids.contains(service.id) {
      continue
    }
    let stack = [service.id]
    while stack.pop() is Some(id) {
      if stable.contains(id) {
        continue
      }
      stable.add(id)
      if model.shapes.get(id) is Some(shape) {
        for next in neighbors(shape) {
          if next.namespace() != "smithy.api" && !feature_ids.contains(next) {
            stack.push(next)
          }
        }
      }
    }
  }
  for owner, feature_id in feature_ids {
    let candidates = []
    for (service, closure) in service_closures {
      if closure.contains(owner) &&
        field(service.trait_value("smithy.api#unstableFeatures"), feature_id)
        is Some(info) &&
        !candidates.contains(info) {
        candidates.push(info)
      }
    }
    if candidates.length() == 1 {
      features[owner] = candidates[0]
    }
    let seen : Set[@smithy.ShapeId] = Set([])
    let stack = [owner]
    while stack.pop() is Some(id) {
      if seen.contains(id) {
        continue
      }
      seen.add(id)
      let enclosing = owners.get_or_init(id, () => [])
      if !enclosing.contains(owner) {
        enclosing.push(owner)
      }
      if id != owner && feature_ids.contains(id) {
        continue
      }
      if model.shapes.get(id) is Some(shape) {
        for next in neighbors(shape) {
          if next.namespace() != "smithy.api" && !stable.contains(next) {
            stack.push(next)
          }
        }
      }
    }
  }
  { owners, features, feature_ids, }
}

///|
fn PreviewIndex::is_preview(self : PreviewIndex, id : @smithy.ShapeId) -> Bool {
  self.owners
  .get(id)
  .map(owners => {
    !owners.is_empty() &&
    owners
    .iter()
    .all(owner => {
      string(field(self.features.get(owner), "reason")) == Some("PREVIEW")
    })
  })
  .unwrap_or(false)
}

///|
fn decorate(
  d : Differences,
  events : Array[ValidationEvent],
  context : ComparisonContext,
) -> Array[ValidationEvent] {
  let old_index = context.old_index
  let new_index = context.new_index
  let decorated = events.map(event => {
    let event = d.new_model.decorate_validation_event(event)
    if (event.severity != "ERROR" && event.severity != "DANGER") ||
      event.id.has_suffix(".smithy.api#unstable") ||
      event.id.has_suffix(".smithy.api#unstableFeatures") {
      return event
    }
    guard event.shape is Some(id) else { return event }
    let in_old = d.old_model.shapes.contains(id)
    let in_new = d.new_model.shapes.contains(id)
    if (!in_old && !in_new) ||
      (in_old && !old_index.is_preview(id)) ||
      (in_new && !new_index.is_preview(id)) {
      return event
    }
    let index = if in_new { new_index } else { old_index }
    let owners = index.owners.get(id).unwrap_or([])
    if (
        event.id.has_prefix("ChangedNullability") ||
        event.id.has_prefix("AddedRequiredMember")
      ) &&
      owners.iter().any(owner => owner.member_name() != None) {
      return event
    }
    let features = owners
      .iter()
      .filter_map(id => index.feature_ids.get(id))
      .collect()
    features.sort_by((a, b) => a.lexical_compare(b))
    let unique : Array[String] = []
    for feature in features {
      if !unique.contains(feature) {
        unique.push(feature)
      }
    }
    {
      ..event,
      severity: "WARNING",
      message: event.message +
      " This event is downgraded to WARNING because this shape is part of preview feature " +
      unique.map(tick).join(", ") +
      ".",
    }
  })
  decorated.sort_by((a, b) => {
    let a_key = a.id +
      "|" +
      a.shape.map(id => id.to_string()).unwrap_or("") +
      "|" +
      a.severity +
      "|" +
      a.message
    let b_key = b.id +
      "|" +
      b.shape.map(id => id.to_string()).unwrap_or("") +
      "|" +
      b.severity +
      "|" +
      b.message
    a_key.lexical_compare(b_key)
  })
  decorated
}

///|
/// Compare two assembled models using the built-in Smithy compatibility rules.
/// Events retain suppressions and are sorted by ID, shape, severity and message.
pub fn compare(old_model : @smithy.Model, new_model : @smithy.Model) -> Result {
  let differences = Differences::detect(old_model, new_model)
  let context = {
    old_index: preview_index(old_model),
    new_index: preview_index(new_model),
  }
  {
    differences,
    events: decorate(differences, evaluate(differences, context), context),
  }
}
