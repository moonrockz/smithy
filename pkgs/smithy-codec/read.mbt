///|
priv struct Target {
  shape : @smithy.ShapeId
  adapter : @contract.AdapterId?
}

///|
priv enum Build {
  BList(@validation.InstancePath, Int32)
  BStruct(@validation.InstancePath, Array[(String, Bool)])
  BUnion(@validation.InstancePath, String)
  BMap(@validation.InstancePath, Array[String])
  BObject(@validation.InstancePath, Array[String])
}

///|
priv enum Task {
  Visit(Json, @validation.InstancePath, Target, Int32)
  Document(Json, @validation.InstancePath, Int32)
  Rest(Array[Json], Int32, @validation.InstancePath, Target, Int32)
  /// A null element or value of a sparse list or map, kept without reading its target layout.
  SparseNull(@validation.InstancePath)
  Assemble(Build)
}

///|
priv struct Reader {
  contract : @contract.WireContract
  adapters : AdapterRegistry
  request : Request
  tasks : Array[Task]
  results : Array[LNode]
}

///|
fn Reader::invalid(self : Reader, path : @validation.InstancePath) -> Unit {
  self.results.push({ kind: LInvalid, source: path, })
}

///|
fn Reader::fail(
  self : Reader,
  code : CodecCode,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
  message : String,
) -> Unit {
  self.request.emit(code, path, shape, message)
  self.invalid(path)
}

///|
fn Reader::shape(
  self : Reader,
  id : @smithy.ShapeId,
) -> @contract.ShapeContract {
  self.contract.shapes.get(id).unwrap()
}

///|
fn Reader::room(
  self : Reader,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
  children : Int32,
) -> Bool {
  let meter = self.request.meter
  if children > meter.limit() - meter.used() {
    self.request.stop(path, shape, "work")
    return false
  }
  self.request.complete
}

///|
/// Call an adapter. Findings are emitted only when `quiet` is false.
fn Reader::adapt(
  self : Reader,
  id : @contract.AdapterId,
  value : Json,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
  quiet~ : Bool = false,
) -> ScalarValue? {
  guard self.adapters.get(id) is Some(adapter) else {
    if !quiet {
      self.request.emit(
        AdapterFailure,
        path,
        shape,
        "I expected the registered adapter \{id}.",
      )
    }
    return None
  }
  let kind = @contract.JsonKind::of(value)
  if !adapter.signature.inputs.contains(kind) {
    if !quiet {
      self.request.emit(
        KindMismatch,
        path,
        shape,
        "I expected a value that adapter \{id} reads, but found \{kind}.",
      )
    }
    return None
  }
  if !self.request.charge(path, shape) {
    return None
  }
  let result = (adapter.reader)(value, { meter: self.request.meter, })
  if self.request.meter.exhausted() {
    self.request.stop(path, shape, "work")
    return None
  }
  match result {
    Ok(scalar) => {
      if scalar.kind() != adapter.signature.output {
        if !quiet {
          self.request.emit(
            AdapterFailure,
            path,
            shape,
            "Adapter \{id} produced a \{scalar.kind()} value instead of \{adapter.signature.output}.",
          )
        }
        return None
      }
      if scalar is Text(text) &&
        !self.request.charge(path, shape, units=text.length() / 64) {
        return None
      }
      Some(scalar)
    }
    Err(failure) => {
      if !quiet {
        self.request.emit(
          AdapterFailure,
          path.append(failure.path),
          shape,
          failure.message,
        )
      }
      None
    }
  }
}

///|
fn scalar_node(scalar : ScalarValue) -> LKind {
  match scalar {
    Text(s) => LString(s)
    Numeric(n) => LNumber(n)
    Flag(b) => LBool(b)
  }
}

///|
fn expected(kind : @contract.JsonKind, found : Json) -> String {
  let article = if kind is (ArrayKind | ObjectKind) { "an" } else { "a" }
  "I expected \{article} \{kind} value, but found \{@contract.JsonKind::of(found)}."
}

