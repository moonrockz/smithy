///|
/// Keywords that start a statement, for recovery and dispatch.
fn statement_keyword(word : String) -> Bool {
  word == "namespace" ||
  word == "use" ||
  word == "metadata" ||
  word == "apply" ||
  @ast.ShapeKind::of(word) is Some(_)
}

///|
/// Whether the token at `i` is the first on its line.
fn Parser::first_on_line(self : Parser, i : Int32) -> Bool {
  guard i >= 0 && i < self.tokens.length() else { return false }
  if i == 0 {
    return true
  }
  let prev = self.tokens[i - 1]
  prev.trivia_after.iter().any(t => t.is_newline()) ||
  self.tokens[i].trivia_before.iter().any(t => t.is_newline())
}

///|
/// Whether the token at `i` is at column 1: first on its line and no
/// whitespace or comma precedes it on that line (no `Whitespace` or
/// `Comma` after the last `Newline` in its `trivia_before`, or, for
/// `i == 0`, no `Whitespace` or `Comma` at all).
fn Parser::at_column_one(self : Parser, i : Int32) -> Bool {
  guard i >= 0 && i < self.tokens.length() else { return false }
  let before = self.tokens[i].trivia_before
  let mut last_newline = -1
  for idx, t in before {
    if t.is_newline() {
      last_newline = idx
    }
  }
  let mut j = last_newline + 1
  while j < before.length() {
    if before[j] is (Whitespace(_, _) | Comma(_)) {
      return false
    }
    j += 1
  }
  true
}

///|
/// Whether the token at `i` starts a statement for recovery: at column 1
/// and a statement keyword, `@`, `$`, or preceded by a doc comment.
/// Indented tokens never start a statement.
fn Parser::at_statement_start(self : Parser, i : Int32) -> Bool {
  guard self.first_on_line(i) && self.at_column_one(i) else { return false }
  let t = self.tokens[i]
  match t.kind {
    At | Dollar => true
    Identifier => statement_keyword(t.lexeme)
    _ => t.trivia_before.iter().any(x => x is Comment(c) && c.kind == Doc)
  }
}

///|
/// Skip from `from` to the next statement start (or the end), and record
/// the run as `Skipped`. The scan starts after the failed statement's own
/// shape keyword (`keyword_index`), which follows its traits and so is at
/// a statement start itself.
fn Parser::recover(
  self : Parser,
  from : Int32,
  out : Array[@cst.StatementCst],
) -> Unit {
  let resume = if self.keyword_index > from { self.keyword_index } else { from }
  // Traits that run to the end of the file leave `keyword_index` at the end.
  let mut i = if resume < self.tokens.length() {
    resume + 1
  } else {
    self.tokens.length()
  }
  while i < self.tokens.length() && !self.at_statement_start(i) {
    i += 1
  }
  // A scanner hole with leading documentation can look like a recovery
  // boundary. Keep it in this run before resuming at the next real token.
  while i < self.tokens.length() && self.tokens[i].kind == Error {
    i += 1
  }
  out.push(
    @cst.StatementCst::new(kind=Skipped, name=None, tokens=self.tokens[from:i]),
  )
  if i > from {
    // Doc comments inside the skipped run belong to it.
    let run_end = self.tokens[i - 1].span.end()
    while self.doc_head < self.doc_comments.length() &&
          self.doc_comments[self.doc_head].span.start < run_end {
      self.doc_head += 1
    }
  }
  self.pos = i
  self.skip_holes()
  self.depth = Depth::zero()
  self.contexts.clear()
}

