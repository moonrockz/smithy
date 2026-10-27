///|
priv enum WTask {
  WValue(LogicalValue, Target, @validation.InstancePath, Int32)
  WJson(Json)
  WText(String)
}

///|
fn write_string(out : StringBuilder, text : String) -> Unit {
  out.write_char('"')
  for i in 0..<text.length() {
    let c = text.code_unit_at(i).to_int()
    match c {
      0x22 => out.write_string("\\\"")
      0x5C => out.write_string("\\\\")
      0x0A => out.write_string("\\n")
      0x0D => out.write_string("\\r")
      0x09 => out.write_string("\\t")
      0x08 => out.write_string("\\b")
      0x0C => out.write_string("\\f")
      _ =>
        if c < 0x20 {
          let digits = "0123456789abcdef"
          out.write_string("\\u00")
          out.write_char(digits[c >> 4].to_int().unsafe_to_char())
          out.write_char(digits[c & 15].to_int().unsafe_to_char())
        } else {
          out.write_char(text.code_unit_at(i).to_int().unsafe_to_char())
        }
    }
  }
  out.write_char('"')
}

///|
fn json_string(text : String) -> String {
  let out = StringBuilder()
  write_string(out, text)
  out.to_string()
}

///|
priv struct Writer {
  contract : @contract.WireContract
  adapters : AdapterRegistry
  request : Request
  tasks : Array[WTask]
  out : StringBuilder
}

///|
fn Writer::fail(
  self : Writer,
  code : CodecCode,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
  message : String,
) -> Unit {
  self.request.emit(code, path, shape, message)
}

///|
/// Push tasks so that they run in the given order.
fn Writer::sequence(self : Writer, items : Array[WTask]) -> Unit {
  for i = items.length() - 1; i >= 0; i = i - 1 {
    self.tasks.push(items[i])
  }
}

///|
fn joined(
  open : String,
  items : Array[Array[WTask]],
  close : String,
) -> Array[WTask] {
  let out : Array[WTask] = [WText(open)]
  for i, item in items {
    if i > 0 {
      out.push(WText(","))
    }
    for task in item {
      out.push(task)
    }
  }
  out.push(WText(close))
  out
}

///|
fn Writer::adapter_json(
  self : Writer,
  id : @contract.AdapterId,
  value : LogicalValue,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
) -> Json? {
  guard self.adapters.get(id) is Some(adapter) else {
    self.fail(
      AdapterFailure,
      path,
      shape,
      "I expected the registered adapter \{id}.",
    )
    return None
  }
  let scalar = match value {
    String(s) => Text(s)
    Number(n) => Numeric(n)
    Boolean(b) => Flag(b)
    _ => {
      self.fail(
        UnrepresentableValue,
        path,
        shape,
        "Adapter \{id} writes scalars, but found \{logical_kind(value)}.",
      )
      return None
    }
  }
  if !self.request.charge(path, shape) {
    return None
  }
  let result = (adapter.writer)(scalar, { meter: self.request.meter, })
  if self.request.meter.exhausted() {
    self.request.stop(path, shape, "work")
    return None
  }
  match result {
    Ok(json) => {
      let kind = @contract.JsonKind::of(json)
      if !adapter.signature.inputs.contains(kind) {
        self.fail(
          AdapterFailure,
          path,
          shape,
          "Adapter \{id} wrote a \{kind} value, which it does not read.",
        )
        return None
      }
      Some(json)
    }
    Err(failure) => {
      self.fail(
        AdapterFailure,
        path.append(failure.path),
        shape,
        failure.message,
      )
      None
    }
  }
}

///|
fn guard_holds(
  guard_ : @contract.WriterGuard,
  value : LogicalValue,
  shape : @contract.ShapeContract,
) -> Bool {
  let field = fn(i : Int32) { value.get(shape.members[i].name) }
  guard_.empty.iter().all(i => field(i).map(v => v.is_empty()).unwrap_or(true)) &&
  guard_.present
  .iter()
  .all(i => field(i).map(v => !v.is_empty()).unwrap_or(false))
}