///|
fn Reader::visit(
  self : Reader,
  json : Json,
  path : @validation.InstancePath,
  target : Target,
  depth : Int32,
) -> Unit {
  if !self.request.charge(path, target.shape) {
    return
  }
  if depth > self.request.limits.depth {
    self.request.stop(path, target.shape, "depth")
    return
  }
  let shape = self.shape(target.shape)
  match shape.layout {
    Scalar(adapter) => {
      let adapter = match target.adapter {
        Some(a) => Some(a)
        None => adapter
      }
      match adapter {
        Some(id) =>
          match self.adapt(id, json, path, shape.id) {
            Some(scalar) =>
              self.results.push({ kind: scalar_node(scalar), source: path, })
            None => self.invalid(path)
          }
        None =>
          if shape.kind == SimpleKind(Document) {
            self.tasks.push(Document(json, path, depth))
          } else {
            match json {
              Null => self.results.push({ kind: LNull, source: path, })
              True => self.results.push({ kind: LBool(true), source: path, })
              False => self.results.push({ kind: LBool(false), source: path, })
              String(s) =>
                self.results.push({ kind: LString(s), source: path, })
              Number(_, ..) =>
                match json_number(json) {
                  Some(n) =>
                    self.results.push({ kind: LNumber(n), source: path, })
                  None =>
                    self.fail(
                      Constraint(InvalidNumber),
                      path,
                      shape.id,
                      "I expected an exact finite numeric token.",
                    )
                }
              Array(_) | Object(_) =>
                self.fail(
                  KindMismatch,
                  path,
                  shape.id,
                  "I expected a scalar value, but found \{@contract.JsonKind::of(json)}.",
                )
            }
          }
      }
    }
    ListShape => {
      guard json is Array(items) else {
        if json is Null {
          self.results.push({ kind: LNull, source: path, })
          return
        }
        self.fail(KindMismatch, path, shape.id, expected(ArrayKind, json))
        return
      }
      if !self.room(path, shape.id, items.length()) {
        return
      }
      let item = shape.members[0]
      self.tasks.push(Assemble(BList(path, items.length())))
      for i = items.length() - 1; i >= 0; i = i - 1 {
        if shape.sparse && items[i] is Null {
          self.tasks.push(SparseNull(index_path(path, i)))
          continue
        }
        self.tasks.push(
          Visit(
            items[i],
            index_path(path, i),
            { shape: item.target, adapter: item.adapter, },
            depth + 1,
          ),
        )
      }
    }
    Dictionary(layout) => self.dictionary(json, path, shape, layout, depth)
    ObjectStructure | TupleStructure(_) => {
      if self.apply_forms(json, path, shape, depth) {
        return
      }
      self.structure(json, path, shape, depth)
    }
    UnionShape(layout) => {
      if self.apply_forms(json, path, shape, depth) {
        return
      }
      self.union_(json, path, shape, layout, depth)
    }
  }
}

///|
fn Reader::structure(
  self : Reader,
  json : Json,
  path : @validation.InstancePath,
  shape : @contract.ShapeContract,
  depth : Int32,
) -> Unit {
  match shape.layout {
    TupleStructure(t) => {
      guard json is Array(items) else {
        if json is Null {
          self.results.push({ kind: LNull, source: path, })
          return
        }
        self.fail(KindMismatch, path, shape.id, expected(ArrayKind, json))
        return
      }
      self.positions(items, 0, path, shape, t.fixed, t.rest, t.optional, depth)
    }
    _ => {
      guard json is Object(fields) else {
        if json is Null {
          self.results.push({ kind: LNull, source: path, })
          return
        }
        self.fail(KindMismatch, path, shape.id, expected(ObjectKind, json))
        return
      }
      self.object_fields(fields, path, shape, None, depth)
    }
  }
}