///|
/// `ControlStatement = "$" NodeObjectKey [SP] ":" [SP] NodeValue BR`.
fn Parser::parse_control(
  self : Parser,
) -> @ast.ControlStatement raise ParseError {
  let dollar = self.expect_kind(Dollar, "`$`")
  self.push_context("a control statement", dollar.span)
  let key = self.parse_object_key()
  self.expect_sp_after("`:`")
  ignore(self.expect_kind(Colon, "`:` after the control key"))
  self.expect_sp_after("the control value")
  let value = self.parse_node_value()
  self.expect_br()
  self.pop_context()
  if key.value == "version" {
    // A second `$version` is a duplicate control statement; reject it before
    // touching the recorded version, so the first statement stays in force.
    if self.version is Some(_) {
      self.fail(
        "SM-PARSE-013",
        "DUPLICATE CONTROL STATEMENT",
        "Duplicate control statement `version`",
        key.span,
        notes=[
          "I already saw a `version` control statement; each control statement key may be set at most once.",
        ],
        hint="Remove the duplicate `version` statement.",
      )
    }
    match value {
      String(v, _) =>
        match Version::of(v) {
          Some(ver) => self.version = Some(ver)
          None =>
            self.fail(
              "SM-PARSE-006",
              "UNSUPPORTED SMITHY VERSION",
              "Unsupported Smithy version number: \{v}",
              value.span(),
              notes=["I know versions `1`, `1.0`, `2` and `2.0`."],
              hint="Write `$version: \"2\"`.",
            )
        }
      _ =>
        self.fail(
          "SM-PARSE-006",
          "UNSUPPORTED SMITHY VERSION",
          "the `$version` value must be a string",
          value.span(),
          example="$version: \"2\"",
        )
    }
  }
  { key, value, span: dollar.span.join(value.span()), }
}

///|
/// `MetadataStatement = "metadata" SP NodeObjectKey [SP] "=" [SP] NodeValue BR`.
fn Parser::parse_metadata(
  self : Parser,
) -> @ast.MetadataStatement raise ParseError {
  let kw = self.expect_kind(Identifier, "`metadata`")
  self.push_context("a metadata statement", kw.span)
  self.expect_sp_present("the metadata key")
  self.expect_sp_after("the metadata key")
  let key = self.parse_object_key()
  self.expect_sp_after("`=`")
  ignore(self.expect_kind(Equal, "`=` after the metadata key"))
  self.expect_sp_after("the metadata value")
  let value = self.parse_node_value()
  self.expect_br()
  self.pop_context()
  { key, value, span: kw.span.join(value.span()), }
}

///|
/// `NamespaceStatement = "namespace" SP Namespace BR`.
fn Parser::parse_namespace(
  self : Parser,
) -> @ast.NamespaceStatement raise ParseError {
  let kw = self.expect_kind(Identifier, "`namespace`")
  self.push_context("a namespace statement", kw.span)
  self.expect_sp_after("the namespace")
  let first = self.expect_identifier("a namespace like `com.example`")
  let parts = [first.value]
  let mut end = first.span.end()
  while self.at_kind(Dot) && self.adjacent() {
    ignore(self.advance())
    guard self.adjacent() && self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-005",
        "INVALID NAMESPACE",
        "I was expecting a namespace segment after `.`",
        self.here_anchored(),
        example="namespace com.example",
      )
    }
    let seg = self.expect_identifier("a namespace segment")
    parts.push(seg.value)
    end = seg.span.end()
  }
  self.expect_br()
  self.pop_context()
  let span = first.span.start.to(end)
  {
    namespace: @ast.Node::new(parts.join("."), span),
    span: kw.span.join(span),
  }
}

///|
/// `UseStatement = "use" SP AbsoluteRootShapeId BR`.
fn Parser::parse_use(self : Parser) -> @ast.UseStatement raise ParseError {
  let kw = self.expect_kind(Identifier, "`use`")
  self.push_context("a use statement", kw.span)
  self.expect_sp_after("the shape ID to use")
  let id = self.parse_shape_id()
  if !id.value.is_absolute() || id.value.member is Some(_) {
    self.fail(
      "SM-PARSE-005",
      "INVALID USE TARGET",
      "a `use` statement needs an absolute shape ID like `smithy.api#String`",
      id.span,
      hint="Add the namespace and `#`, and drop any `$member`.",
    )
  }
  self.expect_br()
  self.pop_context()
  { id, span: kw.span.join(id.span), }
}

///|
/// Which section a statement start belongs to, to enforce the order
/// control, metadata, namespace, use, shapes.
priv enum Section {
  ControlSection
  MetadataSection
  NamespaceSection
  UseSection
  ShapeSection
}