///|
fn Writer::positions(
  self : Writer,
  value : LogicalValue,
  shape : @contract.ShapeContract,
  fixed : Array[Int32],
  rest : Int32?,
  optional : @contract.OptionalTail?,
  path : @validation.InstancePath,
  depth : Int32,
) -> Array[Array[WTask]]? {
  let slots : Array[Array[WTask]?] = []
  for i in fixed {
    let m = shape.members[i]
    match value.get(m.name) {
      Some(v) =>
        slots.push(
          Some([
            WValue(
              v,
              { shape: m.target, adapter: m.adapter, },
              field_path(path, m.name),
              depth + 1,
            ),
          ]),
        )
      None => slots.push(None)
    }
  }
  // Drop absent optional positions at the end; a hole before a present position needs null positions.
  while slots.length() > 0 &&
        slots[slots.length() - 1] is None &&
        optional == Some(OmitTail) {
    ignore(slots.pop())
  }
  let items : Array[Array[WTask]] = []
  for p, slot in slots {
    match slot {
      Some(tasks) => items.push(tasks)
      None =>
        if optional == Some(NullTail) {
          items.push([WText("null")])
        } else {
          let m = shape.members[fixed[p]]
          self.fail(
            UnrepresentableValue,
            field_path(path, m.name),
            m.member_id,
            "I cannot write member \{m.name} as absent at position \{p} before a later present position.",
          )
          return None
        }
    }
  }
  if rest is Some(r) {
    let m = shape.members[r]
    match value.get(m.name) {
      Some(List(list)) => {
        if list.length() > 0 && slots.length() < fixed.length() {
          self.fail(
            UnrepresentableValue,
            field_path(path, m.name),
            m.member_id,
            "I cannot write rest elements after absent positions.",
          )
          return None
        }
        let item = self.contract.shapes.get(m.target).unwrap().members[0]
        for i, v in list {
          items.push([
            WValue(
              v,
              { shape: item.target, adapter: item.adapter, },
              index_path(field_path(path, m.name), i),
              depth + 1,
            ),
          ])
        }
      }
      Some(other) =>
        self.fail(
          UnrepresentableValue,
          field_path(path, m.name),
          m.member_id,
          "I expected a list of rest elements, but found \{logical_kind(other)}.",
        )
      None => ()
    }
  }
  Some(items)
}

///|
fn Writer::form(
  self : Writer,
  value : LogicalValue,
  binding : @contract.FormBinding,
  payload : @contract.ShapeContract,
  adapter : @contract.AdapterId?,
  path : @validation.InstancePath,
  depth : Int32,
) -> Unit {
  match binding {
    Whole(-1) =>
      self.tasks.push(
        WValue(value, { shape: payload.id, adapter, }, path, depth + 1),
      )
    Whole(i) => {
      let m = payload.members[i]
      match value.get(m.name) {
        Some(v) =>
          self.tasks.push(
            WValue(
              v,
              { shape: m.target, adapter: m.adapter, },
              field_path(path, m.name),
              depth + 1,
            ),
          )
        None =>
          self.fail(
            UnrepresentableValue,
            field_path(path, m.name),
            m.member_id,
            "The compact form needs member \{m.name}.",
          )
      }
    }
    Positional(fixed~, rest~) =>
      match self.positions(value, payload, fixed, rest, None, path, depth) {
        Some(items) => self.sequence(joined("[", items, "]"))
        None => ()
      }
  }
}

