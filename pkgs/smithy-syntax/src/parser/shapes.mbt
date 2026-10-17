///|
/// `Mixins = [SP] "with" [WS] "[" [WS] 1*(ShapeId [WS]) "]"`. `[SP]`, not
/// `[WS]` or `[BR]`: right after a top-level shape's name (or its
/// `ForResource`), `with` on the next line is not a `Mixins` clause (the
/// shape has none), so the caller's `BR` check runs into it as a new
/// statement instead ("Unknown shape type: with", matching the reference).
/// `same_line` is `false` for an inline shape (`:=`), where `with` may
/// follow a trait that ends its own line (the reference's
/// `valid/inline-io.smithy`: `input :=\n  @sensitive\n  with [M] {...}`).
fn Parser::parse_mixins(
  self : Parser,
  same_line~ : Bool = true,
) -> @ast.Mixins? raise ParseError {
  guard self.at_keyword("with") && (!same_line || !self.has_br_before()) else {
    return None
  }
  let kw = self.expect_kind(Identifier, "`with`")
  self.require_v2("mixins", kw.span)
  ignore(self.expect_kind(LBracket, "`[` after `with`"))
  let ids : Array[@ast.Node[@ast.ShapeId]] = []
  while !self.at_kind(RBracket) {
    if self.at_end() {
      self.fail(
        "SM-PARSE-002",
        "UNFINISHED MIXINS",
        "I reached the end of the file inside the mixin list",
        self.here(),
        hint="Add the closing `]`.",
      )
    }
    ids.push(self.parse_shape_id())
  }
  let close = self.expect_kind(RBracket, "`]`")
  if ids.is_empty() {
    self.fail(
      "SM-PARSE-001",
      "EMPTY MIXINS",
      "`with [ ]` needs at least one mixin shape ID",
      kw.span.join(close.span),
      example="with [MyMixin]",
    )
  }
  Some({ ids: ids[:], span: kw.span.join(close.span), })
}

///|
/// `ForResource = SP "for" SP ShapeId`.
fn Parser::parse_for_resource(
  self : Parser,
) -> @ast.Node[@ast.ShapeId]? raise ParseError {
  guard self.at_keyword("for") else { return None }
  let kw = self.expect_kind(Identifier, "`for`")
  self.require_v2("resource_binding", kw.span)
  Some(self.parse_shape_id())
}

///|
/// The identifier after a shape keyword. It must be on the keyword's own
/// line, and it must be a plain identifier: the reference reports
/// `string com.foo#Bam` at the dot.
fn Parser::parse_shape_name(
  self : Parser,
  kw : @scanner.Token,
) -> @ast.Node[String] raise ParseError {
  let keyword = kw.lexeme
  guard self.peek() is Some(t) && t.kind == Identifier else {
    self.fail(
      "SM-PARSE-001",
      "MISSING SHAPE NAME",
      "I was expecting a shape name after `\{keyword}` but found \{self.found()}",
      self.here_anchored(),
      example="\{keyword} MyShape",
    )
  }
  if kw.trivia_after.iter().any(x => x.is_newline()) ||
    t.trivia_before.iter().any(x => x.is_newline()) {
    // Report at the line break itself (the reference's own unexpected
    // token), not at the shape name that follows it.
    let break_span = match
      kw.trivia_after.iter().find_first(x => x.is_newline()) {
      Some(piece) => piece.span()
      None =>
        match t.trivia_before.iter().find_first(x => x.is_newline()) {
          Some(piece) => piece.span()
          None => self.here()
        }
    }
    self.fail(
      "SM-PARSE-001",
      "MISSING SHAPE NAME",
      "I was expecting a shape name after `\{keyword}` on the same line but found a line break",
      break_span,
      hint="Write the name right after the keyword: `\{keyword} Name`.",
    )
  }
  let name = self.expect_identifier("a shape name")
  if (self.at_kind(Dot) || self.at_kind(Pound) || self.at_kind(Dollar)) &&
    self.adjacent() {
    // Read the rest of the ID to show it whole.
    let start = name.span.start
    let mut end = name.span.end()
    while (
            self.at_kind(Dot) ||
            self.at_kind(Pound) ||
            self.at_kind(Dollar) ||
            self.at_kind(Identifier)
          ) &&
          self.adjacent() {
      match self.advance() {
        Some(t) => end = t.span.end()
        None => ()
      }
    }
    let shown = self.text_between(start, end)
    let reason = if shown.contains("#") {
      "has a namespace"
    } else if shown.contains("$") {
      "names a member"
    } else {
      "has a dot"
    }
    self.fail(
      "SM-PARSE-005",
      "INVALID SHAPE NAME",
      "a shape name is a plain identifier, but `\{shown}` \{reason}",
      start.to(end),
      notes=[
        "A shape is defined in the file's namespace, so its name carries no namespace, and members are declared inside the shape.",
      ],
      hint="Write `\{keyword} \{name.value}`.",
    )
  }
  name
}