///|
/// Parse a token stream into an `IdlFile`, with recovery per statement.
pub fn parse_tokens(stream : @scanner.TokenStream) -> ParseResult {
  let p = Parser::new(stream)
  let control : Array[@ast.ControlStatement] = []
  let metadata : Array[@ast.MetadataStatement] = []
  let mut namespace : @ast.NamespaceStatement? = None
  let uses : Array[@ast.UseStatement] = []
  let statements : Array[@ast.Statement] = []
  let cst_statements : Array[@cst.StatementCst] = []
  // `Parser::new` already skipped any leading holes (`Error` tokens); they
  // belong to no statement, so record them here or the CST would not tile
  // the token array.
  if p.pos > 0 {
    cst_statements.push(
      @cst.StatementCst::new(
        kind=Skipped,
        name=None,
        tokens=stream.tokens[0:p.pos],
      ),
    )
  }
  let mut section = ControlSection
  let mut read_anything = false
  // Guards the one-time `MISSING NAMESPACE` report below: a file missing
  // its `namespace` statement gets exactly one diagnostic, not one per
  // shape, `use` or `apply` statement that follows.
  let mut reported_missing_namespace = false
  while !p.at_end() {
    let start_index = p.pos
    p.keyword_index = start_index
    guard p.peek() is Some(t) else { break }
    let start_offset = t.span.start
    let outcome = try {
      // Section dispatch on the first token of the statement.
      if t.kind == Dollar &&
        p.peek1() is Some(k) &&
        k.kind == Identifier &&
        p.first_on_line(start_index) &&
        section is ControlSection {
        p.detach_docs_before(start_offset)
        let c = p.parse_control()
        if control.iter().any(x => x.key.value == c.key.value) {
          p.fail(
            "SM-PARSE-013",
            "DUPLICATE CONTROL STATEMENT",
            "Duplicate control statement `\{c.key.value}`",
            c.key.span,
            notes=[
              "I already saw a `\{c.key.value}` control statement; each control statement key may be set at most once.",
            ],
            hint="Remove the duplicate `\{c.key.value}` statement, or change its key.",
          )
        }
        control.push(c)
        Ok((@cst.StatementKind::Control, Some(c.key.value)))
      } else if p.at_keyword("metadata") &&
        (section is ControlSection || section is MetadataSection) {
        p.detach_docs_before(start_offset)
        section = MetadataSection
        let m = p.parse_metadata()
        metadata.push(m)
        Ok((@cst.StatementKind::Metadata, Some(m.key.value)))
      } else if p.at_keyword("namespace") &&
        namespace is None &&
        !(section is UseSection || section is ShapeSection) {
        p.detach_docs_before(start_offset)
        section = NamespaceSection
        let n = p.parse_namespace()
        namespace = Some(n)
        Ok((@cst.StatementKind::Namespace, Some(n.namespace.value)))
      } else if p.at_keyword("use") &&
        (section is NamespaceSection || section is UseSection) {
        p.detach_docs_before(start_offset)
        section = UseSection
        let u = p.parse_use()
        uses.push(u)
        Ok((@cst.StatementKind::Use, Some(u.id.value.to_string())))
      } else if namespace is None &&
        !(p.at_keyword("use") && section is ShapeSection) &&
        (
          p.at_keyword("use") ||
          p.at_keyword("apply") ||
          t.kind == At ||
          (t.kind == Identifier && @ast.ShapeKind::of(t.lexeme) is Some(_))
        ) {
        // A shape, `use` or `apply` statement with no `namespace` before
        // it: report it once, then keep parsing the shape section as if
        // the namespace were there, so one typo gives one diagnostic
        // instead of one per statement that follows.
        if !reported_missing_namespace {
          reported_missing_namespace = true
          p.report(
            "SM-PARSE-004",
            Error,
            "MISSING NAMESPACE",
            "I found `\{t.lexeme}` but no `namespace` statement before it",
            t.span,
            notes=[
              "Every shape, `use` and `apply` statement belongs to a namespace, which the file declares with `namespace your.package` before them.",
            ],
            hint="Add `namespace your.package` before the first shape.",
          )
        }
        section = ShapeSection
        if p.at_keyword("use") {
          p.detach_docs_before(start_offset)
          let u = p.parse_use()
          uses.push(u)
          Ok((@cst.StatementKind::Use, Some(u.id.value.to_string())))
        } else {
          let s = p.parse_shape_or_apply()
          statements.push(s)
          Ok(statement_cst_kind(s))
        }
      } else if p.at_keyword("metadata") ||
        p.at_keyword("namespace") ||
        p.at_keyword("use") ||
        (
          t.kind == Dollar &&
          p.peek1() is Some(k) &&
          k.kind == Identifier &&
          p.first_on_line(start_index)
        ) {
        p.expected_statement(section, namespace is Some(_))
      } else if namespace is Some(_) {
        section = ShapeSection
        let s = p.parse_shape_or_apply()
        statements.push(s)
        Ok(statement_cst_kind(s))
      } else {
        p.expected_statement(section, namespace is Some(_))
      }
    } catch {
      e => Err(e)
    } noraise {
      v => v
    }
    match outcome {
      Ok((kind, name)) => {
        read_anything = true
        cst_statements.push(
          @cst.StatementCst::new(
            kind~,
            name~,
            tokens=p.tokens[start_index:p.pos],
          ),
        )
      }
      Err(e) => {
        // Before the namespace statement, with no `$version` recorded
        // yet, a recovery's skipped run might have swallowed the
        // `$version` line whole (dispatched or not) along with whatever
        // else failed: the version is unknown, not 1.0.
        if namespace is None && p.version is None {
          p.version_unknown = true
        }
        p.diagnostics.push(e.diagnostic())
        p.recover(start_index, cst_statements)
      }
    }
  }
  p.detach_docs_before(p.text_end.next())
  // A tree when a statement was read, or when there was nothing to read:
  // an empty or comment-only file is a valid, empty `IdlFile` with an
  // empty span. `None` only when there were tokens and every statement
  // failed.
  let ast : @ast.IdlFile? = if read_anything || p.tokens.is_empty() {
    let span = if read_anything {
      @span.Offset::zero().to(p.text_end)
    } else {
      @span.Offset::zero().to(@span.Offset::zero())
    }
    Some({
      control: control[:],
      metadata: metadata[:],
      namespace,
      uses: uses[:],
      statements: statements[:],
      span,
    })
  } else {
    None
  }
  {
    ast,
    cst: @cst.IdlCst::new(stream, cst_statements),
    version: p.version,
    diagnostics: order_diagnostics(stream.diagnostics, p.diagnostics[:])[:],
  }
}