///|
/// The single writer form whose guard holds, None when no form applies, or a failure when several apply.
fn Writer::choose(
  self : Writer,
  forms : Array[@contract.Form],
  union_member : Int32?,
  value : LogicalValue,
  payload : @contract.ShapeContract,
  path : @validation.InstancePath,
  shape : @smithy.ShapeId,
) -> Result[@contract.Form?, Unit] {
  if self.contract.writer == Expanded {
    return Ok(None)
  }
  let found : Array[@contract.Form] = []
  for form in forms {
    if form.union_member == union_member &&
      form.writer is Some(guard_) &&
      guard_holds(guard_, value, payload) {
      found.push(form)
    }
  }
  match found {
    [] => Ok(None)
    [form] => Ok(Some(form))
    _ => {
      self.fail(
        UnrepresentableValue,
        path,
        shape,
        "\{found.length()} canonical writer forms apply to this value; I will not choose one by order.",
      )
      Err(())
    }
  }
}

///|
fn Writer::object_fields(
  self : Writer,
  value : LogicalValue,
  shape : @contract.ShapeContract,
  path : @validation.InstancePath,
  depth : Int32,
) -> Array[Array[WTask]] {
  let items : Array[Array[WTask]] = []
  for m in shape.members {
    match value.get(m.name) {
      Some(Union(name, payload)) if m.flatten => {
        let union_shape = self.contract.shapes.get(m.target).unwrap()
        match union_shape.member_index(name) {
          Some(i) => {
            let alternative = union_shape.members[i]
            items.push([
              WText(json_string(alternative.tag.to_string()) + ":"),
              WValue(
                payload,
                { shape: alternative.target, adapter: alternative.adapter, },
                field_path(field_path(path, m.name), name),
                depth + 1,
              ),
            ])
          }
          None =>
            self.fail(
              UnknownTag,
              field_path(path, m.name),
              union_shape.id,
              "I expected a declared union member.",
            )
        }
      }
      Some(v) =>
        items.push([
          WText(json_string(m.wire.to_string()) + ":"),
          WValue(
            v,
            { shape: m.target, adapter: m.adapter, },
            field_path(path, m.name),
            depth + 1,
          ),
        ])
      None =>
        if m.null_when_absent {
          items.push([WText(json_string(m.wire.to_string()) + ":null")])
        }
    }
  }
  items
}