///|
/// The source text between two offsets (from the tokens' lexemes).
fn Parser::text_between(
  self : Parser,
  start : @span.Offset,
  end : @span.Offset,
) -> String {
  let sb = StringBuilder()
  for t in self.tokens {
    if t.span.start >= start && t.span.end() <= end {
      sb.write_string(t.lexeme)
    }
  }
  sb.to_string()
}

///|
/// Whether `peek()` starts a member: a trait, an identifier, or `$`.
fn Parser::at_member_start(self : Parser) -> Bool {
  self.at_kind(At) || self.at_kind(Identifier) || self.at_kind(Dollar)
}

///|
/// Whether the token at `i` is a shape keyword, `apply`, `use`, `metadata`
/// or `namespace` at column 1. These are the only tokens whose appearance
/// inside an unclosed block means the block was left open: `@`, `$` and a
/// doc comment are themselves legal member/trait starts at any column
/// (including column 1), so they never end a block on their own. A
/// keyword followed by `:` never starts a statement: it is a member
/// named like one (`namespace: String`).
fn Parser::at_block_breaking_statement(self : Parser, i : Int32) -> Bool {
  guard self.first_on_line(i) && self.at_column_one(i) else { return false }
  guard self.tokens[i].kind == Identifier &&
    statement_keyword(self.tokens[i].lexeme) else {
    return false
  }
  // The token after the keyword, holes skipped, as `peek1` does.
  let mut next = i + 1
  while next < self.tokens.length() && self.tokens[next].kind == Error {
    next += 1
  }
  !(next < self.tokens.length() && self.tokens[next].kind == Colon)
}

///|
/// The "unfinished block" diagnostic shared by every block kind: a member
/// block, an enum block, an operation body or an apply block. Checked at
/// the top of each block's loop, before parsing the next item.
fn Parser::check_unfinished(
  self : Parser,
  title : String,
  owner : String,
) -> Unit raise ParseError {
  if self.at_block_breaking_statement(self.pos) {
    self.fail(
      "SM-PARSE-001",
      title,
      "I was reading \{owner} and found \{self.found()} at the start of a line; did you forget `}`?",
      self.here(),
      hint="Close the block with `}` before the next statement.",
    )
  }
  if self.at_end() {
    self.fail(
      "SM-PARSE-002",
      title,
      "I reached the end of the file while reading \{owner}",
      self.here(),
      hint="Add the closing `}`.",
    )
  }
}

