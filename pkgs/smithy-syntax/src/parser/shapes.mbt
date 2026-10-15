///|
/// `Mixins = [SP] "with" [WS] "[" [WS] 1*(ShapeId [WS]) "]"`.
fn Parser::parse_mixins(self : Parser) -> @ast.Mixins? raise ParseError {
  guard self.at_keyword("with") else { return None }
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
  self.require_v2("for", kw.span)
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
      self.here(),
      example="\{keyword} MyShape",
    )
  }
  if kw.trivia_after.iter().any(x => x.is_newline()) ||
    t.trivia_before.iter().any(x => x.is_newline()) {
    self.fail(
      "SM-PARSE-001",
      "MISSING SHAPE NAME",
      "I was expecting a shape name after `\{keyword}` on the same line but found a line break",
      self.here(),
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
/// (including column 1), so they never end a block on their own.
fn Parser::at_block_breaking_statement(self : Parser, i : Int32) -> Bool {
  guard self.first_on_line(i) && self.at_column_one(i) else { return false }
  self.tokens[i].kind == Identifier && statement_keyword(self.tokens[i].lexeme)
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
      return true
    }
    ignore(self.advance())
  }
  self.at_kind(RBrace)
}

///|
/// The `BR` between two members: a line break, a comment, or a comma (the
/// grammar's `WS` separates members; only statements need a true `BR`).
fn Parser::expect_member_br(self : Parser) -> Unit raise ParseError {
  guard self.pos > 0 else { return }
  guard self.peek() is Some(next) else { return }
  let prev = self.tokens[self.pos - 1]
  let has_sep = prev.trivia_after
    .iter()
    .any(t => t.is_newline() || t.is_comment() || t is Comma(_)) ||
    next.trivia_before
    .iter()
    .any(t => t.is_newline() || t.is_comment() || t is Comma(_))
  if !has_sep {
    self.fail(
      "SM-PARSE-003",
      "MISSING LINE BREAK",
      "I was expecting a line break here but found \{self.found()}",
      next.span,
      notes=[
        "Each member ends with a line break, a comment or a comma before the next one.",
      ],
      hint="Put `\{next.lexeme}` on its own line, or separate it with a comma.",
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
) -> Array[T] raise ParseError {
  let items : Array[T] = []
  while !self.at_kind(RBrace) {
    self.check_unfinished(title, "the members of \{owner}")
    let start_pos = self.pos
    let ctx_len = self.contexts.length()
    let depth0 = self.depth
    match parse_item() {
      Ok(m) => {
        items.push(m)
        if !self.at_kind(RBrace) {
          self.expect_member_br()
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
  let members = self.parse_block_items("UNFINISHED SHAPE", owner, () => {
    try Ok(self.parse_member()) catch {
      e => Err(e)
    } noraise {
      v => v
    }
  })
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
  // Docs between traits and the name still attach.
  docs.append(self.take_docs_before(self.here().start))
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
    ignore(self.advance())
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
  let members = self.parse_block_items("UNFINISHED ENUM", owner, () => {
    try Ok(self.parse_enum_member()) catch {
      e => Err(e)
    } noraise {
      v => v
    }
  })
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
  docs.append(self.take_docs_before(self.here().start))
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
  let docs = self.take_docs_before(walrus.span.start)
  let traits = self.parse_traits()
  let for_resource = self.parse_for_resource()
  let mixins = self.parse_mixins()
  self.push_context("an inline shape", walrus.span)
  let members = self.parse_members("the inline shape")
  self.pop_context()
  let end = self.tokens[self.pos - 1].span.end()
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
    // Docs before `input :=` belong to the inline shape; elsewhere they are detached.
    guard self.peek() is Some(key) && key.kind == Identifier else {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting `input`, `output` or `errors` but found \{self.found()}",
        self.here(),
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
        let end = self.tokens[self.pos - 1].span.end()
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
      self.expect_member_br()
    }
  }
  self.detach_docs_before(self.here().start)
  ignore(self.expect_kind(RBrace, "`}`"))
  self.leave()
  props
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
      let mixins = self.parse_mixins()
      Enum(kind=t, name~, mixins~, members=self.parse_enum_members(owner)[:])
    }
    Aggregate(t) => {
      let for_resource = self.parse_for_resource()
      let mixins = self.parse_mixins()
      Aggregate(
        kind=t,
        name~,
        for_resource~,
        mixins~,
        members=self.parse_members(owner)[:],
      )
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
      Entity(kind=t, name~, mixins~, body=self.parse_node_value())
    }
    Operation => {
      let mixins = self.parse_mixins()
      Operation(name~, mixins~, properties=self.parse_operation_body(owner)[:])
    }
  }
  self.pop_context()
  let end = self.tokens[self.pos - 1].span.end()
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
  let end = self.tokens[self.pos - 1].span.end()
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
      self.fail(
        "SM-PARSE-008",
        "DOCS BEFORE APPLY",
        "a documentation comment cannot be applied with an apply statement",
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
  docs.append(self.take_docs_before(self.here().start))
  let s = self.parse_shape(docs, traits, start)
  self.expect_br()
  Shape(s)
}
