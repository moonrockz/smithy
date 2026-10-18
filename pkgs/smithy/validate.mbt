///|
fn is_mixin(shape : Shape) -> Bool {
  shape.trait_value("smithy.api#mixin") is Some(_)
}

///|
fn Assembly::target(
  self : Assembly,
  model : Model,
  owner : Shape,
  id : ShapeId,
  expected : String,
) -> Unit {
  guard model.shapes.get(id) is Some(target) else {
    self.problem(
      "SM-MODEL-004",
      "I could not resolve shape \{id}, referenced by \{owner.id}.",
      owner.source,
      shape=owner.id.to_string(),
    )
    return
  }
  let kind = target.body.keyword()
  if owner.id.namespace != id.namespace &&
    target.trait_value("smithy.api#private") is Some(_) {
    self.problem(
      "SM-MODEL-005",
      "I cannot reference private shape \{id} from namespace \{owner.id.namespace}.",
      owner.source,
      shape=owner.id.to_string(),
    )
  }
  let valid = match expected {
    "data" => !["member", "operation", "service", "resource"].contains(kind)
    "string" => kind == "string" || kind == "enum"
    "error" =>
      kind == "structure" && target.trait_value("smithy.api#error") is Some(_)
    _ => kind == expected
  }
  if !valid || is_mixin(target) {
    self.problem(
      "SM-MODEL-005",
      "I expected a \{expected} target from \{owner.id}, but found \{kind} \{id}.",
      owner.source,
      shape=owner.id.to_string(),
    )
  }
}

///|
fn NodeNumber::is_integer(self : NodeNumber) -> Bool {
  self.coefficient == BigInt::from_int(0) ||
  self.exponent >= BigInt::from_int(0)
}

///|
fn NodeNumber::in_range(self : NodeNumber, min : String, max : String) -> Bool {
  if !self.is_integer() {
    return false
  }
  if self.coefficient == BigInt::from_int(0) {
    return true
  }
  if self.exponent > BigInt::from_int(20) {
    return false
  }
  let value = self.coefficient *
    BigInt::from_string("1" + "0".repeat(self.exponent.to_int()))
  value >= BigInt::from_string(min) && value <= BigInt::from_string(max)
}

///|
fn Assembly::validate_value(
  self : Assembly,
  model : Model,
  target : ShapeId,
  value : NodeValue,
  owner : Shape,
  trait_ : String,
) -> Unit {
  let stack = [(target, value, "")]
  while stack.pop() is Some((target, value, path)) {
    guard model.shapes.get(target) is Some(shape) else { continue }
    let valid = match (shape.body, value) {
      (Member(target~), value) => {
        stack.push((target, value, path))
        true
      }
      (Simple(Document), _) => true
      (Simple(Boolean), Boolean(_)) => true
      (Simple(String | Blob), String(_)) => true
      (Simple(Timestamp), String(_) | Number(_)) => true
      (Simple(Float | Double), Number(_)) => true
      (Simple(Float | Double), String("NaN" | "Infinity" | "-Infinity")) => true
      (Simple(BigDecimal), Number(_)) => true
      (Simple(BigDecimal), String(s)) => NodeNumber::parse(s) is Some(_)
      (Simple(BigInteger), Number(n)) => n.is_integer()
      (Simple(BigInteger), String(s)) =>
        NodeNumber::parse(s).map(n => n.is_integer()).unwrap_or(false)
      (Simple(Byte), Number(n)) => n.in_range("-128", "127")
      (Simple(Short), Number(n)) => n.in_range("-32768", "32767")
      (Simple(Integer), Number(n)) => n.in_range("-2147483648", "2147483647")
      (Simple(Long), Number(n)) =>
        n.in_range("-9223372036854775808", "9223372036854775807")
      (List(member_), Array(values)) => {
        for i, value in values {
          stack.push((member_, value, path + "/" + i.to_string()))
        }
        true
      }
      (Map(key~, value=target), Object(values)) => {
        for name, value in values {
          stack.push((key, String(name), path + "/" + pointer(name)))
          stack.push((target, value, path + "/" + pointer(name)))
        }
        true
      }
      (Structure(members) | Union(members), Object(values)) => {
        let declared : Set[String] = Set([])
        for member_ in members {
          guard model.shapes.get(member_) is Some(member_shape) &&
            member_.member is Some(name) else {
            continue
          }
          declared.add(name)
          match values.get(name) {
            Some(value) =>
              stack.push((member_, value, path + "/" + pointer(name)))
            None =>
              if member_shape.trait_value("smithy.api#required") is Some(_) &&
                member_shape.trait_value("smithy.api#default") is None {
                self.problem(
                  "SM-MODEL-011",
                  "I expected required property \{name} in trait \{trait_}\{path} on \{owner.id}.",
                  owner.source,
                  shape=owner.id.to_string(),
                )
              }
          }
        }
        for key, _ in values {
          if !declared.contains(key) {
            self.problem(
              "SM-MODEL-011",
              "I found unknown property \{key} in trait \{trait_}\{path} on \{owner.id}.",
              owner.source,
              shape=owner.id.to_string(),
            )
          }
        }
        if shape.body is Union(_) {
          values.length() == 1
        } else {
          true
        }
      }
      (Enum(members), String(value)) =>
        members
        .iter()
        .any(id => {
          model.shapes.get(id).bind(s => s.trait_value("smithy.api#enumValue")) ==
          Some(String(value))
        })
      (IntEnum(members), Number(value)) =>
        members
        .iter()
        .any(id => {
          model.shapes.get(id).bind(s => s.trait_value("smithy.api#enumValue")) ==
          Some(Number(value))
        })
      _ => false
    }
    if !valid {
      self.problem(
        "SM-MODEL-011",
        "I expected a \{shape.body.keyword()} value in trait \{trait_}\{path} on \{owner.id}.",
        owner.source,
        shape=owner.id.to_string(),
      )
    }
  }
}

