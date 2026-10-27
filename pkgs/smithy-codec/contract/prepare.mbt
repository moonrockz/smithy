///|
fn[T] either(first : T?, second : T?) -> T? {
  match first {
    Some(_) => first
    None => second
  }
}

///|
fn data_shape(shape : @smithy.Shape) -> Bool {
  match shape.body {
    Operation(..) | Service(..) | Resource(..) => false
    _ => shape.trait_value("smithy.api#mixin") is None
  }
}

///|
fn shape_kind(body : @smithy.ShapeBody) -> ShapeKind? {
  match body {
    Simple(t) => Some(SimpleKind(t))
    List(_) => Some(ListKind)
    Map(..) => Some(MapKind)
    Structure(_) => Some(StructureKind)
    Union(_) => Some(UnionKind)
    Enum(_) => Some(EnumKind)
    IntEnum(_) => Some(IntEnumKind)
    _ => None
  }
}

///|
fn wire_name(
  owner : @smithy.ShapeId,
  text : String,
) -> WireName raise ContractError {
  WireName::parse(text) catch {
    InvalidIdentity(_, message) => raise InvalidDeclaration(owner, message)
  }
}

///|
fn adapter_id(
  owner : @smithy.ShapeId,
  text : String,
) -> AdapterId raise ContractError {
  AdapterId::parse(text) catch {
    InvalidIdentity(_, message) => raise InvalidDeclaration(owner, message)
  }
}

///|
fn annotation(shape : @smithy.Shape, id : String) -> Bool {
  shape.trait_value(id) is Some(_)
}

///|
/// The first value at the highest precedence, refusing a disagreement at the same precedence.
fn[T : Eq] pick(
  owner : @smithy.ShapeId,
  what : String,
  selected : T?,
  defaults : T?,
  base : Array[T],
) -> T? raise ContractError {
  if selected is Some(_) {
    return selected
  }
  if defaults is Some(_) {
    return defaults
  }
  match base {
    [] => None
    [first, .. rest] => {
      for other in rest {
        if other != first {
          raise ConflictingDeclaration(
            owner,
            "I found conflicting base declarations of the \{what}.",
          )
        }
      }
      Some(first)
    }
  }
}

///|
priv struct Draft {
  id : @smithy.ShapeId
  kind : ShapeKind
  members : Array[MemberContract]
  layout : ShapeLayout
  accepts : Array[UnionLayout]
  sparse : Bool
  forms : Array[RawForm]
}

///|
fn adapter_signature(
  owner : @smithy.ShapeId,
  adapters : Map[AdapterId, AdapterSignature],
  id : AdapterId,
) -> AdapterSignature raise ContractError {
  match adapters.get(id) {
    Some(signature) => signature
    None => raise MissingAdapter(owner, id)
  }
}

///|
fn scalar_output(kind : ShapeKind, timestamp_text : Bool) -> JsonKind? {
  match kind {
    SimpleKind(String | Blob) | EnumKind => Some(StringKind)
    SimpleKind(Timestamp) =>
      Some(if timestamp_text { StringKind } else { NumberKind })
    SimpleKind(Boolean) => Some(BooleanKind)
    SimpleKind(Document) => None
    SimpleKind(_) | IntEnumKind => Some(NumberKind)
    _ => None
  }
}

///|
fn timestamp_text(shape : @smithy.Shape, member_shape : @smithy.Shape?) -> Bool {
  let format = match
    member_shape.bind(m => m.trait_value("smithy.api#timestampFormat")) {
    Some(value) => Some(value)
    None => shape.trait_value("smithy.api#timestampFormat")
  }
  match format {
    Some(String("date-time" | "http-date")) => true
    _ => false
  }
}

