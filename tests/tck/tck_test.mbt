///|
/// Cases whose position does not match yet, with the reason. `is_skipped`
/// excuses only the position comparison (and, for a recovery case, the
/// "still yields shapes" clause) - never the "produces at least one
/// error" check, which every invalid and recovery case must pass
/// regardless. Shrink this list; never grow it without a note on beads
/// task smithy-2qe.1.3.
///
/// All of these are EOF position: the reference reports an end-of-file
/// or unterminated-string/text-block diagnostic at a position our
/// parser's own convention does not land on (the raw end-of-file offset,
/// where ours points at the construct's own start; or, for one text
/// block, the position of its opening `"""` rather than of the escape
/// inside it, since Java validates text block escapes after dedenting,
/// losing the original offset). Both parsers detect the error; only the
/// reported line differs.
let skipped : Array[(String, String)] = [
  (
    "invalid/namespace/unclosed-string1.smithy", "EOF position: reference points at the raw EOF, ours at the opening quote",
  ),
  (
    "invalid/namespace/unclosed-string3.smithy", "EOF position: reference points at the raw EOF, ours at the opening quote",
  ),
  (
    "invalid/strings/unclosed-string.smithy", "EOF position: reference points at the raw EOF, ours at the opening quote",
  ),
  (
    "invalid/strings/unclosed-string2.smithy", "EOF position: reference points at the raw EOF, ours at the opening quote",
  ),
  (
    "invalid/strings/unclosed-string3.smithy", "EOF position: reference points at the raw EOF, ours at the opening quote",
  ),
  (
    "invalid/strings/unclosed-text-block.smithy", "EOF position: reference points at the raw EOF, ours at the opening quote",
  ),
  // Java validates text block escapes after dedenting, so it reports an
  // invalid `\u` escape at the opening `"""`, not at the escape itself
  // (our scanner validates escapes in the raw source, so it points at
  // the escape - more precisely, but differently).
  (
    "invalid/strings/text-block-invalid-unicode.smithy", "text block escape position: reference points at the opening \"\"\", ours at the escape",
  ),
  // The one error-recovery case with no shapes at all (it is testing
  // metadata recovery): "still yields shapes" does not apply to it.
  (
    "error-recovery/in-metadata.smithy", "this recovery case has no shapes by design (metadata-only); 'still yields shapes' does not apply",
  ),
]

///|
/// Invalid cases whose error is a loader or validation check (name
/// resolution, mixin application, model validation), with the reason.
/// Their syntax is valid, so the test asserts the opposite of the other
/// invalid cases: they parse with no error at all. A syntax parser that
/// rejected them would be doing the loader's job, and would report false
/// errors on valid multi-file models. This list shrinks when sub-project
/// 4's loader takes these cases over. The parser must continue to accept them;
/// model_test.mbt now checks that model assembly rejects every invalid case.
let semantic : Array[(String, String)] = [
  ("invalid/elision/elide-nonexistent-id.smithy", "member elision resolution"),
  (
    "invalid/elision/elided-property-type-conflicts.smithy", "member elision resolution",
  ),
  ("invalid/elision/elided-type-conflicts.smithy", "member elision resolution"),
  (
    "invalid/elision/for-referencing-non-resource.smithy", "name resolution of the `for` target",
  ),
  ("invalid/enums/enum-with-bad-values.smithy", "enum value validation"),
  ("invalid/enums/enum-without-member.smithy", "member count validation"),
  ("invalid/enums/int-enum-without-member.smithy", "member count validation"),
  ("invalid/enums/intEnum-with-bad-value.smithy", "enum value validation"),
  ("invalid/enums/intEnum-with-float.smithy", "enum value validation"),
  ("invalid/enums/intEnum-with-long.smithy", "enum value validation"),
  ("invalid/lists/list-empty-members.smithy", "member count validation"),
  ("invalid/lists/set-empty-members.smithy", "member count validation"),
  ("invalid/maps/map-empty-members.smithy", "member count validation"),
  (
    "invalid/metadata/space-after-node-array-keyword.smithy", "needs the prelude to resolve a bare shape ID",
  ),
  ("invalid/mixins/member-mixin-conflict-1.smithy", "mixin application"),
  ("invalid/mixins/member-mixin-conflict-2.smithy", "mixin application"),
  ("invalid/mixins/mix-types.smithy", "mixin resolution"),
  (
    "invalid/mixins/mixins-trait-in-explicit-1-0.smithy", "trait resolution of `@mixin`",
  ),
  (
    "invalid/mixins/mixins-trait-in-implicit-1-0.smithy", "trait resolution of `@mixin`",
  ),
  (
    "invalid/mixins/operation-mixin-with-io.smithy", "mixin validation (needs `@mixin` resolved)",
  ),
  (
    "invalid/mixins/resource-mixin-with-properties.smithy", "mixin validation (needs `@mixin` resolved)",
  ),
  ("invalid/use/conflicting-shape-def.smithy", "name resolution"),
  ("invalid/use/conflicting-trait-def.smithy", "name resolution"),
  ("invalid/use/conflicting-use.smithy", "name resolution"),
]

