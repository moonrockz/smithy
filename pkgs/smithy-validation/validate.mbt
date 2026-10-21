///|
priv enum ValueSource[V] {
  Original(V)
  KeyText(String)
}

///|
priv struct Frame[V] {
  source : ValueSource[V]
  expected : @smithy.ShapeId?
  owner : @smithy.ShapeId
  path : InstancePath
  depth : Int32
  nullable : Bool
}

///|
fn[V] value_kind(node : ValueNode[V]) -> String {
  match node {
    Null => "null"
    Boolean(_) => "boolean"
    Number(_) | InvalidNumber => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) | LocatedObject(_) => "object"
    Native(_) => "native scalar"
    Sexp(_) => "sexp"
    Annotated(_, _) => "annotated value"
  }
}

///|
fn[V] check_kind(
  shape : PreparedShape,
  node : ValueNode[V],
  config : Config,
  budget : Budget,
  path : InstancePath,
) -> Bool {
  let emit = fn(code, message) { budget.emit(code, path, shape.id, message) }
  match (shape.body, node) {
    (Simple(Document), _) => true
    (Simple(Boolean), Boolean(_)) => true
    (Simple(String), String(_)) => true
    (Simple(Blob), String(text)) => {
      if strict_blob_length(text) is None {
        emit(
          InvalidEncoding,
          "I expected a canonical padded base64 blob, but found an invalid encoding.",
        )
      }
      true
    }
    (Simple(Timestamp), Number(_)) if shape.constraints.timestamp ==
      EpochSeconds => true
    (Simple(Timestamp), String(text)) if shape.constraints.timestamp == DateTime => {
      if !date_time(text) {
        emit(
          InvalidTimestamp,
          "I expected a calendar-valid date-time timestamp with an offset.",
        )
      }
      true
    }
    (
      Simple(
        Byte
        | Short
        | Integer
        | Long
        | BigInteger
        | BigDecimal
        | Float
        | Double as kind
      ),
      Number(n),
    ) => {
      if !numeric_bounds(kind, n) {
        emit(
          NumericBounds,
          "I expected a number within the target's numeric bounds and integer requirements.",
        )
      }
      true
    }
    (Simple(Float | Double), String("NaN" | "Infinity" | "-Infinity" as text)) if config.nonnumeric_floats => {
      if (
          text == "NaN" &&
          (shape.constraints.min is Some(_) || shape.constraints.max is Some(_))
        ) ||
        (text == "Infinity" && shape.constraints.max is Some(_)) ||
        (text == "-Infinity" && shape.constraints.min is Some(_)) {
        emit(
          Range,
          "I expected a numeric value satisfying the modeled range, but found a nonnumeric float.",
        )
      }
      true
    }
    (List(_), Array(_)) => true
    (Structure(_) | Union(_) | Map(..), Object(_) | LocatedObject(_)) => true
    (Enum(_), String(_)) | (IntEnum(_), Number(_)) => true
    _ => false
  }
}

