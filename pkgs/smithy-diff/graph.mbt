///|
/// Directed model containment edges, without traits or member-to-container edges.
fn neighbors(shape : @smithy.Shape) -> Array[@smithy.ShapeId] {
  match shape.body {
    Member(target~) => [target]
    Operation(input~, output~, errors~) => [input, output] + errors
    Service(operations~, resources~, errors~, ..) =>
      operations + resources + errors
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
      let out = identifiers.values().to_array() +
        properties.values().to_array() +
        operations +
        collectionOperations +
        resources
      for id in [create, put, read, update, delete, list] {
        if id is Some(id) {
          out.push(id)
        }
      }
      out
    }
    _ => members(shape)
  }
}

///|
fn closure(
  model : @smithy.Model,
  start : @smithy.ShapeId,
) -> Set[@smithy.ShapeId] {
  let seen : Set[@smithy.ShapeId] = Set([])
  let stack = [start]
  while stack.pop() is Some(id) {
    if seen.contains(id) {
      continue
    }
    seen.add(id)
    if model.shapes.get(id) is Some(shape) {
      stack.append(neighbors(shape))
    }
  }
  seen
}

///|
/// EntityShape.getOperations contains explicitly bound operations; resource
/// lifecycle operations are separate relationships in the reference model.
fn entity_ids(
  shape : @smithy.Shape,
) -> (Array[@smithy.ShapeId], Array[@smithy.ShapeId])? {
  match shape.body {
    Service(operations~, resources~, ..)
    | Resource(operations~, resources~, ..) => Some((operations, resources))
    _ => None
  }
}

///|
fn contained_operations(
  model : @smithy.Model,
  start : @smithy.ShapeId,
) -> Set[@smithy.ShapeId] {
  let seen : Set[@smithy.ShapeId] = Set([])
  let operations : Set[@smithy.ShapeId] = Set([])
  let stack = [start]
  while stack.pop() is Some(id) {
    if seen.contains(id) {
      continue
    }
    seen.add(id)
    if model.shapes.get(id) is Some(shape) {
      match shape.body {
        Service(operations=ops, resources~, ..) => {
          for op in ops {
            operations.add(op)
          }
          stack.append(resources)
        }
        Resource(
          create~,
          put~,
          read~,
          update~,
          delete~,
          list~,
          operations=ops,
          collectionOperations~,
          resources~,
          ..
        ) => {
          for op in ops + collectionOperations {
            operations.add(op)
          }
          for op in [create, put, read, update, delete, list] {
            if op is Some(op) {
              operations.add(op)
            }
          }
          stack.append(resources)
        }
        _ => ()
      }
    }
  }
  operations
}

///|
fn entity_bindings(
  d : Differences,
  change : ShapeChange,
  events : Array[ValidationEvent],
) -> Unit {
  guard entity_ids(change.old_shape) is Some((old_ops, old_resources)) &&
    entity_ids(change.new_shape) is Some((new_ops, new_resources)) else {
    return
  }
  let shape = change.new_shape
  let service = shape.body is Service(..)
  let parent = if service { "Service" } else { "Resource" }
  for
    (noun, old_ids, new_ids) in [
      ("Operation", old_ops, new_ops),
      ("Resource", old_resources, new_resources),
    ] {
    for id in new_ids {
      if !old_ids.contains(id) {
        emit(
          events,
          "Added" + noun + "Binding.To" + parent + "." + id.name(),
          "NOTE",
          shape,
          noun +
          " binding of " +
          tick(id.to_string()) +
          " was added to the " +
          kind(shape) +
          " shape, " +
          tick(shape.id.to_string()),
        )
      }
    }
    for id in old_ids {
      if !new_ids.contains(id) {
        let moved = service &&
          noun == "Operation" &&
          contained_operations(d.new_model, shape.id).contains(id)
        emit(
          events,
          "Removed" + noun + "Binding.From" + parent + "." + id.name(),
          if moved {
            "NOTE"
          } else {
            "ERROR"
          },
          shape,
          noun +
          " binding of " +
          tick(id.to_string()) +
          " was removed from " +
          kind(shape) +
          " shape, " +
          tick(shape.id.to_string()) +
          (if moved {
            ", but the operation remains in the service closure through a resource"
          } else {
            ""
          }),
        )
      }
    }
  }
}