///|
/// Project the fields of an object onto structure members, skipping a discriminator.
fn Reader::object_fields(
  self : Reader,
  fields : Map[String, Json],
  path : @validation.InstancePath,
  shape : @contract.ShapeContract,
  skip : @contract.WireName?,
  depth : Int32,
) -> Unit {
  if !self.room(path, shape.id, fields.length()) {
    return
  }
  let slots : Array[(Json, @validation.InstancePath, String)?] = Array::make(
    shape.members.length(),
    None,
  )
  let mut failed = false
  let flattened = shape.members.search_by(m => m.flatten)
  let rest : Map[String, Json] = Map([])
  for name, value in fields {
    if skip is Some(tag) && tag.to_string() == name {
      continue
    }
    let field = field_path(path, name)
    let mut found = None
    for i, m in shape.members {
      if (!m.flatten && m.wire.to_string() == name) ||
        m.aliases.iter().any(a => a.to_string() == name) {
        found = Some(i)
        break
      }
    }
    match found {
      None if flattened is Some(_) => rest[name] = value
      None =>
        if self.contract.unknown_members == RejectUnknown {
          self.request.emit(
            UnknownMember,
            field,
            shape.id,
            "I expected a declared member, but found unknown member \{name.escape()}.",
          )
          failed = true
        }
      Some(i) if value is Null && shape.members[i].null_when_absent => ()
      Some(i) =>
        match slots[i] {
          Some((_, _, first)) => {
            self.request.emit(
              MemberCollision,
              field,
              shape.members[i].member_id,
              "Fields \{first.escape()} and \{name.escape()} both supply member \{shape.members[i].name}.",
            )
            failed = true
          }
          None => slots[i] = Some((value, field, name))
        }
    }
  }
  if flattened is Some(f) && !rest.is_empty() {
    match slots[f] {
      Some((_, _, field_name)) => {
        self.request.emit(
          MemberCollision,
          path,
          shape.members[f].member_id,
          "Field \{field_name.escape()} and flattened fields both supply member \{shape.members[f].name}.",
        )
        failed = true
      }
      None => slots[f] = Some((Json::object(rest), path, shape.members[f].name))
    }
  }
  for i, m in shape.members {
    if m.required && slots[i] is None {
      self.request.emit(
        MissingMember,
        field_path(path, m.wire.to_string()),
        m.member_id,
        "I expected the required member \{m.name}, but found it absent.",
      )
      failed = true
    }
  }
  if failed {
    self.invalid(path)
    return
  }
  let names : Array[(String, Bool)] = []
  let visits : Array[Task] = []
  for i, m in shape.members {
    if slots[i] is Some((value, field, _)) {
      names.push((m.name, m.empty_as_absent))
      visits.push(
        Visit(value, field, { shape: m.target, adapter: m.adapter, }, depth + 1),
      )
    }
  }
  self.tasks.push(Assemble(BStruct(path, names)))
  for i = visits.length() - 1; i >= 0; i = i - 1 {
    self.tasks.push(visits[i])
  }
}

///|
/// Project array positions onto structure members. `offset` is the index of the first position in the
/// source array, which is 1 after a tag.
fn Reader::positions(
  self : Reader,
  items : ArrayView[Json],
  offset : Int32,
  path : @validation.InstancePath,
  shape : @contract.ShapeContract,
  fixed : Array[Int32],
  rest : Int32?,
  optional : @contract.OptionalTail?,
  depth : Int32,
) -> Unit {
  if !self.room(path, shape.id, items.length()) {
    return
  }
  let slots : Array[Task?] = Array::make(shape.members.length(), None)
  let mut failed = false
  for p, i in fixed {
    let m = shape.members[i]
    let at = index_path(path, p + offset)
    if p >= items.length() {
      if m.required || optional is None {
        self.request.emit(
          MissingMember,
          at,
          m.member_id,
          "I expected member \{m.name} at position \{p + offset}, but the array has \{items.length() + offset} elements.",
        )
        failed = true
      }
      continue
    }
    let item = items[p]
    if item is Null && !m.required && optional == Some(NullTail) {
      continue
    }
    slots[i] = Some(
      Visit(item, at, { shape: m.target, adapter: m.adapter, }, depth + 1),
    )
  }
  if items.length() > fixed.length() {
    match rest {
      None => {
        self.request.emit(
          Arity,
          index_path(path, fixed.length() + offset),
          shape.id,
          "I expected at most \{fixed.length() + offset} elements, but found \{items.length() + offset}.",
        )
        failed = true
      }
      Some(r) => {
        let m = shape.members[r]
        let list = self.shape(m.target)
        let item = list.members[0]
        slots[r] = Some(
          Rest(
            items[fixed.length():].to_owned(),
            fixed.length() + offset,
            path,
            { shape: item.target, adapter: item.adapter, },
            depth + 1,
          ),
        )
      }
    }
  } else if rest is Some(r) && shape.members[r].required {
    slots[r] = Some(
      Rest(
        [],
        fixed.length() + offset,
        path,
        { shape: shape.members[r].target, adapter: None, },
        depth + 1,
      ),
    )
  }
  if failed {
    self.invalid(path)
    return
  }
  let names : Array[(String, Bool)] = []
  let visits : Array[Task] = []
  for i, m in shape.members {
    if slots[i] is Some(task) {
      names.push((m.name, m.empty_as_absent))
      visits.push(task)
    }
  }
  self.tasks.push(Assemble(BStruct(path, names)))
  for i = visits.length() - 1; i >= 0; i = i - 1 {
    self.tasks.push(visits[i])
  }
}