///|
/// Every diagnostic by position: a pure function of both lists.
fn order_diagnostics(
  scanner : ArrayView[@diagnostic.Diagnostic],
  parser : ArrayView[@diagnostic.Diagnostic],
) -> Array[@diagnostic.Diagnostic] {
  let all = scanner.to_owned()
  all.append(parser.to_owned())
  let indexed = all.mapi((i, d) => (i, d))
  indexed.sort_by((a, b) => {
    let order = a.1.span.start.compare(b.1.span.start)
    if order == 0 {
      a.0.compare(b.0)
    } else {
      order
    }
  })
  indexed.map(e => e.1)
}

///|
fn statement_cst_kind(s : @ast.Statement) -> (@cst.StatementKind, String?) {
  match s {
    Shape(sh) => (Shape(sh.shape.kind()), Some(sh.shape.name().value))
    Apply(a) => (Apply, Some(a.target.value.to_string()))
  }
}

///|
/// The error for a token that cannot start a statement in `section`.
fn[T] Parser::expected_statement(
  self : Parser,
  section : Section,
  has_namespace : Bool,
) -> T raise ParseError {
  let expected = match section {
    ControlSection =>
      "a control statement (`$version: \"2\"`), `metadata`, or `namespace`"
    MetadataSection => "`metadata` or `namespace`"
    NamespaceSection | UseSection => "`use`, a shape statement, or `apply`"
    ShapeSection => "a shape statement or `apply`"
  }
  let notes = if !has_namespace &&
    (
      self.at_keyword("use") ||
      self.at_keyword("apply") ||
      (
        self.peek() is Some(t) &&
        t.kind == Identifier &&
        @ast.ShapeKind::of(t.lexeme) is Some(_)
      )
    ) {
    ["Shapes, `use` and `apply` can only appear after a `namespace` statement."]
  } else if self.at_keyword("namespace") {
    [
      "A file has one `namespace` statement, and it must come before any `use`, shape or `apply` statement.",
    ]
  } else if self.at_keyword("metadata") ||
    (self.peek() is Some(t) && t.kind == Dollar) {
    [
      "Control statements (`$...`) come first, then `metadata`, then `namespace`.",
    ]
  } else {
    []
  }
  self.fail(
    "SM-PARSE-004",
    "EXPECTED A STATEMENT",
    "I was expecting \{expected} but found \{self.found()}",
    self.here(),
    notes~,
  )
}

///|
/// Parse Smithy IDL source text: a pipeline of the pure scanner and the
/// parser.
pub fn parse(source : @span.SourceText) -> ParseResult {
  source |> @scanner.tokenize |> parse_tokens
}

///|
/// `parse` of a `SourceText` built from `text`.
pub fn parse_text(text : String) -> ParseResult {
  @span.SourceText::new(text) |> parse
}
