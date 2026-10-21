///|
pub using @smithy {type ValidationEvent}

///|
/// A changed applied trait, including additions and removals.
pub struct TraitChange {
  id : @smithy.ShapeId
  old_value : @smithy.NodeValue?
  new_value : @smithy.NodeValue?
} derive(Eq, Debug)

///|
pub struct ShapeChange {
  old_shape : @smithy.Shape
  new_shape : @smithy.Shape
  traits : Array[TraitChange]
} derive(Eq, Debug)

///|
pub struct MetadataChange {
  key : String
  old_value : @smithy.NodeValue?
  new_value : @smithy.NodeValue?
} derive(Eq, Debug)

///|
/// Semantic changes ignore source locations and assembly provenance. Container
/// changes include changes to their first-class members.
pub struct Differences {
  old_model : @smithy.Model
  new_model : @smithy.Model
  added : Array[@smithy.Shape]
  removed : Array[@smithy.Shape]
  changed : Array[ShapeChange]
  metadata : Array[MetadataChange]
} derive(Debug)

///|
fn members(shape : @smithy.Shape) -> Array[@smithy.ShapeId] {
  match shape.body {
    Structure(ids) | Union(ids) | Enum(ids) | IntEnum(ids) => ids
    List(id) => [id]
    Map(key~, value~) => [key, value]
    _ => []
  }
}

///|
fn sorted_ids(ids : Array[@smithy.ShapeId]) -> Array[@smithy.ShapeId] {
  let sorted = ids.copy()
  sorted.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
  let unique = []
  for id in sorted {
    if unique.last() != Some(id) {
      unique.push(id)
    }
  }
  unique
}

///|
fn semantic_body(body : @smithy.ShapeBody) -> @smithy.ShapeBody {
  match body {
    Operation(input~, output~, errors~) =>
      Operation(input~, output~, errors=sorted_ids(errors))
    Service(version~, operations~, resources~, errors~, rename~) =>
      Service(
        version~,
        operations=sorted_ids(operations),
        resources=sorted_ids(resources),
        errors=sorted_ids(errors),
        rename~,
      )
    Resource(
      identifiers~,
      properties~,
      create~,
      put~,
      read~,
      update~,
      delete~,
      list~,
      operations~,
      collectionOperations~,
      resources~
    ) => {
      let all_operations = operations + collectionOperations
      for id in [create, put, read, update, delete, list] {
        if id is Some(id) {
          all_operations.push(id)
        }
      }
      Resource(
        identifiers~,
        properties~,
        create~,
        put~,
        read~,
        update~,
        delete~,
        list~,
        operations=sorted_ids(all_operations),
        collectionOperations=[],
        resources=sorted_ids(resources),
      )
    }
    _ => body
  }
}

///|
fn semantic_equal(a : @smithy.Shape, b : @smithy.Shape) -> Bool {
  semantic_body(a.body) == semantic_body(b.body) &&
  a.traits == b.traits &&
  sorted_ids(a.mixins) == sorted_ids(b.mixins) &&
  a.is_legacy_set() == b.is_legacy_set()
}

///|
fn shape_change(a : @smithy.Shape, b : @smithy.Shape) -> ShapeChange {
  let traits : Array[TraitChange] = []
  for id, old_value in a.traits {
    let new_value = b.traits.get(id)
    if new_value != Some(old_value) {
      traits.push({ id, old_value: Some(old_value), new_value, })
    }
  }
  for id, value in b.traits {
    if !a.traits.contains(id) {
      traits.push({ id, old_value: None, new_value: Some(value), })
    }
  }
  traits.sort_by((a, b) => a.id.to_string().lexical_compare(b.id.to_string()))
  { old_shape: a, new_shape: b, traits, }
}

///|
pub fn Differences::detect(
  old_model : @smithy.Model,
  new_model : @smithy.Model,
) -> Differences {
  let added = []
  let removed = []
  let changed = []
  for id, old_shape in old_model.shapes {
    match new_model.shapes.get(id) {
      None => removed.push(old_shape)
      Some(new_shape) => {
        let member_changed = members(old_shape)
          .iter()
          .any(id => {
            match (old_model.shapes.get(id), new_model.shapes.get(id)) {
              (Some(a), Some(b)) => !semantic_equal(a, b)
              (None, None) => false
              _ => true
            }
          })
        if !semantic_equal(old_shape, new_shape) || member_changed {
          changed.push(shape_change(old_shape, new_shape))
        }
      }
    }
  }
  for id, shape in new_model.shapes {
    if !old_model.shapes.contains(id) {
      added.push(shape)
    }
  }
  added.sort_by((a, b) => a.id.to_string().lexical_compare(b.id.to_string()))
  removed.sort_by((a, b) => a.id.to_string().lexical_compare(b.id.to_string()))
  changed.sort_by((a, b) => {
    a.new_shape.id.to_string().lexical_compare(b.new_shape.id.to_string())
  })
  let metadata = []
  for key, value in old_model.metadata {
    let new_value = new_model.metadata.get(key)
    if new_value != Some(value) {
      metadata.push({ key, old_value: Some(value), new_value, })
    }
  }
  for key, value in new_model.metadata {
    if !old_model.metadata.contains(key) {
      metadata.push({ key, old_value: None, new_value: Some(value), })
    }
  }
  metadata.sort_by((a, b) => a.key.lexical_compare(b.key))
  { old_model, new_model, added, removed, changed, metadata, }
}

///|
pub struct Result {
  differences : Differences
  events : Array[ValidationEvent]
} derive(Debug)

///|
pub fn Result::is_breaking(self : Result) -> Bool {
  self.events
  .iter()
  .any(event => event.severity == "ERROR" || event.severity == "DANGER")
}

///|
fn has(shape : @smithy.Shape, name : String) -> Bool {
  shape.trait_value("smithy.api#" + name) != None
}

///|
fn kind(shape : @smithy.Shape) -> String {
  if shape.is_legacy_set() {
    "set"
  } else {
    shape.body.keyword()
  }
}

///|
fn emit(
  events : Array[ValidationEvent],
  id : String,
  severity : String,
  shape : @smithy.Shape,
  message : String,
) -> Unit {
  events.push({
    id,
    severity,
    shape: Some(shape.id),
    message,
    source: Some(shape.source),
    suppression_reason: None,
  })
}

///|
fn json(value : @smithy.NodeValue) -> String {
  value.to_json().stringify()
}

///|
fn field(value : @smithy.NodeValue?, name : String) -> @smithy.NodeValue? {
  match value {
    Some(Object(values)) => values.get(name)
    _ => None
  }
}

///|
fn strings(value : @smithy.NodeValue?) -> Array[String] {
  match value {
    Some(Array(values)) =>
      values
      .iter()
      .filter_map(v => {
        match v {
          String(s) => Some(s)
          _ => None
        }
      })
      .collect()
    _ => []
  }
}

///|
fn string(value : @smithy.NodeValue?) -> String? {
  match value {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn tick(value : String) -> String {
  "`" + value + "`"
}