///|
fn Reader::dictionary(
  self : Reader,
  json : Json,
  path : @validation.InstancePath,
  shape : @contract.ShapeContract,
  layout : @contract.DictionaryLayout,
  depth : Int32,
) -> Unit {
  let value_member = shape.members[1]
  let value_target = {
    shape: value_member.target,
    adapter: value_member.adapter,
  }
  let keys : Array[String] = []
  let visits : Array[Task] = []
  let seen : Map[String, @validation.InstancePath] = Map([])
  let mut failed = false
  let add = fn(key : String, key_path, value : Json, value_path) {
    if seen.contains(key) {
      self.request.emit(
        DuplicateKey,
        key_path,
        shape.id,
        "I found a second entry for the key \{key.escape()}.",
      )
      failed = true
      return
    }
    seen[key] = key_path
    keys.push(key)
    if shape.sparse && value is Null {
      visits.push(SparseNull(value_path))
    } else {
      visits.push(Visit(value, value_path, value_target, depth + 1))
    }
  }
  let read_key = fn(key : Json, key_path) -> String? {
    match layout.key_adapter {
      Some(id) =>
        match self.adapt(id, key, key_path, shape.members[0].member_id) {
          Some(Text(text)) => Some(text)
          _ => None
        }
      None =>
        match key {
          String(text) => Some(text)
          _ => {
            self.request.emit(
              KindMismatch,
              key_path,
              shape.members[0].member_id,
              expected(StringKind, key),
            )
            None
          }
        }
    }
  }
  let entries_layout = if layout.accept_other {
    json is Array(_)
  } else {
    layout.entries
  }
  if entries_layout {
    guard json is Array(entries) else {
      self.fail(KindMismatch, path, shape.id, expected(ArrayKind, json))
      return
    }
    if !self.room(path, shape.id, entries.length()) {
      return
    }
    for i, entry in entries {
      let at = index_path(path, i)
      guard entry is Array(pair) else {
        self.request.emit(
          KindMismatch,
          at,
          shape.id,
          "I expected a [key, value] entry, but found \{@contract.JsonKind::of(entry)}.",
        )
        failed = true
        continue
      }
      guard pair.length() == 2 else {
        self.request.emit(
          Arity,
          at,
          shape.id,
          "I expected a [key, value] entry of 2 elements, but found \{pair.length()}.",
        )
        failed = true
        continue
      }
      match read_key(pair[0], index_path(at, 0)) {
        Some(key) => add(key, index_path(at, 0), pair[1], index_path(at, 1))
        None => failed = true
      }
    }
  } else {
    guard json is Object(fields) else {
      self.fail(KindMismatch, path, shape.id, expected(ObjectKind, json))
      return
    }
    if !self.room(path, shape.id, fields.length()) {
      return
    }
    for name, value in fields {
      let at = field_path(path, name)
      match read_key(Json::string(name), at) {
        Some(key) => add(key, at, value, at)
        None => failed = true
      }
    }
  }
  if failed {
    self.invalid(path)
    return
  }
  self.tasks.push(Assemble(BMap(path, keys)))
  for i = visits.length() - 1; i >= 0; i = i - 1 {
    self.tasks.push(visits[i])
  }
}