///|
fn Writer::value(
  self : Writer,
  value : LogicalValue,
  target : Target,
  path : @validation.InstancePath,
  depth : Int32,
) -> Unit {
  if !self.request.charge(path, target.shape) {
    return
  }
  if depth > self.request.limits.depth {
    self.request.stop(path, target.shape, "depth")
    return
  }
  let shape = self.contract.shapes.get(target.shape).unwrap()
  match shape.layout {
    Scalar(adapter) => {
      let adapter = match target.adapter {
        Some(a) => Some(a)
        None => adapter
      }
      match adapter {
        Some(id) =>
          match self.adapter_json(id, value, path, shape.id) {
            Some(json) => self.tasks.push(WJson(json))
            None => ()
          }
        None => self.tasks.push(WJson(logical_json(value)))
      }
    }
    ListShape =>
      match value {
        List(items) => {
          let m = shape.members[0]
          self.sequence(
            joined(
              "[",
              items.mapi((i, v) => {
                [
                  WValue(
                    v,
                    { shape: m.target, adapter: m.adapter, },
                    index_path(path, i),
                    depth + 1,
                  ),
                ]
              }),
              "]",
            ),
          )
        }
        _ => self.tasks.push(WText("null"))
      }
    Dictionary(layout) => {
      let fields = entries(value).unwrap_or([]).copy()
      match layout.order {
        LexicalKeys => fields.sort_by((a, b) => a.0.lexical_compare(b.0))
        AdapterKeys =>
          match
            layout.key_adapter
            .bind(id => self.adapters.get(id))
            .bind(a => a.compare) {
            Some(compare) => fields.sort_by((a, b) => compare(a.0, b.0))
            None => ()
          }
        PreservedKeys => ()
      }
      let m = shape.members[1]
      let items : Array[Array[WTask]] = []
      for field in fields {
        let value_task = WValue(
          field.1,
          { shape: m.target, adapter: m.adapter, },
          field_path(path, field.0),
          depth + 1,
        )
        let key = match layout.key_adapter {
          Some(id) =>
            match
              self.adapter_json(
                id,
                String(field.0),
                field_path(path, field.0),
                shape.members[0].member_id,
              ) {
              Some(json) => json
              None => return
            }
          None => Json::string(field.0)
        }
        if layout.entries {
          items.push([
            WText("["),
            WJson(key),
            WText(","),
            value_task,
            WText("]"),
          ])
        } else {
          guard key is String(text) else {
            self.fail(
              AdapterFailure,
              field_path(path, field.0),
              shape.id,
              "An object dictionary key must be written as a string.",
            )
            return
          }
          items.push([WText(json_string(text) + ":"), value_task])
        }
      }
      self.sequence(
        joined(
          if layout.entries {
            "["
          } else {
            "{"
          },
          items,
          if layout.entries {
            "]"
          } else {
            "}"
          },
        ),
      )
    }
    ObjectStructure | TupleStructure(_) => {
      if value is Null {
        self.tasks.push(WText("null"))
        return
      }
      match self.choose(shape.forms, None, value, shape, path, shape.id) {
        Err(_) => return
        Ok(Some(form)) => {
          self.form(value, form.binding, shape, None, path, depth)
          return
        }
        Ok(None) => ()
      }
      match shape.layout {
        TupleStructure(t) =>
          match
            self.positions(
              value,
              shape,
              t.fixed,
              t.rest,
              t.optional,
              path,
              depth,
            ) {
            Some(items) => self.sequence(joined("[", items, "]"))
            None => ()
          }
        _ =>
          self.sequence(
            joined("{", self.object_fields(value, shape, path, depth), "}"),
          )
      }
    }
    UnionShape(layout) => {
      guard value is Union(name, payload) && shape.member_index(name) is Some(i) else {
        self.fail(
          UnknownTag,
          path,
          shape.id,
          "I expected a declared union member.",
        )
        return
      }
      let m = shape.members[i]
      let target = self.contract.shapes.get(m.target).unwrap()
      let payload_path = field_path(path, name)
      match self.choose(shape.forms, Some(i), payload, target, path, shape.id) {
        Err(_) => return
        Ok(Some(form)) => {
          self.form(
            payload,
            form.binding,
            target,
            m.adapter,
            payload_path,
            depth,
          )
          return
        }
        Ok(None) => ()
      }
      let tag = json_string(m.tag.to_string())
      let payload_task = WValue(
        payload,
        { shape: m.target, adapter: m.adapter, },
        payload_path,
        depth + 1,
      )
      match layout {
        External =>
          self.sequence([WText("{" + tag + ":"), payload_task, WText("}")])
        Internal(tag=field) => {
          let items = [[WText(json_string(field.to_string()) + ":" + tag)]] +
            self.object_fields(payload, target, payload_path, depth)
          self.sequence(joined("{", items, "}"))
        }
        Adjacent(tag=field, content~) =>
          if unit_like(target) {
            self.tasks.push(
              WText("{" + json_string(field.to_string()) + ":" + tag + "}"),
            )
          } else {
            self.sequence([
              WText(
                "{" +
                json_string(field.to_string()) +
                ":" +
                tag +
                "," +
                json_string(content.to_string()) +
                ":",
              ),
              payload_task,
              WText("}"),
            ])
          }
        TagArray(tag_only_unit~) =>
          if tag_only_unit && unit_like(target) {
            self.tasks.push(WText("[" + tag + "]"))
          } else {
            match target.layout {
              TupleStructure(t) =>
                match
                  self.positions(
                    payload,
                    target,
                    t.fixed,
                    t.rest,
                    t.optional,
                    payload_path,
                    depth,
                  ) {
                  Some(items) =>
                    self.sequence(joined("[", [[WText(tag)]] + items, "]"))
                  None => ()
                }
              _ =>
                self.sequence([WText("[" + tag + ","), payload_task, WText("]")])
            }
          }
        Untagged(_) => self.tasks.push(payload_task)
      }
    }
  }
}