///|
/// Whether, starting at `i`, skipping over a run of trait applications
/// (`@Name` or `@Name(...)`, balancing parens), the next token is a
/// column-1 shape keyword. When it is, the traits at `i` are not a new
/// member's leading traits: the block was left open, and what looks
/// like a member start is really the start of the *next* shape.
fn Parser::leads_to_block_break(self : Parser, i : Int32) -> Bool {
  let mut j = i
  while j < self.tokens.length() && self.tokens[j].kind == At {
    j += 1
    if j < self.tokens.length() && self.tokens[j].kind == Identifier {
      j += 1
      while j + 1 < self.tokens.length() &&
            (
              self.tokens[j].kind == Dot ||
              self.tokens[j].kind == Pound ||
              self.tokens[j].kind == Dollar
            ) &&
            self.tokens[j + 1].kind == Identifier {
        j += 2
      }
    }
    if j < self.tokens.length() && self.tokens[j].kind == LParen {
      let mut depth = 1
      j += 1
      while j < self.tokens.length() && depth > 0 {
        if self.tokens[j].kind == LParen {
          depth += 1
        }
        if self.tokens[j].kind == RParen {
          depth -= 1
        }
        j += 1
      }
    }
  }
  self.at_block_breaking_statement(j)
}

///|
/// Skip to the next member start or the closing brace after an error in a
/// member, so one bad member does not drop the shape. `start_pos` is
/// `self.pos` from before the failed item was attempted: when the item
/// consumed nothing at all (`self.pos` is still `start_pos`), the current
/// token is itself the thing that failed to parse, so it is always
/// advanced past before looking for a stop point — otherwise, if that
/// token already satisfies a stop condition (an indented `$member`, say),
/// this would return without moving and the caller would retry the same
/// token forever. When the item consumed something before failing,
/// `self.pos` is left exactly where it should resume (often the very next
/// member's first token, e.g. after `a:` fails to find a target and the
/// next token is `@required`), so nothing is skipped. Returns `true` when
/// it stops at `}` or at any first-on-line member start (`@`, `$`, or an
/// identifier), so the caller may record the diagnostic and keep going;
/// `false` when it instead reaches a block-breaking statement
/// (`at_block_breaking_statement`) or the end of the file, so the caller
/// must re-raise the original error instead of reporting a second one.
fn Parser::recover_member(self : Parser, start_pos : Int32) -> Bool {
  if self.pos == start_pos && !self.at_end() && !self.at_kind(RBrace) {
    ignore(self.advance())
  }
  while !self.at_end() && !self.at_kind(RBrace) {
    if self.at_block_breaking_statement(self.pos) {
      return false
    }
    if self.first_on_line(self.pos) && self.at_member_start() {
      if self.tokens[self.pos].kind == At && self.leads_to_block_break(self.pos) {
        return false
      }
      return true
    }
    ignore(self.advance())
  }
  self.at_kind(RBrace)
}

///|
/// The `WS` between members or object/trait entries. `construct` gives
/// entries their own diagnostic wording. For members, the grammar is `ShapeMembers = "{" [WS]
/// *(ShapeMember [WS]) "}"`, and `WS = 1*(SP / NL / Comment / Comma)`, so
/// any whitespace at all separates members (unlike a statement's `BR`,
/// members do not need a line break, a comment or a comma specifically:
/// `enum A { FOO BAR BAZ }` and `map H { key: String value: String }` are
/// both valid, with members separated only by a space).
fn Parser::expect_separator(
  self : Parser,
  construct? : String,
) -> Unit raise ParseError {
  guard self.pos > 0 else { return }
  guard self.peek() is Some(next) else { return }
  let prev = self.tokens[self.pos - 1]
  let has_sep = prev.trivia_after.length() > 0 ||
    next.trivia_before.length() > 0
  if !has_sep {
    self.fail(
      "SM-PARSE-003",
      "MISSING SEPARATOR",
      match construct {
        Some(what) =>
          "I was expecting whitespace between entries in \{what} but found \{self.found()}"
        None => "I was expecting whitespace here but found \{self.found()}"
      },
      next.span,
      notes=[
        match construct {
          Some(what) => "I separate entries in \{what} with whitespace."
          None => "Each member must be separated from the next by whitespace."
        },
      ],
      hint="Put a space before `\{next.lexeme}`.",
    )
  }
}