///|
/// Prepare the detached wire contract of `root` under `profile`, or under the base rules when no profile
/// is selected. `adapters` declares the scalar adapters that the host has registered.
pub fn WireContract::prepare(
  model : @smithy.Model,
  root : @smithy.ShapeId,
  profile~ : ProfileId? = None,
  adapters~ : Array[AdapterSignature] = [],
  max_shapes~ : Int32 = 100000,
) -> WireContract raise ContractError {
  guard model.shapes.get(root) is Some(root_shape) &&
    data_shape(root_shape) &&
    !(root_shape.body is Member(_)) else {
    raise InvalidTarget(
      root, "I expected an existing data shape, not a member, as the codec root.",
    )
  }
  let declared = declared_profiles(model)
  let declaration = match profile {
    None => None
    Some(id) =>
      match declared.get(id) {
        Some(d) => Some(d)
        None => raise UnknownProfile(id)
      }
  }
  let rule_set = declaration.map(d => d.rule_set.to_string())
  let defaults = match declaration {
    None => empty_rule()
    Some(d) =>
      if d.rule_set == d.id {
        d.defaults
      } else {
        declared.get(d.rule_set).unwrap().defaults
      }
  }
  let catalog : Map[AdapterId, AdapterSignature] = Map([])
  for signature in adapters {
    catalog[signature.id] = signature
  }
  let drafts : Map[@smithy.ShapeId, Draft] = Map([])
  let order : Array[@smithy.ShapeId] = []
  let stack = [root]
  while stack.pop() is Some(id) {
    if drafts.contains(id) {
      continue
    }
    if drafts.length() >= max_shapes {
      raise PreparationLimit(
        id,
        "I reached the preparation limit of \{max_shapes} shapes.",
      )
    }
    guard model.shapes.get(id) is Some(shape) &&
      data_shape(shape) &&
      shape_kind(shape.body) is Some(kind) else {
      raise InvalidDeclaration(
        id, "I expected a reachable data shape, but found a missing or nondata target.",
      )
    }
    let encoding = shape_encoding(shape, declared)
    let selected = rule_set
      .bind(name => encoding.profiles.get(name))
      .unwrap_or(empty_rule())
    let base = encoding.base.unwrap_or(empty_rule())
    let shape_rules = [selected, base]
    for rule in shape_rules {
      if rule.name is Some(_) ||
        rule.tag is Some(_) ||
        rule.aliases is Some(_) ||
        rule.absent is Some(_) {
        raise InvalidDeclaration(
          id, "Member names, tags, aliases and absence policies belong on members, not on the shape.",
        )
      }
      if rule.union_ is Some(_) && kind != UnionKind {
        raise InvalidDeclaration(id, "A union rule needs a union shape.")
      }
      if rule.tuple is Some(_) && kind != StructureKind {
        raise InvalidDeclaration(id, "A tuple rule needs a structure shape.")
      }
      if rule.dictionary is Some(_) && kind != MapKind {
        raise InvalidDeclaration(id, "A dictionary rule needs a map shape.")
      }
      if rule.forms is Some(_) && !(kind is (UnionKind | StructureKind)) {
        raise InvalidDeclaration(id, "Forms need a union or structure shape.")
      }
      if rule.adapter is Some(_) &&
        !(kind is (SimpleKind(_) | EnumKind | IntEnumKind)) {
        raise InvalidDeclaration(id, "A scalar adapter needs a simple shape.")
      }
    }
    if annotation(shape, untagged_trait) && kind != UnionKind {
      raise InvalidDeclaration(id, "The untagged trait needs a union shape.")
    }
    // Members.
    let member_ids = match shape.body {
      Structure(ids) | Union(ids) => ids.copy()
      List(member_id) => [member_id]
      Map(key~, value~) => [key, value]
      _ => []
    }
    let members : Array[MemberContract] = []
    for member_id in member_ids {
      guard member_id.root() == id &&
        member_id.member_name() is Some(name) &&
        model.shapes.get(member_id) is Some(member_shape) &&
        member_shape.body is Member(target~) &&
        model.shapes.get(target) is Some(target_shape) &&
        data_shape(target_shape) &&
        !(target_shape.body is Member(_)) else {
        raise InvalidDeclaration(
          id, "I expected declared members that target existing data shapes.",
        )
      }
      let member_encoding = shape_encoding(member_shape, declared)
      let member_selected = rule_set
        .bind(name => member_encoding.profiles.get(name))
        .unwrap_or(empty_rule())
      let member_base = member_encoding.base.unwrap_or(empty_rule())
      for rule in [member_selected, member_base] {
        if rule.union_ is Some(_) ||
          rule.tuple is Some(_) ||
          rule.dictionary is Some(_) ||
          rule.forms is Some(_) {
          raise InvalidDeclaration(
            member_id, "Union, tuple, dictionary and form rules belong on shapes, not on members.",
          )
        }
      }
      let json_name = match member_shape.trait_value("smithy.api#jsonName") {
        None => []
        Some(String(text)) => [text]
        Some(_) =>
          raise InvalidDeclaration(
            member_id, "I expected a string JSON member name.",
          )
      }
      let base_names = match member_base.name {
        None => json_name
        Some(text) => json_name + [text]
      }
      let wire = wire_name(
        member_id,
        pick(member_id, "member name", member_selected.name, None, base_names).unwrap_or(
          name,
        ),
      )
      let tag = match
        pick(
          member_id,
          "member tag",
          member_selected.tag,
          None,
          member_base.tag.map(t => [t]).unwrap_or([]),
        ) {
        Some(text) => wire_name(member_id, text)
        None => wire
      }
      let aliases = either(member_selected.aliases, member_base.aliases)
        .unwrap_or([])
        .map(text => wire_name(member_id, text))
      let adapter = match
        pick(
          member_id,
          "member adapter",
          member_selected.adapter,
          None,
          member_base.adapter.map(t => [t]).unwrap_or([]),
        ) {
        Some(text) => Some(adapter_id(member_id, text))
        None => None
      }
      let target_kind = shape_kind(target_shape.body).unwrap()
      if adapter is Some(adapter) {
        guard target_kind is (SimpleKind(_) | EnumKind | IntEnumKind) &&
          !(target_kind is SimpleKind(Document)) else {
          raise InvalidDeclaration(
            member_id, "A scalar adapter needs a member that targets a simple shape.",
          )
        }
        let signature = adapter_signature(member_id, catalog, adapter)
        guard scalar_output(
            target_kind,
            timestamp_text(target_shape, Some(member_shape)),
          ) ==
          Some(signature.output) else {
          raise InvalidDeclaration(
            member_id,
            "Adapter \{adapter} produces a \{signature.output} value, which the target cannot hold.",
          )
        }
      }
      let empty_as_absent = annotation(member_shape, empty_as_absent_trait)
      let required = annotation(member_shape, "smithy.api#required")
      let null_when_absent = match
        either(member_selected.absent, member_base.absent) {
        None | Some("omit") => false
        Some("null") => true
        Some(other) =>
          raise UnsupportedDeclaration(
            member_id,
            "I do not implement the absence policy \{other.escape()}.",
          )
      }
      if null_when_absent && (required || kind != StructureKind) {
        raise InvalidDeclaration(
          member_id, "The null absence policy needs an optional structure member.",
        )
      }
      if empty_as_absent &&
        (required || !(target_kind is (StructureKind | ListKind | MapKind))) {
        raise InvalidDeclaration(
          member_id, "emptyAsAbsent needs an optional member that targets a structure, list or map.",
        )
      }
      members.push({
        name,
        member_id,
        target,
        required,
        wire,
        aliases,
        tag,
        adapter,
        empty_as_absent,
        null_when_absent,
        flatten: member_selected.flatten || member_base.flatten,
      })
      stack.push(target)
    }
    // Wire names are unique within an object layout.
    if kind is (StructureKind | UnionKind) {
      let names : Map[String, String] = Map([])
      for m in members {
        let spellings = [m.wire] + m.aliases
        let seen = if kind == UnionKind {
          [m.tag] + m.aliases
        } else {
          spellings
        }
        for spelling in seen {
          let text = spelling.to_string()
          if names.get(text) is Some(other) {
            raise InvalidDeclaration(
              id,
              "Members \{other} and \{m.name} use the same wire name \{text.escape()}.",
            )
          }
          names[text] = m.name
        }
      }
    }
    let sparse = annotation(shape, "smithy.api#sparse")
    let accepts : Array[UnionLayout] = []
    let layout = match kind {
      StructureKind =>
        match either(selected.tuple, base.tuple) {
          None => ObjectStructure
          Some(t) => TupleStructure(tuple_layout(id, members, t))
        }
      UnionKind => {
        let base_unions : Array[RawUnion] = []
        if base.union_ is Some(u) {
          base_unions.push(u)
        }
        if annotation(shape, untagged_trait) {
          base_unions.push({
            style: "untagged",
            tag: None,
            content: None,
            unit: None,
            accept: [],
          })
        }
        let rule = match selected.union_ {
          Some(u) => Some(u)
          None =>
            match defaults.union_ {
              Some(u) => Some(u)
              None =>
                match base_unions {
                  [] => None
                  [first, .. rest] => {
                    for other in rest {
                      if other.style != first.style {
                        raise ConflictingDeclaration(
                          id,
                          "I found conflicting base union styles \{first.style} and \{other.style}.",
                        )
                      }
                    }
                    Some(first)
                  }
                }
            }
        }
        match rule {
          Some(r) =>
            for alternative in r.accept {
              let layout = union_layout(id, members, Some(alternative))
              guard layout
                is (External | Internal(..) | Adjacent(..) | TagArray(..)) else {
                raise InvalidDeclaration(
                  id, "An accepted union layout must be external, internal, adjacent or a tag array.",
                )
              }
              if layout is TagArray(..) &&
                (
                  r.style == "tagArray" ||
                  accepts.iter().any(a => a is TagArray(..))
                ) {
                raise InvalidDeclaration(
                  id, "A union can read only one tag-array layout.",
                )
              }
              accepts.push(layout)
            }
          None => ()
        }
        UnionShape(union_layout(id, members, rule))
      }
      ListKind => ListShape
      MapKind => {
        let rule = either(
          selected.dictionary,
          either(defaults.dictionary, base.dictionary),
        )
        Dictionary(dictionary_layout(id, members, rule, catalog))
      }
      _ => {
        let adapter = match
          pick(
            id,
            "scalar adapter",
            selected.adapter,
            None,
            base.adapter.map(t => [t]).unwrap_or([]),
          ) {
          Some(text) => Some(adapter_id(id, text))
          None => None
        }
        if adapter is Some(adapter) {
          let signature = adapter_signature(id, catalog, adapter)
          guard scalar_output(kind, timestamp_text(shape, None)) ==
            Some(signature.output) else {
            raise InvalidDeclaration(
              id,
              "Adapter \{adapter} produces a \{signature.output} value, which the shape cannot hold.",
            )
          }
        }
        Scalar(adapter)
      }
    }
    drafts[id] = {
      id,
      kind,
      members,
      layout,
      accepts,
      sparse,
      forms: either(selected.forms, base.forms).unwrap_or([]),
    }
    order.push(id)
  }
  // Second pass: decisions that read other shapes.
  let shapes : Map[@smithy.ShapeId, ShapeContract] = Map([])
  for id in order {
    let draft = drafts.get(id).unwrap()
    for alternative in draft.accepts {
      if alternative is Internal(tag~) {
        check_internal(id, draft, drafts, model, tag)
      }
    }
    if draft.kind == StructureKind {
      check_flatten(draft, drafts)
    }
    let layout = match draft.layout {
      UnionShape(Untagged(_)) =>
        UnionShape(Untagged(untagged_kinds(draft, drafts, catalog, model)))
      UnionShape(Internal(tag~)) => {
        check_internal(id, draft, drafts, model, tag)
        draft.layout
      }
      TupleStructure(t) => {
        if t.rest is Some(rest) {
          guard drafts.get(draft.members[rest].target) is Some(target) &&
            target.kind == ListKind else {
            raise InvalidDeclaration(
              id,
              "The rest member \{draft.members[rest].name} needs a list target.",
            )
          }
        }
        draft.layout
      }
      other => other
    }
    let forms = prepare_forms(draft, layout, drafts, catalog, model)
    shapes[id] = {
      id,
      kind: draft.kind,
      members: draft.members,
      layout,
      accepts: draft.accepts,
      sparse: draft.sparse,
      forms,
    }
  }
  {
    root,
    profile,
    writer: declaration.map(d => d.writer).unwrap_or(Canonical),
    unknown_members: declaration
    .map(d => d.unknown_members)
    .unwrap_or(RejectUnknown),
    fingerprint: fingerprint(model, root, order),
    shapes,
  }
}