///|
fn is_semantic(path : String) -> Bool {
  semantic.iter().any(s => s.0 == path)
}

///|
fn is_skipped(path : String) -> Bool {
  skipped.iter().any(s => s.0 == path)
}

///|
/// Column conventions that differ from Java. Lines and message facts still
/// apply. Each exception names the construct we underline instead.
let column_differences : Array[(String, String)] = [
  (
    "invalid/control/control-version-defined-twice.smithy", "duplicate key span instead of end of value",
  ),
  (
    "invalid/version/version-set-more-than-once.smithy", "duplicate key span instead of end of value",
  ),
  (
    "invalid/version/unsupported-version.smithy", "whole version string instead of closing quote",
  ),
  (
    "invalid/mixins/with-but-no-ids.smithy", "whole empty mixin clause instead of closing bracket",
  ),
  (
    "invalid/parse-errors/absolute-shape-name.smithy", "whole invalid name instead of its dot",
  ),
  (
    "invalid/parse-errors/shape-name-syntax.smithy", "whole invalid name instead of its dot",
  ),
  (
    "invalid/parse-errors/shape-name-syntax3.smithy", "invalid underscore instead of following space",
  ),
  (
    "invalid/use/use-invalid-namespace.smithy", "missing member after dollar instead of dollar",
  ),
  (
    "invalid/use/use-missing-namespace.smithy", "whole namespace instead of following newline",
  ),
  (
    "invalid/strings/invalid-escape-apostrophe.smithy", "escape span instead of opening quote",
  ),
  (
    "invalid/strings/invalid-escape-space.smithy", "escape span instead of opening quote",
  ),
  (
    "invalid/strings/invalid-unicode-escape.smithy", "escape span instead of opening quote",
  ),
  (
    "invalid/strings/invalid-unicode-escape2.smithy", "escape span instead of opening quote",
  ),
  (
    "invalid/strings/invalid-unicode-escape3.smithy", "escape span instead of opening quote",
  ),
  (
    "invalid/strings/invalid-unicode-escape4.smithy", "escape span instead of opening quote",
  ),
  (
    "invalid/strings/invalid-unicode-escape5.smithy", "escape span instead of opening quote",
  ),
]

///|
fn column_differs(path : String) -> Bool {
  column_differences.iter().any(e => e.0 == path)
}

///|
test "every valid case parses with no error" {
  let failures : Array[String] = []
  for c in @tck.cases() {
    guard c.kind is Valid && !is_skipped(c.path) else { continue }
    let r = @syntax.parse_idl(c.text, name=c.path)
    if r.has_errors() {
      let source = @syntax.SourceText::new(c.text, name=c.path)
      failures.push(@syntax.render_short(r.errors()[0], source))
    }
  }
  @expect.expect(failures).to_equal([])
}