///|
/// The shared loop for `ShapeMembers` and `EnumShapeMembers`: read items
/// with `parse_item` until `}`, recovering from one bad item (without
/// losing the rest) and restoring `contexts` and `depth` to what they were
/// before the bad item, since whatever it entered (a trait body, a node
/// value) may never have run its own cleanup once it raised.
fn[T] Parser::parse_block_items(
  self : Parser,
  title : String,
  owner : String,
  parse_item : () -> Result[T, ParseError],
  needs_br? : (T) -> Bool,
  name_of? : (T) -> @ast.Node[String],
) -> Array[T] raise ParseError {
  let items : Array[T] = []
  let seen_names : Array[String] = []
  while !self.at_kind(RBrace) {
    self.check_unfinished(title, "the members of \{owner}")
    let start_pos = self.pos
    let ctx_len = self.contexts.length()
    let depth0 = self.depth
    match parse_item() {
      Ok(m) => {
        let strict = match needs_br {
          Some(f) => f(m)
          None => false
        }
        match name_of {
          Some(f) => {
            let name = f(m)
            // Reported, not raised: the shape and both members stay in
            // the AST, so editors and generators keep the shape.
            if seen_names.contains(name.value) {
              self.report(
                "SM-PARSE-014",
                Error,
                "DUPLICATE MEMBER",
                "Found conflicting member name, `\{name.value}`",
                name.span,
                notes=[
                  "I already saw a member named `\{name.value}` in this shape; each member name is used once.",
                ],
                hint="Rename one of them or remove the duplicate.",
              )
            }
            seen_names.push(name.value)
          }
          None => ()
        }
        items.push(m)
        if !self.at_kind(RBrace) {
          // `ValueAssignment` ends with a true `BR`, stricter than the
          // `[WS]` that otherwise separates members (`FOO = 1 BAR = 2` on
          // one line is invalid, but `FOO BAR` is fine).
          if strict {
            self.expect_br()
          } else {
            self.expect_separator()
          }
        }
      }
      Err(e) => {
        while self.contexts.length() > ctx_len {
          ignore(self.contexts.pop())
        }
        self.depth = depth0
        if self.recover_member(start_pos) {
          self.diagnostics.push(e.diagnostic())
        } else {
          raise e
        }
      }
    }
  }
  self.detach_docs_before(self.here().start)
  items
}

///|
/// `ShapeMembers = "{" [WS] *(ShapeMember [WS]) "}"`, each
/// `ShapeMember = TraitStatements (ExplicitShapeMember / ElidedShapeMember) [ValueAssignment]`.
fn Parser::parse_members(
  self : Parser,
  owner : String,
) -> Array[@ast.Member] raise ParseError {
  let open = self.expect_kind(LBrace, "`{` to start the members of \{owner}")
  self.enter()
  let members = self.parse_block_items(
    "UNFINISHED SHAPE",
    owner,
    () => {
      try Ok(self.parse_member()) catch {
        e => Err(e)
      } noraise {
        v => v
      }
    },
    needs_br=m => m.default is Some(_),
    name_of=m => m.name,
  )
  ignore(self.expect_kind(RBrace, "`}`"))
  self.leave()
  ignore(open)
  members
}