///|
fn is_unit(model : @smithy.Model, id : @smithy.ShapeId) -> Bool {
  match model.shapes.get(id) {
    Some(shape) =>
      shape.trait_value("smithy.api#unitType") is Some(_) ||
      (
        shape.body is Structure(ids) &&
        ids.is_empty() &&
        id.to_string() == "smithy.api#Unit"
      )
    None => false
  }
}

///|
fn tuple_layout(
  id : @smithy.ShapeId,
  members : Array[MemberContract],
  rule : RawTuple,
) -> TupleLayout raise ContractError {
  let index = fn(name : String) raise ContractError {
    for i, m in members {
      if m.name == name {
        return i
      }
    }
    raise InvalidDeclaration(
      id,
      "The tuple names \{name.escape()}, which is not a member.",
    )
  }
  let fixed : Array[Int32] = []
  let used : Set[Int32] = Set([])
  for name in rule.members {
    let i = index(name)
    if used.contains(i) {
      raise InvalidDeclaration(
        id,
        "The tuple lists member \{name} at two positions.",
      )
    }
    used.add(i)
    fixed.push(i)
  }
  let rest = match rule.rest {
    None => None
    Some(name) => {
      let i = index(name)
      if used.contains(i) {
        raise InvalidDeclaration(
          id,
          "The rest member \{name} also has a fixed position.",
        )
      }
      used.add(i)
      Some(i)
    }
  }
  for i, m in members {
    if !used.contains(i) {
      raise InvalidDeclaration(id, "Member \{m.name} has no tuple position.")
    }
  }
  let optional = match rule.optional {
    None => None
    Some("omit") => Some(OmitTail)
    Some("null") => Some(NullTail)
    Some(other) =>
      raise UnsupportedDeclaration(
        id,
        "I do not implement the optional-position policy \{other.escape()}.",
      )
  }
  let mut seen_optional = false
  for i in fixed {
    let m = members[i]
    if !m.required {
      if optional is None {
        raise InvalidDeclaration(
          id,
          "Optional member \{m.name} has a position, so the tuple needs an optional policy.",
        )
      }
      seen_optional = true
    } else if seen_optional && optional == Some(OmitTail) {
      raise InvalidDeclaration(
        id,
        "Required member \{m.name} follows an optional position, which leaves a hole.",
      )
    }
  }
  if rest is Some(_) && seen_optional && optional == Some(OmitTail) {
    raise InvalidDeclaration(
      id, "A rest list cannot follow omitted optional positions.",
    )
  }
  { fixed, rest, optional, }
}