///|
/// Facts shared by Java's token-oriented messages and our construct-oriented
/// prose. Every recognized fact must occur, even when positions are excused.
fn message_facts(path : String, reference : String) -> Array[Array[String]] {
  // These inputs fail at different grammar checks. Compare the shared
  // offending construct rather than the reference's later expectation.
  match path {
    "invalid/parse-errors/absolute-shape-name.smithy" =>
      return [["com.foo#Bam"], ["name"]]
    "invalid/parse-errors/shape-name-syntax.smithy" =>
      return [["Not...Valid"], ["dot"]]
    "invalid/parse-errors/shape-name-syntax3.smithy" =>
      return [["`_`"], ["character"]]
    "invalid/parse-errors/syntax-error-token.smithy" =>
      return [["`!`"], ["character"]]
    "invalid/traits/annotation-unclosed-object1.smithy" =>
      return [["MyString"], ["trait"]]
    "invalid/strings/text-block-invalid-unicode.smithy" =>
      return [["\\u"], ["four hex digits"]]
    "invalid/metadata/invalid-unquoted-shape-id.smithy" =>
      return [["member name"], ["`$`"]]
    "invalid/parse-errors/expected-shape-name-but-eof.smithy" =>
      return [["shape name"], ["end of the file"]]
    _ => ()
  }
  let facts : Array[Array[String]] = []
  for
    (needle, alternatives) in [
      ("line break", ["line break", "same line", "newline"]),
      ("whitespace", ["whitespace", "space"]),
      ("Invalid number", ["number"]),
      ("unicode", ["\\u", "unicode"]),
      ("Invalid escape", ["escape"]),
      ("text block", ["text block", "opening `\"\"\"`"]),
      ("Duplicate control", ["control"]),
      ("Duplicate control", ["Duplicate", "duplicate"]),
      ("statement `version`", ["version"]),
      ("Duplicate operation", ["operation"]),
      ("Duplicate operation", ["Duplicate", "duplicate"]),
      ("operation input", ["input"]),
      ("conflicting member", ["member"]),
      ("conflicting member", ["conflicting", "duplicate"]),
      ("`BAR`", ["`BAR`"]),
      ("Unsupported Smithy version", ["version"]),
      ("number: 999", ["999"]),
      ("version 2 or later", ["version 2", "IDL 2"]),
      ("namespace definition", ["namespace"]),
      ("Traits applied to apply", ["shape", "apply"]),
      ("EOF", ["end of the file", "closing", "unterminated"]),
      ("Expected COLON", ["`:`"]),
      ("Expected LBRACE", ["`{`", "{..."]),
      ("Expected RBRACE", ["`}`"]),
      ("Expected LBRACKET", ["`[`", "[..."]),
      ("Expected RPAREN", ["`)`"]),
      ("Expected EQUAL", ["`=`"]),
      ("Expected IDENTIFIER", ["identifier", "name", "mixin", "statement"]),
      ("Expected SPACE", ["whitespace", "same line", "line break"]),
      ("Expected POUND", ["`#`", "member name after `$`"]),
      ("found NEWLINE", ["line break", "same line", "namespace", "shape name"]),
      ("found COMMENT", ["line break", "same line", "comment"]),
      ("found LPAREN", ["`(`"]),
      ("found POUND", ["`#`"]),
      ("found DOLLAR", ["`$`"]),
      ("found COLON", ["`:`"]),
      ("found EQUAL", ["`=`"]),
      ("found WALRUS", ["`:=`"]),
      ("found DOT", ["`.`", "dot", "namespace"]),
      ("Unexpected character", ["character"]),
      ("one of STRING", ["value", "array"]),
      ("one of LBRACE", ["value"]),
      ("one of RBRACE", ["key"]),
      ("one of IDENTIFIER", ["key"]),
    ] {
    if reference.contains(needle) {
      facts.push(alternatives)
    }
  }
  // The invalid numeric lexeme and unknown character are concrete facts.
  if reference.find("Invalid number '") is Some(i) {
    facts.push([reference[i + 16:].split("':").next().unwrap().to_owned()])
  }
  if reference.find("Unexpected character: '") is Some(i) {
    facts.push([reference[i + 23:i + 24].to_owned()])
  }
  // Unknown type names and found identifier lexemes are facts too.
  if reference.find("Unknown shape type: ") is Some(i) {
    facts.push([reference[i + 20:].split(" | ").next().unwrap().to_owned()])
  }
  if reference.find("found IDENTIFIER('") is Some(i) {
    facts.push([reference[i + 18:].split("')").next().unwrap().to_owned()])
  }
  facts
}