///|
/// One `ShapeMember`.
fn Parser::parse_member(self : Parser) -> @ast.Member raise ParseError {
  guard self.peek() is Some(first) else {
    self.fail(
      "SM-PARSE-002",
      "UNEXPECTED END OF FILE",
      "I was expecting a member",
      self.here(),
    )
  }
  let docs = self.take_docs_before(first.span.start)
  let traits = self.parse_traits()
  // Documentation must precede the first trait, not follow its body.
  self.take_docs_before(self.here().start) |> ignore
  // A column-1 shape keyword after a member's leading traits means those
  // traits belong to the *next* shape, not to a member here: the block
  // was left open, not a member with an odd name.
  self.check_unfinished("UNFINISHED SHAPE", "a member")
  let (name, target) : (@ast.Node[String], @ast.MemberTarget) = if self.at_kind(
      Dollar,
    ) {
    let d = self.expect_kind(Dollar, "`$`")
    self.require_v2("elision", d.span)
    guard self.adjacent() && self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting a member name right after `$` but found \{self.found()}",
        self.here(),
        example="$memberName",
      )
    }
    let n = self.expect_identifier("a member name")
    (@ast.Node::new(n.value, d.span.join(n.span)), Elided)
  } else {
    guard self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting a member name but found \{self.found()}",
        self.here(),
        notes=[
          "A member looks like `name: Target`, with optional traits before it and an optional `= default` after it.",
        ],
      )
    }
    let n = self.expect_identifier("a member name")
    guard self.at_kind(Colon) else {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting `:` after the member name `\{n.value}` but found \{self.found()}",
        self.here(),
        example="\{n.value}: String",
      )
    }
    ignore(self.advance())
    let target = self.parse_shape_id()
    (n, Explicit(target))
  }
  let mut end = match target {
    Explicit(t) => t.span.end()
    Elided => name.span.end()
  }
  let default : @ast.NodeValue? = if self.at_kind(Equal) {
    let eq = self.expect_kind(Equal, "`=`")
    self.require_v2("default", eq.span)
    self.expect_sp_after("the default value")
    let v = self.parse_node_value()
    end = v.span().end()
    Some(v)
  } else {
    None
  }
  let start = if traits.length() > 0 {
    traits[0].span.start
  } else {
    name.span.start
  }
  {
    docs: docs[:],
    traits: traits[:],
    name,
    target,
    default,
    span: start.to(end),
  }
}

///|
/// `EnumShapeMembers = "{" [WS] 1*(EnumShapeMember [WS]) "}"`.
fn Parser::parse_enum_members(
  self : Parser,
  owner : String,
) -> Array[@ast.EnumMember] raise ParseError {
  ignore(self.expect_kind(LBrace, "`{` to start the members of \{owner}"))
  self.enter()
  let members = self.parse_block_items(
    "UNFINISHED ENUM",
    owner,
    () => {
      try Ok(self.parse_enum_member()) catch {
        e => Err(e)
      } noraise {
        v => v
      }
    },
    needs_br=m => m.value is Some(_),
    name_of=m => m.name,
  )
  ignore(self.expect_kind(RBrace, "`}`"))
  self.leave()
  members
}

///|
/// One `EnumShapeMember`.
fn Parser::parse_enum_member(self : Parser) -> @ast.EnumMember raise ParseError {
  guard self.peek() is Some(first) else {
    self.fail(
      "SM-PARSE-002",
      "UNEXPECTED END OF FILE",
      "I was expecting an enum member",
      self.here(),
    )
  }
  let docs = self.take_docs_before(first.span.start)
  let traits = self.parse_traits()
  self.take_docs_before(self.here().start) |> ignore
  if self.at_kind(Dollar) {
    let d = self.expect_kind(Dollar, "`$`")
    self.fail(
      "SM-PARSE-001",
      "UNEXPECTED TOKEN",
      "an enum member is a name, not `$name`",
      d.span,
      hint="Write the member name without a leading `$`; `$name` elides a member from a mixin, which enums don't have.",
    )
  }
  guard self.at_kind(Identifier) else {
    self.fail(
      "SM-PARSE-001",
      "UNEXPECTED TOKEN",
      "I was expecting an enum member name but found \{self.found()}",
      self.here(),
      example="RED = \"red\"",
    )
  }
  let name = self.expect_identifier("an enum member name")
  let mut end = name.span.end()
  let value : @ast.NodeValue? = if self.at_kind(Equal) {
    ignore(self.advance())
    self.expect_sp_after("the enum value")
    let v = self.parse_node_value()
    end = v.span().end()
    Some(v)
  } else {
    None
  }
  let start = if traits.length() > 0 {
    traits[0].span.start
  } else {
    name.span.start
  }
  { docs: docs[:], traits: traits[:], name, value, span: start.to(end), }
}