///|
fn union_layout(
  id : @smithy.ShapeId,
  members : Array[MemberContract],
  rule : RawUnion?,
) -> UnionLayout raise ContractError {
  guard rule is Some(rule) else { return External }
  let check_unused = fn(names : Array[(String, String?)]) raise ContractError {
    for entry in names {
      if entry.1 is Some(_) {
        raise InvalidDeclaration(
          id,
          "The \{rule.style} union style has no \{entry.0} setting.",
        )
      }
    }
  }
  match rule.style {
    "external" => {
      check_unused([
        ("tag", rule.tag),
        ("content", rule.content),
        ("unit", rule.unit),
      ])
      External
    }
    "internal" => {
      check_unused([("content", rule.content), ("unit", rule.unit)])
      guard rule.tag is Some(tag) else {
        raise InvalidDeclaration(
          id, "An internally tagged union needs a tag field.",
        )
      }
      Internal(tag=wire_name(id, tag))
    }
    "adjacent" => {
      check_unused([("unit", rule.unit)])
      guard rule.tag is Some(tag) && rule.content is Some(content) else {
        raise InvalidDeclaration(
          id, "An adjacently tagged union needs tag and content fields.",
        )
      }
      guard tag != content else {
        raise InvalidDeclaration(
          id, "An adjacently tagged union needs distinct tag and content fields.",
        )
      }
      Adjacent(tag=wire_name(id, tag), content=wire_name(id, content))
    }
    "tagArray" => {
      check_unused([("tag", rule.tag), ("content", rule.content)])
      let tag_only_unit = match rule.unit {
        None | Some("tagOnly") => true
        Some("slot") => false
        Some(other) =>
          raise UnsupportedDeclaration(
            id,
            "I do not implement the tag-array unit mode \{other.escape()}.",
          )
      }
      TagArray(tag_only_unit~)
    }
    "untagged" => {
      check_unused([
        ("tag", rule.tag),
        ("content", rule.content),
        ("unit", rule.unit),
      ])
      ignore(members)
      Untagged([])
    }
    other =>
      raise UnsupportedDeclaration(
        id,
        "I do not implement the union style \{other.escape()}.",
      )
  }
}