///|
fn Reader::member_by_tag(
  self : Reader,
  shape : @contract.ShapeContract,
  tag : String,
  path : @validation.InstancePath,
) -> Int32? {
  for i, m in shape.members {
    if m.tag.to_string() == tag ||
      m.aliases.iter().any(a => a.to_string() == tag) {
      return Some(i)
    }
  }
  self.request.emit(
    UnknownTag,
    path,
    shape.id,
    "I expected a declared union tag, but found \{tag.escape()}.",
  )
  None
}

///|
fn unit_like(shape : @contract.ShapeContract) -> Bool {
  shape.kind == StructureKind &&
  shape.members.is_empty() &&
  shape.layout is ObjectStructure
}

///|
fn Reader::union_(
  self : Reader,
  json : Json,
  path : @validation.InstancePath,
  shape : @contract.ShapeContract,
  layout : @contract.UnionLayout,
  depth : Int32,
) -> Unit {
  let layout = if shape.accepts.is_empty() {
    layout
  } else {
    match self.accepted_layout(json, path, shape, layout) {
      Some(l) => l
      None => return
    }
  }
  match layout {
    External => {
      guard json is Object(fields) else {
        self.fail(KindMismatch, path, shape.id, expected(ObjectKind, json))
        return
      }
      guard fields.length() == 1 else {
        self.fail(
          Arity,
          path,
          shape.id,
          "I expected exactly one union member, but found \{fields.length()}.",
        )
        return
      }
      for tag, value in fields {
        let at = field_path(path, tag)
        guard self.member_by_tag(shape, tag, at) is Some(i) else {
          self.invalid(path)
          return
        }
        let m = shape.members[i]
        self.tasks.push(Assemble(BUnion(path, m.name)))
        self.tasks.push(
          Visit(value, at, { shape: m.target, adapter: m.adapter, }, depth + 1),
        )
      }
    }
    Internal(tag~) => {
      guard json is Object(fields) else {
        self.fail(KindMismatch, path, shape.id, expected(ObjectKind, json))
        return
      }
      let at = field_path(path, tag.to_string())
      guard fields.get(tag.to_string()) is Some(value) else {
        self.fail(
          MissingMember,
          at,
          shape.id,
          "I expected the discriminator \{tag}, but found it absent.",
        )
        return
      }
      guard value is String(name) else {
        self.fail(KindMismatch, at, shape.id, expected(StringKind, value))
        return
      }
      guard self.member_by_tag(shape, name, at) is Some(i) else {
        self.invalid(path)
        return
      }
      let m = shape.members[i]
      self.tasks.push(Assemble(BUnion(path, m.name)))
      self.object_fields(
        fields,
        path,
        self.shape(m.target),
        Some(tag),
        depth + 1,
      )
    }
    Adjacent(tag~, content~) => {
      guard json is Object(fields) else {
        self.fail(KindMismatch, path, shape.id, expected(ObjectKind, json))
        return
      }
      let mut failed = false
      for name, _ in fields {
        if name != tag.to_string() && name != content.to_string() {
          self.request.emit(
            UnknownMember,
            field_path(path, name),
            shape.id,
            "I expected only the fields \{tag} and \{content}, but found \{name.escape()}.",
          )
          failed = true
        }
      }
      let at = field_path(path, tag.to_string())
      guard fields.get(tag.to_string()) is Some(value) else {
        self.fail(
          MissingMember,
          at,
          shape.id,
          "I expected the tag field \{tag}, but found it absent.",
        )
        return
      }
      guard value is String(name) else {
        self.fail(KindMismatch, at, shape.id, expected(StringKind, value))
        return
      }
      guard !failed && self.member_by_tag(shape, name, at) is Some(i) else {
        self.invalid(path)
        return
      }
      let m = shape.members[i]
      let target = self.shape(m.target)
      let content_path = field_path(path, content.to_string())
      match fields.get(content.to_string()) {
        Some(payload) => {
          self.tasks.push(Assemble(BUnion(path, m.name)))
          self.tasks.push(
            Visit(
              payload,
              content_path,
              { shape: m.target, adapter: m.adapter, },
              depth + 1,
            ),
          )
        }
        None =>
          if unit_like(target) {
            self.results.push({
              kind: LUnion(m.name, { kind: LStruct([]), source: path, }),
              source: path,
            })
          } else {
            self.fail(
              MissingMember,
              content_path,
              shape.id,
              "I expected the content field \{content}, but found it absent.",
            )
          }
      }
    }
    TagArray(tag_only_unit~) => {
      guard json is Array(items) else {
        self.fail(KindMismatch, path, shape.id, expected(ArrayKind, json))
        return
      }
      guard items.length() >= 1 else {
        self.fail(Arity, path, shape.id, "I expected a tag at position 0.")
        return
      }
      let at = index_path(path, 0)
      guard items[0] is String(name) else {
        self.fail(KindMismatch, at, shape.id, expected(StringKind, items[0]))
        return
      }
      guard self.member_by_tag(shape, name, at) is Some(i) else {
        self.invalid(path)
        return
      }
      let m = shape.members[i]
      let target = self.shape(m.target)
      if tag_only_unit && unit_like(target) {
        guard items.length() == 1 else {
          self.fail(
            Arity,
            index_path(path, 1),
            shape.id,
            "I expected only the tag of the Unit member \{m.name}.",
          )
          return
        }
        self.results.push({
          kind: LUnion(m.name, { kind: LStruct([]), source: path, }),
          source: path,
        })
        return
      }
      match target.layout {
        TupleStructure(t) => {
          self.tasks.push(Assemble(BUnion(path, m.name)))
          self.positions(
            items[1:],
            1,
            path,
            target,
            t.fixed,
            t.rest,
            t.optional,
            depth + 1,
          )
        }
        _ => {
          guard items.length() == 2 else {
            self.fail(
              Arity,
              path,
              shape.id,
              "I expected a tag and one payload element, but found \{items.length()} elements.",
            )
            return
          }
          self.tasks.push(Assemble(BUnion(path, m.name)))
          self.tasks.push(
            Visit(
              items[1],
              index_path(path, 1),
              { shape: m.target, adapter: m.adapter, },
              depth + 1,
            ),
          )
        }
      }
    }
    Untagged(kinds) => {
      let kind = @contract.JsonKind::of(json)
      let mut selected = None
      for entry in kinds {
        if entry.0 == kind {
          selected = Some(entry.1)
        }
      }
      guard selected is Some(i) else {
        self.fail(
          KindMismatch,
          path,
          shape.id,
          "I expected a value of one of the union's JSON kinds, but found \{kind}.",
        )
        return
      }
      let m = shape.members[i]
      self.tasks.push(Assemble(BUnion(path, m.name)))
      self.tasks.push(
        Visit(json, path, { shape: m.target, adapter: m.adapter, }, depth + 1),
      )
    }
  }
}