///|
/// `InlineAggregateShape = ":=" [WS] TraitStatements [ForResource] [Mixins] [WS] ShapeMembers`.
fn Parser::parse_inline_shape(
  self : Parser,
  walrus : @scanner.Token,
) -> @ast.InlineShape raise ParseError {
  self.require_v2("inline", walrus.span)
  let docs = self.take_docs_before(self.here().start)
  let traits = self.parse_traits()
  let for_resource = self.parse_for_resource()
  let mixins = self.parse_mixins(same_line=false)
  self.push_context("an inline shape", walrus.span)
  let members = self.parse_members("the inline shape")
  self.pop_context()
  let end = self.previous_end()
  {
    docs: docs[:],
    traits: traits[:],
    for_resource,
    mixins,
    members: members[:],
    span: walrus.span.start.to(end),
  }
}

///|
/// `OperationBody = "{" [WS] *(OperationProperty [WS]) "}"`.
fn Parser::parse_operation_body(
  self : Parser,
  owner : String,
) -> Array[@ast.OperationProperty] raise ParseError {
  ignore(self.expect_kind(LBrace, "`{` to start the body of \{owner}"))
  self.enter()
  let props : Array[@ast.OperationProperty] = []
  while !self.at_kind(RBrace) {
    self.check_unfinished("UNFINISHED OPERATION", owner)
    // Inline-shape documentation follows `:=`, before its leading traits.
    guard self.peek() is Some(key) && key.kind == Identifier else {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting `input`, `output` or `errors` but found \{self.found()}",
        self.here(),
      )
    }
    let duplicate = match key.lexeme {
      "input" => props.iter().any(p => p is Input(_, _))
      "output" => props.iter().any(p => p is Output(_, _))
      "errors" => props.iter().any(p => p is Errors(_, _))
      _ => false
    }
    if duplicate {
      self.report(
        "SM-PARSE-012",
        Error,
        "DUPLICATE OPERATION PROPERTY",
        "Duplicate operation \{key.lexeme} property for \{owner}",
        key.span,
        notes=[
          "I already saw a `\{key.lexeme}` property for \{owner}; an operation body holds `input`, `output` and `errors`, each at most once.",
        ],
        hint="Remove the duplicate `\{key.lexeme}` property.",
      )
    }
    match key.lexeme {
      "input" | "output" => {
        ignore(self.advance())
        let target : @ast.OperationTarget = if self.at_kind(Walrus) {
          let w = self.expect_kind(Walrus, "`:=`")
          Inline(self.parse_inline_shape(w))
        } else {
          self.detach_docs_before(key.span.start)
          ignore(self.expect_kind(Colon, "`:` or `:=` after `\{key.lexeme}`"))
          Reference(self.parse_shape_id())
        }
        let end = self.previous_end()
        let span = key.span.start.to(end)
        props.push(
          if key.lexeme == "input" {
            Input(target, span)
          } else {
            Output(target, span)
          },
        )
      }
      "errors" => {
        self.detach_docs_before(key.span.start)
        ignore(self.advance())
        ignore(self.expect_kind(Colon, "`:` after `errors`"))
        ignore(self.expect_kind(LBracket, "`[` to start the error list"))
        let ids : Array[@ast.Node[@ast.ShapeId]] = []
        while !self.at_kind(RBracket) {
          if self.at_end() {
            self.fail(
              "SM-PARSE-002",
              "UNFINISHED ERROR LIST",
              "I reached the end of the file inside the error list",
              self.here(),
              hint="Add the closing `]`.",
            )
          }
          ids.push(self.parse_shape_id())
        }
        let close = self.expect_kind(RBracket, "`]`")
        props.push(Errors(ids[:], key.span.join(close.span)))
      }
      other =>
        self.fail(
          "SM-PARSE-011",
          "UNKNOWN OPERATION PROPERTY",
          "an operation has no `\{other}` property",
          key.span,
          notes=[
            "An operation body holds `input`, `output` and `errors`, each at most once.",
          ],
          hint=if other == "inputs" {
            "Did you mean `input`?"
          } else if other == "outputs" {
            "Did you mean `output`?"
          } else if other == "error" {
            "Did you mean `errors`?"
          } else {
            "Remove it, or move it into a trait."
          },
        )
    }
    if !self.at_kind(RBrace) {
      self.expect_separator()
    }
  }
  self.detach_docs_before(self.here().start)
  ignore(self.expect_kind(RBrace, "`}`"))
  self.leave()
  props
}