///|
fn dictionary_layout(
  id : @smithy.ShapeId,
  members : Array[MemberContract],
  rule : RawDictionary?,
  catalog : Map[AdapterId, AdapterSignature],
) -> DictionaryLayout raise ContractError {
  if members.length() == 2 && members[0].adapter is Some(_) {
    raise InvalidDeclaration(
      id, "Declare a map key adapter with the dictionary rule, not on the key member.",
    )
  }
  guard rule is Some(rule) else {
    return {
      entries: false,
      accept_other: false,
      key_adapter: None,
      order: LexicalKeys,
    }
  }
  let entries = match rule.layout {
    "object" => false
    "entries" => true
    other =>
      raise UnsupportedDeclaration(
        id,
        "I do not implement the dictionary layout \{other.escape()}.",
      )
  }
  let accept_other = match rule.accept {
    [] => false
    ["object"] if entries => true
    ["entries"] if !entries => true
    _ =>
      raise InvalidDeclaration(
        id, "A dictionary can accept only the other layout.",
      )
  }
  let key_adapter = rule.key.map(text => adapter_id(id, text))
  let order = match rule.order {
    None | Some("key") => LexicalKeys
    Some("adapter") => AdapterKeys
    Some("preserve") => PreservedKeys
    Some(other) =>
      raise UnsupportedDeclaration(
        id,
        "I do not implement the dictionary order \{other.escape()}.",
      )
  }
  match key_adapter {
    Some(adapter) => {
      let signature = adapter_signature(id, catalog, adapter)
      guard signature.output == StringKind else {
        raise InvalidDeclaration(
          id,
          "Key adapter \{adapter} must produce a string key.",
        )
      }
      if (!entries || accept_other) && !signature.inputs.contains(StringKind) {
        raise InvalidDeclaration(
          id,
          "Key adapter \{adapter} must read strings in an object dictionary.",
        )
      }
      if order == AdapterKeys && !signature.orders_keys {
        raise InvalidDeclaration(id, "Adapter \{adapter} does not order keys.")
      }
    }
    None =>
      if order == AdapterKeys {
        raise InvalidDeclaration(id, "Adapter key order needs a key adapter.")
      }
  }
  { entries, accept_other, key_adapter, order, }
}