///|
/// Read a compact form. Returns true when a form, or an ambiguity between forms, decided the value.
fn Reader::apply_forms(
  self : Reader,
  json : Json,
  path : @validation.InstancePath,
  shape : @contract.ShapeContract,
  depth : Int32,
) -> Bool {
  if shape.forms.is_empty() {
    return false
  }
  let kind = @contract.JsonKind::of(json)
  let matches : Array[@contract.Form] = []
  for form in shape.forms {
    if form.reader.kind != kind {
      continue
    }
    if form.reader.field is Some(field) &&
      !(json is Object(fields) && fields.contains(field.to_string())) {
      continue
    }
    if form.reader.absent is Some(field) &&
      json is Object(fields) &&
      fields.contains(field.to_string()) {
      continue
    }
    if form.reader.adapter is Some(id) &&
      self.adapt(id, json, path, shape.id, quiet=true) is None {
      if !self.request.complete {
        return true
      }
      continue
    }
    matches.push(form)
  }
  match matches {
    [] => false
    [form] => {
      match form.union_member {
        Some(i) => {
          let m = shape.members[i]
          self.tasks.push(Assemble(BUnion(path, m.name)))
          self.bind(
            json,
            path,
            form.binding,
            self.shape(m.target),
            m.adapter,
            depth,
          )
        }
        None => self.bind(json, path, form.binding, shape, None, depth)
      }
      true
    }
    _ => {
      self.fail(
        AmbiguousForm,
        path,
        shape.id,
        "I found \{matches.length()} compact forms that read this \{kind} value.",
      )
      true
    }
  }
}