///|
/// The value of the node object key `key` in `body`, if `body` is an
/// object and has it.
fn object_key(body : @ast.NodeValue, key : String) -> @ast.NodeValue? {
  guard body is Object(kvps, _) else { return None }
  for kvp in kvps {
    if kvp.key.value == key {
      return Some(kvp.value)
    }
  }
  None
}

///|
/// `Shape`, after the docs and traits; `start` is the statement start.
fn Parser::parse_shape(
  self : Parser,
  docs : Array[@ast.DocComment],
  traits : Array[@ast.Trait],
  start : @span.Offset,
) -> @ast.ShapeStatement raise ParseError {
  guard self.peek() is Some(kw) &&
    kw.kind == Identifier &&
    @ast.ShapeKind::of(kw.lexeme) is Some(kind) else {
    if traits.length() > 0 || docs.length() > 0 {
      self.fail(
        "SM-PARSE-004",
        "EXPECTED A SHAPE",
        "I was expecting a shape after the traits but found \{self.found()}",
        self.here(),
        notes=[
          "Traits and documentation comments apply to the shape statement right after them.",
        ],
      )
    }
    self.fail(
      "SM-PARSE-004",
      "EXPECTED A STATEMENT",
      "I was expecting a shape statement or `apply` but found \{self.found()}",
      self.here(),
    )
  }
  ignore(self.advance())
  let name = self.parse_shape_name(kw)
  let owner = "the \{kw.lexeme} `\{name.value}`"
  self.push_context(owner, kw.span)
  let shape : @ast.Shape = match kind {
    Simple(t) => Simple(kind=t, name~, mixins=self.parse_mixins())
    Enum(t) => {
      self.require_v2("enum", kw.span)
      let mixins = self.parse_mixins()
      let members = self.parse_enum_members(owner)
      Enum(kind=t, name~, mixins~, members=members[:])
    }
    Aggregate(t) => {
      // `set` is not a shape type keyword in IDL 2.0 (lists took over,
      // with `@uniqueItems` for the old `set` behavior). Like
      // `require_v2`, this reports once per file.
      if t is Set && self.claim_v1_report() {
        self.report(
          "SM-PARSE-015",
          Error,
          "NEEDS SMITHY IDL 1",
          "set shapes cannot be used in Smithy version 2.0",
          kw.span,
          notes=["Use a list with the `@uniqueItems` trait in IDL 2.0 instead."],
        )
      }
      let for_resource = self.parse_for_resource()
      let mixins = self.parse_mixins()
      let members = self.parse_members(owner)
      Aggregate(kind=t, name~, for_resource~, mixins~, members=members[:])
    }
    Entity(t) => {
      let mixins = self.parse_mixins()
      guard self.at_kind(LBrace) else {
        self.fail(
          "SM-PARSE-001",
          "UNEXPECTED TOKEN",
          "I was expecting `{` to start the body of \{owner} but found \{self.found()}",
          self.here(),
          example="\{kw.lexeme} \{name.value} {\n    version: \"2024-01-01\"\n}",
        )
      }
      let body = self.parse_node_value()
      if t is Resource {
        if object_key(body, "properties") is Some(_) && self.claim_v2_report() {
          self.report(
            "SM-PARSE-007",
            Error,
            "NEEDS SMITHY IDL 2",
            "Resource properties can only be used with Smithy version 2 or later",
            body.span(),
            notes=[
              "This file is Smithy IDL 1.0: " +
              (if self.version is None {
                "it has no `$version` statement, so I read it as version 1.0."
              } else {
                "its `$version` says so."
              }),
            ],
            hint="Add `$version: \"2\"` as the first line of the file.",
          )
        }
      }
      Entity(kind=t, name~, mixins~, body~)
    }
    Operation => {
      let mixins = self.parse_mixins()
      let properties = self.parse_operation_body(owner)
      Operation(name~, mixins~, properties=properties[:])
    }
  }
  self.pop_context()
  let end = self.previous_end()
  { docs: docs[:], traits: traits[:], shape, span: start.to(end), }
}