///|
fn Assembly::validate(self : Assembly, model : Model) -> Unit {
  for (target, source) in self.syntactic {
    if model.get(target) is None {
      self.problem(
        "SM-MODEL-004",
        "I could not resolve the syntactic shape ID \{target}.",
        source,
        shape=target,
      )
    }
  }
  let names : Map[String, ShapeId] = Map([])
  for id, shape in model.shapes {
    let folded = id.to_string().to_lower()
    if names.get(folded) is Some(other) && other != id {
      self.problem(
        "SM-MODEL-010",
        "I found case-insensitively conflicting shape IDs \{other} and \{id}.",
        shape.source,
        shape=id.to_string(),
      )
    }
    names[folded] = id
    for trait_id, value in shape.traits {
      guard model.shapes.get(trait_id) is Some(definition) else {
        self.problem(
          "SM-MODEL-004",
          "I could not resolve trait \{trait_id} on \{id}.",
          shape.source,
          shape=id.to_string(),
        )
        continue
      }
      if definition.id.namespace != id.namespace &&
        definition.trait_value("smithy.api#private") is Some(_) {
        self.problem(
          "SM-MODEL-011",
          "I cannot apply private trait \{trait_id} outside its namespace.",
          shape.source,
          shape=id.to_string(),
        )
      }
      if definition.trait_value("smithy.api#trait") is None {
        self.problem(
          "SM-MODEL-011",
          "I expected a trait definition for \{trait_id}, applied to \{id}.",
          shape.source,
          shape=id.to_string(),
        )
      } else {
        self.validate_value(model, trait_id, value, shape, trait_id.to_string())
        if trait_id.to_string() == "smithy.contracts#conditions" {
          self.validate_conditions(model, shape, value)
        }
      }
    }
    match shape.body {
      Member(target~) => {
        let parent = model.shapes.get(id.root())
        let enum_member = parent
          .map(p => p.body is Enum(_) || p.body is IntEnum(_))
          .unwrap_or(false)
        self.target(
          model,
          shape,
          target,
          if enum_member {
            "structure"
          } else {
            "data"
          },
        )
        if enum_member && target.to_string() != "smithy.api#Unit" {
          self.problem(
            "SM-MODEL-005",
            "I expected enum member \{id} to target smithy.api#Unit, but found \{target}.",
            shape.source,
            shape=id.to_string(),
          )
        }
      }
      Map(key~, ..) =>
        if model.shapes.get(key) is Some({ body: Member(target~), .. }) {
          self.target(model, shape, target, "string")
        }
      Union(members) | Enum(members) | IntEnum(members) => {
        if members.is_empty() && !is_mixin(shape) {
          self.problem(
            "SM-MODEL-010",
            "I expected at least one member in \{shape.body.keyword()} \{id}.",
            shape.source,
            shape=id.to_string(),
          )
        }
        if shape.body is Enum(_) || shape.body is IntEnum(_) {
          let values : Array[NodeValue] = []
          for member_ in members {
            guard model.shapes.get(member_) is Some(member_shape) else {
              continue
            }
            let value = member_shape.trait_value("smithy.api#enumValue")
            let valid = match (shape.body, value) {
              (Enum(_), Some(String(_))) => true
              (IntEnum(_), Some(Number(n))) =>
                n.in_range("-2147483648", "2147483647")
              _ => false
            }
            if !valid {
              self.problem(
                "SM-MODEL-010",
                "I expected an enumValue of the correct type for \{member_}.",
                member_shape.source,
                shape=member_.to_string(),
              )
            }
            if value is Some(value) {
              if values.contains(value) {
                self.problem(
                  "SM-MODEL-010",
                  "I found a duplicate enumValue in \{id}.",
                  member_shape.source,
                  shape=id.to_string(),
                )
              }
              values.push(value)
            }
          }
        }
      }
      Operation(input~, output~, errors~) => {
        self.target(model, shape, input, "structure")
        self.target(model, shape, output, "structure")
        for error in errors {
          self.target(model, shape, error, "error")
        }
        if is_mixin(shape) &&
          (
            input.to_string() != "smithy.api#Unit" ||
            output.to_string() != "smithy.api#Unit"
          ) {
          self.problem(
            "SM-MODEL-008",
            "I expected Unit input and output on operation mixin \{id}.",
            shape.source,
            shape=id.to_string(),
          )
        }
      }
      Service(operations~, resources~, errors~, rename~, ..) => {
        for operation in operations {
          self.target(model, shape, operation, "operation")
        }
        for resource in resources {
          self.target(model, shape, resource, "resource")
        }
        for error in errors {
          self.target(model, shape, error, "error")
        }
        for target, _ in rename {
          if !model.shapes.contains(target) {
            self.problem(
              "SM-MODEL-004",
              "I could not resolve renamed shape \{target} in \{id}.",
              shape.source,
              shape=id.to_string(),
            )
          }
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
        operations~,
        collectionOperations~,
        resources~
      ) => {
        for name, target in identifiers {
          self.target(model, shape, target, "string")
          if properties.contains(name) {
            self.problem(
              "SM-MODEL-010",
              "I found resource identifier and property named \{name} on \{id}.",
              shape.source,
              shape=id.to_string(),
            )
          }
        }
        for _, target in properties {
          self.target(model, shape, target, "data")
        }
        for operation in [create, put, read, update, delete, list] {
          if operation is Some(operation) {
            self.target(model, shape, operation, "operation")
          }
        }
        for operation in operations + collectionOperations {
          self.target(model, shape, operation, "operation")
        }
        for resource in resources {
          self.target(model, shape, resource, "resource")
        }
        if is_mixin(shape) &&
          (
            !identifiers.is_empty() ||
            !properties.is_empty() ||
            [create, put, read, update, delete, list]
            .iter()
            .any(v => v is Some(_)) ||
            !(operations + collectionOperations + resources).is_empty()
          ) {
          self.problem(
            "SM-MODEL-008",
            "I found properties on resource mixin \{id}.",
            shape.source,
            shape=id.to_string(),
          )
        }
      }
      _ => ()
    }
  }
  self.resource_cycles(model)
}

///|
fn Assembly::resource_cycles(self : Assembly, model : Model) -> Unit {
  let done : Set[ShapeId] = Set([])
  let active : Set[ShapeId] = Set([])
  for id, shape in model.shapes {
    guard shape.body is Resource(..) else { continue }
    let stack = [(id, false)]
    while stack.pop() is Some((id, leaving)) {
      if done.contains(id) {
        continue
      }
      if leaving {
        active.remove(id)
        done.add(id)
        continue
      }
      guard model.shapes.get(id) is Some(shape) &&
        shape.body is Resource(resources~, ..) else {
        continue
      }
      if active.contains(id) {
        self.problem(
          "SM-MODEL-009",
          "I found a resource containment cycle at \{id}.",
          shape.source,
          shape=id.to_string(),
        )
        continue
      }
      active.add(id)
      stack.push((id, true))
      for child in resources.rev() {
        stack.push((child, false))
      }
    }
  }
}