///|
fn Reader::bind(
  self : Reader,
  json : Json,
  path : @validation.InstancePath,
  binding : @contract.FormBinding,
  payload : @contract.ShapeContract,
  adapter : @contract.AdapterId?,
  depth : Int32,
) -> Unit {
  match binding {
    Whole(-1) =>
      self.tasks.push(
        Visit(json, path, { shape: payload.id, adapter, }, depth + 1),
      )
    Whole(i) => {
      let m = payload.members[i]
      self.tasks.push(Assemble(BStruct(path, [(m.name, m.empty_as_absent)])))
      self.tasks.push(
        Visit(json, path, { shape: m.target, adapter: m.adapter, }, depth + 1),
      )
    }
    Positional(fixed~, rest~) =>
      match json {
        Array(items) =>
          self.positions(
            items[:],
            0,
            path,
            payload,
            fixed,
            rest,
            None,
            depth + 1,
          )
        _ =>
          self.fail(KindMismatch, path, payload.id, expected(ArrayKind, json))
      }
  }
}

///|
fn Reader::document(
  self : Reader,
  json : Json,
  path : @validation.InstancePath,
  depth : Int32,
) -> Unit {
  let root = self.contract.root
  if !self.request.charge(path, root) {
    return
  }
  if depth > self.request.limits.depth {
    self.request.stop(path, root, "depth")
    return
  }
  match json {
    Null => self.results.push({ kind: LNull, source: path, })
    True => self.results.push({ kind: LBool(true), source: path, })
    False => self.results.push({ kind: LBool(false), source: path, })
    String(s) => self.results.push({ kind: LString(s), source: path, })
    Number(_, ..) =>
      match json_number(json) {
        Some(n) => self.results.push({ kind: LNumber(n), source: path, })
        None =>
          self.fail(
            Constraint(InvalidNumber),
            path,
            root,
            "I expected an exact finite numeric token.",
          )
      }
    Array(items) => {
      if !self.room(path, root, items.length()) {
        return
      }
      self.tasks.push(Assemble(BList(path, items.length())))
      for i = items.length() - 1; i >= 0; i = i - 1 {
        self.tasks.push(Document(items[i], index_path(path, i), depth + 1))
      }
    }
    Object(fields) => {
      if !self.room(path, root, fields.length()) {
        return
      }
      let names = fields.keys().to_array()
      self.tasks.push(Assemble(BObject(path, names)))
      for i = names.length() - 1; i >= 0; i = i - 1 {
        self.tasks.push(
          Document(
            fields.get(names[i]).unwrap(),
            field_path(path, names[i]),
            depth + 1,
          ),
        )
      }
    }
  }
}

///|
fn Reader::take(self : Reader, n : Int32) -> Array[LNode] {
  let items : Array[LNode] = []
  for _ in 0..<n {
    items.push(self.results.pop().unwrap())
  }
  items.rev_in_place()
  items
}