///|
/// The JSON kinds that the reader of a shape accepts, through its layout and its forms.
fn accepted_kinds(
  target : @smithy.ShapeId,
  member_id : @smithy.ShapeId?,
  adapter : AdapterId?,
  drafts : Map[@smithy.ShapeId, Draft],
  catalog : Map[AdapterId, AdapterSignature],
  model : @smithy.Model,
  visiting : Set[@smithy.ShapeId],
) -> Array[JsonKind] raise ContractError {
  let draft = drafts.get(target).unwrap()
  let adapter = match adapter {
    Some(a) => Some(a)
    None =>
      match draft.layout {
        Scalar(a) => a
        _ => None
      }
  }
  if adapter is Some(adapter) {
    return adapter_signature(target, catalog, adapter).inputs.copy()
  }
  let out : Array[JsonKind] = []
  let add = fn(kind : JsonKind) { if !out.contains(kind) { out.push(kind) } }
  for form in draft.forms {
    match JsonKind::parse(form.kind) {
      Some(kind) => add(kind)
      None => ()
    }
  }
  match draft.layout {
    ObjectStructure => add(ObjectKind)
    TupleStructure(_) | ListShape => add(ArrayKind)
    Dictionary(d) => {
      add(if d.entries { ArrayKind } else { ObjectKind })
      if d.accept_other {
        add(if d.entries { ObjectKind } else { ArrayKind })
      }
    }
    UnionShape(External | Internal(..) | Adjacent(..)) => add(ObjectKind)
    UnionShape(TagArray(..)) => add(ArrayKind)
    UnionShape(Untagged(_)) => {
      if visiting.contains(target) {
        raise InvalidDeclaration(
          target, "An untagged union cannot contain itself without a tag.",
        )
      }
      visiting.add(target)
      for m in draft.members {
        for
          kind in accepted_kinds(
            m.target,
            Some(m.member_id),
            m.adapter,
            drafts,
            catalog,
            model,
            visiting,
          ) {
          add(kind)
        }
      }
      visiting.remove(target)
    }
    Scalar(_) =>
      match draft.kind {
        SimpleKind(Document) => {
          add(NullKind)
          add(BooleanKind)
          add(NumberKind)
          add(StringKind)
          add(ArrayKind)
          add(ObjectKind)
        }
        kind =>
          match
            scalar_output(
              kind,
              timestamp_text(
                model.shapes.get(target).unwrap(),
                member_id.bind(m => model.shapes.get(m)),
              ),
            ) {
            Some(k) => add(k)
            None => ()
          }
      }
  }
  for alternative in draft.accepts {
    for kind in layout_kinds(UnionShape(alternative)) {
      add(kind)
    }
  }
  out
}

///|
fn untagged_kinds(
  draft : Draft,
  drafts : Map[@smithy.ShapeId, Draft],
  catalog : Map[AdapterId, AdapterSignature],
  model : @smithy.Model,
) -> Array[(JsonKind, Int32)] raise ContractError {
  let out : Array[(JsonKind, Int32)] = []
  for i, m in draft.members {
    if is_unit(model, m.target) {
      raise InvalidDeclaration(
        draft.id,
        "Untagged member \{m.name} has no value to select it.",
      )
    }
    let kinds = accepted_kinds(
      m.target,
      Some(m.member_id),
      m.adapter,
      drafts,
      catalog,
      model,
      Set([draft.id]),
    )
    for kind in kinds {
      for entry in out {
        if entry.0 == kind {
          raise InvalidDeclaration(
            draft.id,
            "Untagged members \{draft.members[entry.1].name} and \{m.name} both accept JSON \{kind} values.",
          )
        }
      }
      out.push((kind, i))
    }
  }
  out
}