///|
fn[V : ValueView] check_constraints(
  shape : PreparedShape,
  node : ValueNode[V],
  budget : Budget,
  path : InstancePath,
) -> Unit {
  let c = shape.constraints
  let emit = fn(code, message) { budget.emit(code, path, shape.id, message) }
  if node is Number(n) {
    if !budget.charge(path, shape.id) {
      return
    }
    if (c.min is Some(min) && n.numeric_compare(min) < 0) ||
      (c.max is Some(max) && n.numeric_compare(max) > 0) {
      emit(Range, "I expected the number to satisfy the modeled range.")
    }
  }
  let count = match node {
    String(text) =>
      if shape.body is Simple(Blob) {
        strict_blob_length(text)
      } else {
        Some(text.iter().count())
      }
    Array(values) => Some(values.length())
    Object(fields) => Some(fields.length())
    LocatedObject(fields) => Some(fields.length())
    _ => None
  }
  if count is Some(count) &&
    (c.min_length is Some(_) || c.max_length is Some(_)) {
    if !budget.charge(path, shape.id) {
      return
    }
    let n = number(count.to_string())
    if (c.min_length is Some(min) && n.numeric_compare(min) < 0) ||
      (c.max_length is Some(max) && n.numeric_compare(max) > 0) {
      emit(
        Length,
        "I expected the value's length to satisfy the modeled bounds.",
      )
    }
  }
  if c.pattern is Some(pattern) && node is String(text) {
    let units = if text.length() >= budget.limits.work / pattern.weight {
      budget.limits.work + 1
    } else {
      (text.length() + 1) * pattern.weight
    }
    if !budget.charge(path, shape.id, units~) {
      return
    }
    if !pattern.execute(text) {
      emit(Pattern, "I expected the string to match the modeled pattern.")
    }
  }
  if !shape.enum_values.is_empty() {
    let mut found = false
    for candidate in shape.enum_values {
      if !budget.charge(path, shape.id) {
        return
      }
      match (node, candidate) {
        (String(a), String(b)) if a == b => found = true
        (Number(a), Number(b)) if a == b => found = true
        _ => ()
      }
      if found {
        break
      }
    }
    if !found {
      emit(EnumValue, "I expected a declared enum value.")
    }
  }
  if c.unique && node is Array(values) {
    for i in 0..<values.length() {
      for j in 0..<i {
        if !budget.complete {
          return
        }
        if equivalent(values[i], values[j], budget, path, shape.id) {
          budget.emit(
            UniqueItems,
            path.child(Index(i)),
            shape.id,
            "I expected a unique item, but found a duplicate value.",
          )
          break
        }
      }
    }
  }
}