///|
/// The JSON of a scalar or document value, with exact numbers.
fn logical_json(value : LogicalValue) -> Json {
  let tasks : Array[(LogicalValue, Bool)] = [(value, false)]
  let out : Array[Json] = []
  while tasks.pop() is Some((v, built)) {
    match v {
      Null => out.push(Json::null())
      Boolean(b) => out.push(Json::boolean(b))
      Number(n) => out.push(number_json(n))
      String(s) => out.push(Json::string(s))
      List(items) =>
        if built {
          let xs : Array[Json] = []
          for _ in 0..<items.length() {
            xs.push(out.pop().unwrap())
          }
          xs.rev_in_place()
          out.push(Json::array(xs))
        } else {
          tasks.push((v, true))
          for i = items.length() - 1; i >= 0; i = i - 1 {
            tasks.push((items[i], false))
          }
        }
      Union(name, payload) =>
        if built {
          let object : Map[String, Json] = Map([])
          object[name] = out.pop().unwrap()
          out.push(Json::object(object))
        } else {
          tasks.push((v, true))
          tasks.push((payload, false))
        }
      Structure(fields) | Map(fields) | Object(fields) =>
        if built {
          let xs : Array[Json] = []
          for _ in 0..<fields.length() {
            xs.push(out.pop().unwrap())
          }
          xs.rev_in_place()
          let object : Map[String, Json] = Map([])
          for i, f in fields {
            object[f.0] = xs[i]
          }
          out.push(Json::object(object))
        } else {
          tasks.push((v, true))
          for i = fields.length() - 1; i >= 0; i = i - 1 {
            tasks.push((fields[i].1, false))
          }
        }
    }
  }
  out.pop().unwrap()
}

///|
fn write_json_value(out : StringBuilder, value : Json) -> Unit {
  let tasks : Array[Result[Json, String]] = [Ok(value)]
  while tasks.pop() is Some(task) {
    match task {
      Err(text) => out.write_string(text)
      Ok(Null) => out.write_string("null")
      Ok(True) => out.write_string("true")
      Ok(False) => out.write_string("false")
      Ok(Number(n, repr~)) =>
        out.write_string(
          match repr {
            Some(text) => text
            None => n.to_string()
          },
        )
      Ok(String(s)) => write_string(out, s)
      Ok(Array(items)) => {
        tasks.push(Err("]"))
        for i = items.length() - 1; i >= 0; i = i - 1 {
          tasks.push(Ok(items[i]))
          if i > 0 {
            tasks.push(Err(","))
          }
        }
        tasks.push(Err("["))
      }
      Ok(Object(fields)) => {
        let names = fields.keys().to_array()
        tasks.push(Err("}"))
        for i = names.length() - 1; i >= 0; i = i - 1 {
          tasks.push(Ok(fields.get(names[i]).unwrap()))
          tasks.push(
            Err((if i > 0 { "," } else { "" }) + json_string(names[i]) + ":"),
          )
        }
        tasks.push(Err("{"))
      }
    }
  }
}

///|
/// Write a normalized value. Returns no text when any part cannot be written.
fn write_value(
  contract : @contract.WireContract,
  adapters : AdapterRegistry,
  request : Request,
  value : LogicalValue,
) -> String? {
  let writer : Writer = {
    contract,
    adapters,
    request,
    tasks: [
      WValue(
        value,
        { shape: contract.root, adapter: None, },
        @validation.InstancePath::root(),
        0,
      ),
    ],
    out: StringBuilder(),
  }
  while writer.tasks.pop() is Some(task) {
    if !request.complete || !request.findings.is_empty() {
      return None
    }
    match task {
      WText(text) => writer.out.write_string(text)
      WJson(json) => {
        if !request.charge(@validation.InstancePath::root(), contract.root) {
          return None
        }
        write_json_value(writer.out, json)
      }
      WValue(value, target, path, depth) =>
        writer.value(value, target, path, depth)
    }
  }
  if !request.complete || !request.findings.is_empty() {
    return None
  }
  Some(writer.out.to_string())
}