///|
fn layout_kinds(layout : ShapeLayout) -> Array[JsonKind] {
  match layout {
    ObjectStructure | UnionShape(External | Internal(..) | Adjacent(..)) =>
      [ObjectKind]
    Dictionary(d) =>
      if d.accept_other {
        [ArrayKind, ObjectKind]
      } else {
        [if d.entries { ArrayKind } else { ObjectKind }]
      }
    TupleStructure(_) | ListShape | UnionShape(TagArray(..)) => [ArrayKind]
    UnionShape(Untagged(kinds)) => kinds.map(entry => entry.0)
    Scalar(_) => []
  }
}

///|
fn prepare_forms(
  draft : Draft,
  layout : ShapeLayout,
  drafts : Map[@smithy.ShapeId, Draft],
  catalog : Map[AdapterId, AdapterSignature],
  model : @smithy.Model,
) -> Array[Form] raise ContractError {
  let id = draft.id
  let out : Array[Form] = []
  for raw in draft.forms {
    guard JsonKind::parse(raw.kind) is Some(kind) else {
      raise UnsupportedDeclaration(
        id,
        "I do not implement the form reader kind \{raw.kind.escape()}.",
      )
    }
    let adapter = raw.adapter.map(text => adapter_id(id, text))
    if adapter is Some(a) {
      let signature = adapter_signature(id, catalog, a)
      guard signature.inputs.contains(kind) else {
        raise InvalidDeclaration(
          id,
          "Form guard adapter \{a} does not read \{kind} values.",
        )
      }
    }
    let field = raw.field.map(text => wire_name(id, text))
    let absent_field = raw.absent_field.map(text => wire_name(id, text))
    if (field is Some(_) || absent_field is Some(_)) && kind != ObjectKind {
      raise InvalidDeclaration(id, "A field marker needs an object form.")
    }
    // The members that the form binds belong to the payload of a union member, or to the structure.
    let (selected_member, payload) = match draft.kind {
      UnionKind => {
        guard raw.union_member is Some(name) &&
          draft.members.search_by(m => m.name == name) is Some(i) else {
          raise InvalidDeclaration(id, "A union form needs a union member.")
        }
        (Some(i), drafts.get(draft.members[i].target).unwrap())
      }
      _ => {
        if raw.union_member is Some(_) {
          raise InvalidDeclaration(
            id, "A structure form selects no union member.",
          )
        }
        (None, draft)
      }
    }
    let index = fn(name : String) raise ContractError {
      guard payload.kind == StructureKind &&
        payload.members.search_by(m => m.name == name) is Some(i) else {
        raise InvalidDeclaration(
          id,
          "The form names \{name.escape()}, which is not a payload member.",
        )
      }
      i
    }
    let binding = match (raw.bind, raw.positions) {
      (Some(_), Some(_)) =>
        raise InvalidDeclaration(
          id, "A form binds either one member or positions.",
        )
      (Some(name), None) => {
        if raw.rest is Some(_) {
          raise InvalidDeclaration(id, "A rest member needs positions.")
        }
        let i = index(name)
        let accepted = accepted_kinds(
          payload.members[i].target,
          Some(payload.members[i].member_id),
          payload.members[i].adapter,
          drafts,
          catalog,
          model,
          Set([]),
        )
        guard accepted.contains(kind) else {
          raise InvalidDeclaration(
            id,
            "Member \{name} does not accept the form's \{kind} values.",
          )
        }
        Whole(i)
      }
      (None, Some(names)) => {
        guard kind == ArrayKind else {
          raise InvalidDeclaration(
            id, "A positional form needs an array reader.",
          )
        }
        let fixed : Array[Int32] = []
        for name in names {
          let i = index(name)
          if fixed.contains(i) {
            raise InvalidDeclaration(id, "The form lists member \{name} twice.")
          }
          fixed.push(i)
        }
        let rest = match raw.rest {
          None => None
          Some(name) => {
            let i = index(name)
            guard !fixed.contains(i) &&
              drafts.get(payload.members[i].target).unwrap().kind == ListKind else {
              raise InvalidDeclaration(
                id,
                "The form's rest member \{name} needs a list target and no fixed position.",
              )
            }
            Some(i)
          }
        }
        Positional(fixed~, rest~)
      }
      (None, None) =>
        if selected_member is Some(_) {
          let accepted = accepted_kinds(
            payload.id,
            Some(draft.members[selected_member.unwrap()].member_id),
            draft.members[selected_member.unwrap()].adapter,
            drafts,
            catalog,
            model,
            Set([]),
          )
          guard accepted.contains(kind) else {
            raise InvalidDeclaration(
              id,
              "The payload does not accept the form's \{kind} values.",
            )
          }
          Whole(-1)
        } else {
          raise InvalidDeclaration(
            id, "A form needs a bound member or positions.",
          )
        }
    }
    let bound : Array[Int32] = match binding {
      Whole(i) =>
        if i >= 0 {
          [i]
        } else {
          Array::makei(payload.members.length(), i => i)
        }
      Positional(fixed~, rest~) =>
        match rest {
          Some(r) => fixed + [r]
          None => fixed
        }
    }
    // A reader leaves unbound members absent, so they must be optional.
    if payload.kind == StructureKind {
      for i, m in payload.members {
        if m.required && !bound.contains(i) {
          raise InvalidDeclaration(
            id,
            "The form leaves required member \{m.name} without a value.",
          )
        }
      }
    }
    let writer = match raw.write {
      None => None
      Some((empty, present)) => {
        let empty = empty.map(index)
        let present = present.map(index)
        if payload.kind == StructureKind {
          for i, m in payload.members {
            if !bound.contains(i) && !empty.contains(i) {
              raise InvalidDeclaration(
                id,
                "The form's writer would drop member \{m.name}; list it as empty.",
              )
            }
          }
        }
        Some({ empty, present, })
      }
    }
    out.push({
      union_member: selected_member,
      reader: { kind, adapter, field, absent: absent_field, },
      binding,
      writer,
    })
  }
  // Reader rules must not overlap without a guard that can tell them apart.
  let guarded = fn(form : Form) {
    form.reader.adapter is Some(_) ||
    form.reader.field is Some(_) ||
    form.reader.absent is Some(_)
  }
  for i, form in out {
    if (layout_kinds(layout) +
      draft.accepts.map(a => layout_kinds(UnionShape(a))).flatten()).contains(
        form.reader.kind,
      ) &&
      !guarded(form) {
      raise InvalidDeclaration(
        id,
        "A \{form.reader.kind} form overlaps the shape's own \{form.reader.kind} layout without a guard.",
      )
    }
    for j in 0..<i {
      let other = out[j]
      if other.reader.kind == form.reader.kind &&
        (
          !guarded(form) ||
          !guarded(other) ||
          (
            other.reader.adapter == form.reader.adapter &&
            other.reader.field == form.reader.field &&
            other.reader.absent == form.reader.absent
          )
        ) {
        raise InvalidDeclaration(
          id,
          "Two \{form.reader.kind} forms overlap without guards that tell them apart.",
        )
      }
    }
  }
  out
}

