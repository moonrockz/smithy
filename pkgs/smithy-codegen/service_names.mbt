///|
/// The contextual names of shapes in one or more services. A service `rename`
/// map gives a shape another name in the context of that service. A generator
/// applies its own case rules to the result.
pub struct ServiceNames {
  priv renames : Map[@smithy.ShapeId, String]
}

///|
/// The names in the context of one service. It raises `MissingService` or
/// `NotAService` for a bad service ID.
pub fn ServiceNames::new(
  model : @smithy.Model,
  service : @smithy.ShapeId,
) -> ServiceNames raise CodegenError {
  ServiceNames::for_services(model, [service])
}

///|
/// The names in the context of several services, such as the two services of a
/// protocol that one generated package holds. I merge the rename maps. I raise
/// `InvalidSettings` when the services give one shape two names, or when two
/// shapes outside the prelude get the same name without regard to case.
pub fn ServiceNames::for_services(
  model : @smithy.Model,
  services : Array[@smithy.ShapeId],
) -> ServiceNames raise CodegenError {
  let renames : Map[@smithy.ShapeId, String] = Map([])
  let shapes : Map[@smithy.ShapeId, Unit] = Map([])
  for service in services {
    guard model.shapes.get(service) is Some(shape) else {
      raise MissingService(service)
    }
    guard shape.body is Service(rename~, ..) else { raise NotAService(service) }
    let ids = rename.keys().collect()
    ids.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
    for id in ids {
      let name = rename[id]
      match renames.get(id) {
        Some(old) if old != name => {
          let (first, second) = if old.lexical_compare(name) <= 0 {
            (old, name)
          } else {
            (name, old)
          }
          raise InvalidSettings(
            "I found two names for shape `\{id}` in the services: `\{first}` and `\{second}`.",
          )
        }
        _ => renames[id] = name
      }
    }
    for id in service_closure(model, service) {
      shapes[id] = ()
    }
  }
  let names = { renames, }
  let ids = shapes.keys().collect()
  ids.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
  let seen : Map[String, @smithy.ShapeId] = Map([])
  for id in ids {
    if id.member_name() is Some(_) || id.namespace() == "smithy.api" {
      continue
    }
    let key = names.shape_name(id).to_lower()
    match seen.get(key) {
      Some(first) =>
        raise InvalidSettings(
          "I found shapes `\{first}` and `\{id}` with the same name in the services. Add a rename to a service.",
        )
      None => seen[key] = id
    }
  }
  names
}

///|
/// The name of a shape in the context of the services: the rename, else the
/// name of the shape ID. A member keeps its member name.
pub fn ServiceNames::shape_name(
  self : ServiceNames,
  id : @smithy.ShapeId,
) -> String {
  match id.member_name() {
    Some(name) => name
    None =>
      match self.renames.get(id) {
        Some(name) => name
        None => id.name()
      }
  }
}