///|
/// `ApplyStatement = ApplyStatementSingular / ApplyStatementBlock`.
fn Parser::parse_apply(
  self : Parser,
  start : @span.Offset,
) -> @ast.ApplyStatement raise ParseError {
  let kw = self.expect_kind(Identifier, "`apply`")
  self.push_context("an apply statement", kw.span)
  let target = self.parse_shape_id()
  self.expect_sp_present("the trait or `{` after the apply target")
  let (traits, block) : (Array[@ast.Trait], Bool) = if self.at_kind(LBrace) {
    ignore(self.advance())
    self.enter()
    let ts : Array[@ast.Trait] = []
    while !self.at_kind(RBrace) {
      self.check_unfinished(
        "UNFINISHED APPLY",
        "the traits applied to `\{target.value}`",
      )
      ts.push(self.parse_trait())
    }
    self.detach_docs_before(self.here().start)
    ignore(self.expect_kind(RBrace, "`}` to close the apply block"))
    self.leave()
    (ts, true)
  } else {
    guard self.at_kind(At) else {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting a trait or `{` after the apply target but found \{self.found()}",
        self.here(),
        example="apply \{target.value} @deprecated",
      )
    }
    ([self.parse_trait()], false)
  }
  self.pop_context()
  let end = self.previous_end()
  { target, traits: traits[:], block, span: start.to(end), }
}

///|
/// `ShapeOrApplyStatement`, then `BR`.
fn Parser::parse_shape_or_apply(
  self : Parser,
) -> @ast.Statement raise ParseError {
  guard self.peek() is Some(first) else {
    self.fail(
      "SM-PARSE-002",
      "UNEXPECTED END OF FILE",
      "I was expecting a statement",
      self.here(),
    )
  }
  let start = first.span.start
  let docs = self.take_docs_before(start)
  if self.at_keyword("apply") {
    if docs.length() > 0 {
      // An `apply` statement adds traits to a shape defined elsewhere, so it
      // cannot take documentation: the reference treats a doc comment here
      // as an ordinary comment (dropped, not an error).
      self.report(
        "SM-PARSE-008",
        Warning,
        "DOCS BEFORE APPLY",
        "a documentation comment cannot be applied with an apply statement, so I read it as an ordinary comment",
        docs[0].span,
        notes=[
          "An `apply` statement adds traits to a shape defined elsewhere; documentation is written where the shape is defined, or applied as `@documentation(\"...\")`.",
        ],
        hint="Turn it into a `//` comment or into `apply \{self.peek1().map(t => t.lexeme).unwrap_or("Target")} @documentation(\"...\")`.",
      )
    }
    let a = self.parse_apply(start)
    self.expect_br()
    return Apply(a)
  }
  let traits = self.parse_traits()
  // Only a shape type keyword after the traits belongs to this statement
  // for recovery; anything else (`apply`, say) is a statement of its own.
  if self.peek() is Some(k) &&
    k.kind == Identifier &&
    @ast.ShapeKind::of(k.lexeme) is Some(_) {
    self.keyword_index = self.pos
  }
  self.take_docs_before(self.here().start) |> ignore
  let s = self.parse_shape(docs, traits, start)
  self.expect_br()
  Shape(s)
}