///|
fn check_internal(
  id : @smithy.ShapeId,
  draft : Draft,
  drafts : Map[@smithy.ShapeId, Draft],
  model : @smithy.Model,
  tag : WireName,
) -> Unit raise ContractError {
  for m in draft.members {
    let target = drafts.get(m.target).unwrap()
    if is_unit(model, m.target) {
      continue
    }
    guard target.layout is ObjectStructure else {
      raise InvalidDeclaration(
        id,
        "Internally tagged member \{m.name} needs an object structure payload.",
      )
    }
    for field in target.members {
      if field.wire == tag || field.aliases.contains(tag) {
        raise InvalidDeclaration(
          id,
          "The discriminator \{tag} collides with field \{field.name} of member \{m.name}.",
        )
      }
    }
  }
}

///|
/// A flattened member reads the fields that no sibling claims as one external union.
fn check_flatten(
  draft : Draft,
  drafts : Map[@smithy.ShapeId, Draft],
) -> Unit raise ContractError {
  let flattened = draft.members.filter(m => m.flatten)
  if flattened.is_empty() {
    return
  }
  guard flattened.length() == 1 && draft.layout is ObjectStructure else {
    raise InvalidDeclaration(
      draft.id,
      "An object structure can flatten at most one member.",
    )
  }
  let m = flattened[0]
  let target = drafts.get(m.target).unwrap()
  guard target.layout is UnionShape(External) && target.forms.is_empty() else {
    raise InvalidDeclaration(
      draft.id,
      "Flattened member \{m.name} needs an external union without forms.",
    )
  }
  for alternative in target.members {
    for tag in [alternative.tag] + alternative.aliases {
      for sibling in draft.members {
        if !sibling.flatten &&
          (sibling.wire == tag || sibling.aliases.contains(tag)) {
          raise InvalidDeclaration(
            draft.id,
            "Flattened tag \{tag} collides with member \{sibling.name}.",
          )
        }
      }
    }
  }
}