///|
test "every invalid case matches reference positions and message facts" {
  let failures : Array[String] = []
  for c in @tck.cases() {
    guard c.kind is Invalid(line~, column~, message~) else { continue }
    let source = @syntax.SourceText::new(c.text, name=c.path)
    let r = @syntax.parse(source)
    let errs = r.errors()
    // A loader-level case has valid syntax: it must parse clean.
    if is_semantic(c.path) {
      if errs.length() > 0 {
        let rendered = @syntax.render_short(errs[0], source)
        failures.push(
          "\{c.path}: listed as semantic but has a syntax error: \{rendered}",
        )
      }
      continue
    }
    // Every other invalid case must produce at least one error, skipped
    // or not: `skipped` excuses a reporting-convention difference, never
    // a silent false negative.
    if errs.length() == 0 {
      failures.push(
        "\{c.path}: expected an error at \{line}:\{column} (\{message}) but parsed clean",
      )
      continue
    }
    if !message.is_empty() {
      let d = errs[0]
      let prose = d.message +
        " " +
        d.notes.join(" ") +
        " " +
        d.hint.unwrap_or("") +
        " " +
        d.example.unwrap_or("")
      let facts = message_facts(c.path, message)
      if facts.is_empty() {
        failures.push("\{c.path}: no reference facts extracted from \{message}")
      }
      for alternatives in facts {
        if !alternatives.iter().any(fact => prose.contains(fact)) {
          failures.push(
            "\{c.path}: reference fact \{alternatives.join(" or ")} absent from \{prose}",
          )
        }
      }
    }
    // Semantic cases (line 0) only need some error; syntax cases must match
    // the line and column, unless skipped (a known position-reporting difference).
    if line > 0 && !is_skipped(c.path) {
      let p = source.position(errs[0].span.start)
      if p.line.0 != line ||
        (column > 0 && !column_differs(c.path) && p.column.0 != column) {
        let rendered = @syntax.render_short(errs[0], source)
        failures.push(
          "\{c.path}: expected position \{line}:\{column} (\{message}) but got \{rendered}",
        )
      }
    }
  }
  @expect.expect(failures).to_equal([])
}

///|
test "every recovery case reports at least one error and still yields shapes" {
  let failures : Array[String] = []
  for c in @tck.cases() {
    guard c.kind is Recovery else { continue }
    let r = @syntax.parse_idl(c.text, name=c.path)
    guard r.ast is Some(f) else {
      failures.push("\{c.path}: no ast")
      continue
    }
    // Every recovery case must report at least one error, skipped or not;
    // only the "still yields shapes" clause can be excused (one case has
    // no shapes at all, by design).
    if !r.has_errors() {
      failures.push(
        "\{c.path}: errors=\{r.errors().length()} shapes=\{f.shapes().length()}",
      )
      continue
    }
    if f.shapes().length() == 0 && !is_skipped(c.path) {
      failures.push(
        "\{c.path}: errors=\{r.errors().length()} shapes=\{f.shapes().length()}",
      )
    }
  }
  @expect.expect(failures).to_equal([])
}

///|
test "the CST is lossless on every case" {
  for c in @tck.cases() {
    let r = @syntax.parse_idl(c.text)
    @expect.expect(r.cst.to_source() == c.text).because(c.path).to_be_true()
  }
}
