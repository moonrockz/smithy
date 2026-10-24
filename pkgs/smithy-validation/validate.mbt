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
    Object(_) | LocatedObject(_) | NativeObject(_) => "object"
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
    (Simple(Blob), Native(Blob(_))) if config.profile == NativeProfile => true
    (Simple(Timestamp), Native(Timestamp(_))) if config.profile == NativeProfile =>
      true
    (Simple(BigDecimal | Float | Double as kind), Native(Decimal(n))) if config.profile ==
      NativeProfile => {
      if !numeric_bounds(kind, n) {
        emit(
          NumericBounds,
          "I expected a number within the target's numeric bounds.",
        )
      }
      true
    }
    (Simple(Float | Double as kind), Native(Float(n))) if config.profile ==
      NativeProfile => {
      match exact_float(n) {
        Some(value) =>
          if !numeric_bounds(kind, value) {
            emit(
              NumericBounds,
              "I expected a number within the target's numeric bounds.",
            )
          }
        None =>
          if (
              n != n &&
              (
                shape.constraints.min is Some(_) ||
                shape.constraints.max is Some(_)
              )
            ) ||
            (n > 0.0 && shape.constraints.max is Some(_)) ||
            (n < 0.0 && shape.constraints.min is Some(_)) {
            emit(
              Range,
              "I expected a numeric value satisfying the modeled range, but found a nonnumeric float.",
            )
          }
      }
      true
    }
    (Simple(Boolean), Boolean(_)) => true
    (Simple(String), String(_)) => true
    (Simple(Blob), String(text)) if config.profile == JsonProfile => {
      if strict_blob_length(text) is None {
        emit(
          InvalidEncoding,
          "I expected a canonical padded base64 blob, but found an invalid encoding.",
        )
      }
      true
    }
    (Simple(Timestamp), Number(_)) if config.profile == JsonProfile &&
      shape.constraints.timestamp == EpochSeconds => true
    (Simple(Timestamp), String(text)) if config.profile == JsonProfile &&
      shape.constraints.timestamp == DateTime => {
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
    (Simple(Float | Double), String("NaN" | "Infinity" | "-Infinity" as text)) if config.profile ==
      JsonProfile &&
      config.nonnumeric_floats => {
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
    (
      Structure(_)
      | Union(_)
      | Map(..),
      Object(_)
      | LocatedObject(_)
      | NativeObject(_),
    ) => true
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
  config : Config,
) -> Unit {
  let c = shape.constraints
  let emit = fn(code, message) { budget.emit(code, path, shape.id, message) }
  if exact_numeric(node) is Some(n) {
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
    NativeObject(fields) => Some(fields.length())
    Native(Blob(bytes)) => Some(bytes.length())
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
    if !budget.complete {
      return
    }
    // The matcher counts its own work and stops when it needs more than is left.
    let work = budget.limits.work - budget.used
    let (matched, units) = match pattern.matches(text, work~) {
      Some(result) => result
      None => (true, work + 1)
    }
    if !budget.charge(path, shape.id, units~) {
      return
    }
    if !matched {
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
        if equivalent(values[i], values[j], budget, path, shape.id, config) {
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
    let mut node = match frame.source {
      Original(value) => {
        if !budget.room(
            frame.path,
            frame.owner,
            value.expansion_size(),
            pending=stack.length(),
          ) {
          break
        }
        value.inspect()
      }
      KeyText(text) => String(text)
    }
    let shape = frame.expected.bind(id => self.shapes.get(id))
    let mut unsupported = false
    match node {
      InvalidNumber => {
        budget.emit(
          InvalidNumber,
          frame.path,
          frame.owner,
          "I expected an exact finite numeric token, but found an invalid host number.",
        )
        continue
      }
      Annotated(annotations, value) => {
        if !budget.charge(frame.path, frame.owner, units=annotations.length()) {
          break
        }
        budget.emit(
          UnsupportedValue,
          frame.path,
          frame.owner,
          "I cannot validate an annotated value.",
        )
        stack.push({ ..frame, source: Original(value), })
        continue
      }
      Sexp(values) => {
        budget.emit(
          UnsupportedValue,
          frame.path,
          frame.owner,
          "I cannot validate an s-expression value.",
        )
        node = Array(values)
        unsupported = true
      }
      Native(scalar) => {
        let invalid = if self.config.profile == JsonProfile {
          true
        } else {
          match scalar {
            Symbol(_) | Clob(_) | InvalidTimestamp => true
            Timestamp(t) =>
              !t.full() ||
              shape.map(s => s.body is Simple(Document)).unwrap_or(true)
            Blob(_) =>
              shape.map(s => s.body is Simple(Document)).unwrap_or(true)
            Float(n) =>
              exact_float(n) is None &&
              (
                !self.config.nonnumeric_floats ||
                !shape
                .map(s => s.body is Simple(Float | Double))
                .unwrap_or(false)
              )
            _ => false
          }
        }
        if invalid {
          budget.emit(
            UnsupportedValue,
            frame.path,
            frame.owner,
            "I cannot validate this native value kind in the selected value profile or placement.",
          )
          continue
        }
        if scalar is TypedNull(_) {
          node = Null
        }
      }
      NativeObject(_) if self.config.profile == JsonProfile => {
        budget.emit(
          UnsupportedValue,
          frame.path,
          frame.owner,
          "I cannot validate a native object in the JSON value profile.",
        )
        unsupported = true
      }
      _ => ()
    }
    if node is Null && frame.nullable {
      continue
    }
    if !unsupported && shape is Some(shape) {
      if check_kind(shape, node, self.config, budget, frame.path) {
        check_constraints(shape, node, budget, frame.path, self.config)
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
      Object(_) | LocatedObject(_) | NativeObject(_) => {
        let count = match node {
          Object(fields) => fields.length()
          LocatedObject(fields) => fields.length()
          NativeObject(fields) => fields.length()
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
        let unresolved : Array[(V, InstancePath)] = []
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
          NativeObject(fields) => {
            let resolved : Array[LocatedField[V]] = []
            for i in 0..<fields.length() {
              let (name, value) = fields[i]
              match name {
                Some(name) =>
                  resolved.push(
                    LocatedField::new(name, value, InstancePath::root()),
                  )
                None => {
                  let path = frame.path.child(FieldPosition(i))
                  budget.emit(
                    UnsupportedValue,
                    frame.path.child(FieldNamePosition(i)),
                    frame.owner,
                    "I expected a resolved object field name, but found an unresolved field symbol.",
                  )
                  unresolved.push((value, path))
                }
              }
            }
            resolved
          }
          _ => []
        }
        let occurrences : Map[String, Int32] = Map([])
        let present : Set[String] = Set([])
        let located : Array[(LocatedField[V], InstancePath, Int32)] = []
        for field in fields {
          let occurrence = occurrences.get(field.name).unwrap_or(0)
          occurrences[field.name] = occurrence + 1
          present.add(field.name)
          let path = if node is (Object(_) | NativeObject(_)) {
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
          if shape.body is Union(_) && count != 1 {
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
        for (value, path) in unresolved {
          stack.push({
            source: Original(value),
            expected: None,
            owner: frame.owner,
            path,
            depth: frame.depth + 1,
            nullable: false,
          })
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