///|
/// Validate a value using a read-only adapter. No input or prepared state is mutated.
pub fn[V : ValueView] PreparedValidator::validate(
  self : PreparedValidator,
  value : V,
  base_path~ : InstancePath = InstancePath::root(),
) -> ValidationResult {
  let budget = Budget::new(self.config.limits)
  let stack : Array[Frame[V]] = [
    {
      source: Original(value),
      expected: Some(self.target),
      owner: self.target,
      path: base_path,
      depth: 0,
      nullable: false,
    },
  ]
  while stack.pop() is Some(frame) {
    if !budget.charge(frame.path, frame.owner) {
      break
    }
    if frame.depth > budget.limits.depth {
      budget.stop(frame.path, frame.owner, "depth")
      break
    }
    let node = match frame.source {
      Original(value) => value.inspect()
      KeyText(text) => String(text)
    }
    let shape = frame.expected.bind(id => self.shapes.get(id))
    match node {
      InvalidNumber => {
        budget.emit(
          InvalidNumber,
          frame.path,
          frame.owner,
          "I expected an exact finite JSON numeric token, but found an invalid host number.",
        )
        continue
      }
      Native(_) | Sexp(_) | Annotated(_, _) => {
        budget.emit(
          UnsupportedValue,
          frame.path,
          frame.owner,
          "I cannot validate this native value kind in the JSON value profile.",
        )
        continue
      }
      _ => ()
    }
    if node is Null && frame.nullable {
      continue
    }
    if shape is Some(shape) {
      if check_kind(shape, node, self.config, budget, frame.path) {
        check_constraints(shape, node, budget, frame.path)
      } else {
        budget.emit(
          TypeMismatch,
          frame.path,
          shape.id,
          "I expected a " +
          shape.body.keyword() +
          " value, but found " +
          value_kind(node) +
          ".",
        )
      }
    }
    if !budget.complete {
      break
    }
    match node {
      Array(values) => {
        if !budget.room(
            frame.path,
            frame.owner,
            values.length(),
            pending=stack.length(),
          ) {
          break
        }
        let child = shape.bind(s => {
          match s.body {
            List(id) => Some(id)
            _ => None
          }
        })
        let nullable = shape.map(s => s.sparse).unwrap_or(false)
        for i = values.length() - 1; i >= 0; i = i - 1 {
          stack.push({
            source: Original(values[i]),
            expected: child,
            owner: child.unwrap_or(frame.owner),
            path: frame.path.child(Index(i)),
            depth: frame.depth + 1,
            nullable,
          })
        }
      }
      Object(_) | LocatedObject(_) => {
        let count = match node {
          Object(fields) => fields.length()
          LocatedObject(fields) => fields.length()
          _ => 0
        }
        if !budget.room(frame.path, frame.owner, count, pending=stack.length()) {
          break
        }
        if shape.map(s => s.body is Map(..)).unwrap_or(false) &&
          !budget.room(
            frame.path,
            frame.owner,
            count * 2,
            pending=stack.length(),
          ) {
          break
        }
        let fields = match node {
          Object(fields) =>
            fields.map(entry => {
              LocatedField::new(
                entry.0,
                entry.1,
                InstancePath::root().child(Field(entry.0, 0)),
              )
            })
          LocatedObject(fields) => fields
          _ => []
        }
        let occurrences : Map[String, Int32] = Map([])
        let present : Set[String] = Set([])
        let located : Array[(LocatedField[V], InstancePath, Int32)] = []
        for field in fields {
          let occurrence = occurrences.get(field.name).unwrap_or(0)
          occurrences[field.name] = occurrence + 1
          present.add(field.name)
          let path = if node is Object(_) {
            frame.path.child(Field(field.name, occurrence))
          } else {
            frame.path.append(field.source)
          }
          if occurrence > 0 {
            budget.emit(
              DuplicateMember,
              path,
              frame.owner,
              "I expected unique object member names, but found a duplicate member.",
            )
          }
          located.push((field, path, occurrence))
        }
        if shape is Some(shape) {
          if shape.body is Union(_) && fields.length() != 1 {
            budget.emit(
              UnionMember,
              frame.path,
              shape.id,
              "I expected exactly one union member.",
            )
          }
          for member_ in shape.members {
            if !budget.charge(frame.path, shape.id) {
              break
            }
            if member_.required && !present.contains(member_.name) {
              budget.emit(
                RequiredMember,
                frame.path.child(Field(member_.name, 0)),
                member_.id,
                "I expected the required structure member, but found it absent.",
              )
            }
          }
        }
        for i = located.length() - 1; i >= 0; i = i - 1 {
          let (field, path, occurrence) = located[i]
          let mut expected = None
          let mut nullable = false
          if shape is Some(shape) {
            match shape.body {
              Structure(_) | Union(_) =>
                match shape.by_name.get(field.name) {
                  Some(member_) => expected = Some(member_.id)
                  None =>
                    if self.config.unknown_members == Reject ||
                      shape.body is Union(_) {
                      budget.emit(
                        UnknownMember,
                        path,
                        shape.id,
                        "I expected a declared member, but found an unknown member.",
                      )
                    }
                }
              Map(key~, value~) => {
                expected = Some(value)
                nullable = shape.sparse
                stack.push({
                  source: KeyText(field.name),
                  expected: Some(key),
                  owner: key,
                  path: frame.path.child(MapKey(field.name, occurrence)),
                  depth: frame.depth + 1,
                  nullable: false,
                })
              }
              _ => ()
            }
          }
          stack.push({
            source: Original(field.value),
            expected,
            owner: expected.unwrap_or(frame.owner),
            path,
            depth: frame.depth + 1,
            nullable,
          })
        }
      }
      _ => ()
    }
  }
  { findings: budget.findings, complete: budget.complete, }
}

///|
pub fn PreparedValidator::validate_json(
  self : PreparedValidator,
  value : Json,
  base_path~ : InstancePath = InstancePath::root(),
) -> ValidationResult {
  self.validate(value, base_path~)
}