///|
fn Reader::assemble(self : Reader, build : Build) -> Unit {
  match build {
    BList(path, n) =>
      self.results.push({ kind: LList(self.take(n)), source: path, })
    BStruct(path, names) => {
      let items = self.take(names.length())
      let fields : Array[(String, LNode)] = []
      for i, entry in names {
        if entry.1 && items[i].kind.is_empty() {
          continue
        }
        fields.push((entry.0, items[i]))
      }
      self.results.push({ kind: LStruct(fields), source: path, })
    }
    BUnion(path, name) => {
      let payload = self.take(1)[0]
      self.results.push({ kind: LUnion(name, payload), source: path, })
    }
    BMap(path, keys) => {
      let items = self.take(keys.length())
      let fields : Array[(String, LNode)] = []
      for i, key in keys {
        fields.push((key, items[i]))
      }
      self.results.push({ kind: LMap(fields), source: path, })
    }
    BObject(path, keys) => {
      let items = self.take(keys.length())
      let fields : Array[(String, LNode)] = []
      for i, key in keys {
        fields.push((key, items[i]))
      }
      self.results.push({ kind: LObject(fields), source: path, })
    }
  }
}

///|
/// Project a parsed JSON value onto the contract. Returns no node when the request failed.
fn read_json(
  contract : @contract.WireContract,
  adapters : AdapterRegistry,
  request : Request,
  json : Json,
  path : @validation.InstancePath,
) -> LNode? {
  let reader : Reader = {
    contract,
    adapters,
    request,
    tasks: [Visit(json, path, { shape: contract.root, adapter: None, }, 0)],
    results: [],
  }
  while reader.tasks.pop() is Some(task) {
    if !request.complete {
      break
    }
    match task {
      Visit(json, path, target, depth) =>
        reader.visit(json, path, target, depth)
      Document(json, path, depth) => reader.document(json, path, depth)
      Rest(items, start, path, target, depth) => {
        if !reader.room(path, target.shape, items.length()) {
          break
        }
        reader.tasks.push(Assemble(BList(path, items.length())))
        for i = items.length() - 1; i >= 0; i = i - 1 {
          reader.tasks.push(
            Visit(items[i], index_path(path, start + i), target, depth),
          )
        }
      }
      SparseNull(path) => reader.results.push({ kind: LNull, source: path, })
      Assemble(build) => reader.assemble(build)
    }
  }
  if !request.complete || !request.findings.is_empty() {
    return None
  }
  reader.results.pop()
}

///|
/// Choose among a union's own layout and its reader-only layouts for an object input. Internal and
/// adjacent layouts apply when their tag field is present; an adjacent layout also needs its content
/// field and then wins over an internal layout with the same tag. An external layout applies to an
/// object with one field that names a member.
fn Reader::accepted_layout(
  self : Reader,
  json : Json,
  path : @validation.InstancePath,
  shape : @contract.ShapeContract,
  main : @contract.UnionLayout,
) -> @contract.UnionLayout? {
  guard json is Object(fields) else {
    if json is Array(_) && !(main is TagArray(..)) {
      for alternative in shape.accepts {
        if alternative is TagArray(..) {
          return Some(alternative)
        }
      }
    }
    return Some(main)
  }
  let names_member = fn(name : String) {
    shape.members
    .iter()
    .any(m => {
      m.tag.to_string() == name ||
      m.aliases.iter().any(a => a.to_string() == name)
    })
  }
  let applies = fn(layout : @contract.UnionLayout) {
    match layout {
      External => fields.length() == 1 && fields.keys().iter().all(names_member)
      Internal(tag~) => fields.contains(tag.to_string())
      Adjacent(tag~, content~) =>
        fields.contains(tag.to_string()) && fields.contains(content.to_string())
      _ => false
    }
  }
  let candidates = ([main] + shape.accepts).filter(applies)
  let adjacent_tags = candidates.filter_map(l => {
    match l {
      Adjacent(tag~, ..) => Some(tag)
      _ => None
    }
  })
  let chosen = candidates.filter(l => {
    !(l is Internal(tag~) && adjacent_tags.contains(tag))
  })
  match chosen {
    [] => Some(main)
    [one] => Some(one)
    _ => {
      self.fail(
        AmbiguousForm,
        path,
        shape.id,
        "I found \{chosen.length()} union layouts that read this object.",
      )
      None
    }
  }
}
