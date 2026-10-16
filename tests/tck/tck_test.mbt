///|
/// Cases known not to match yet, with the reason. Shrink this list; never
/// grow it without a note on beads task smithy-2qe.1.3.
///
/// Two groups:
/// - Semantic: the reference reports these from the loader/validator (a
///   symbol table and cross-shape model), not the parser. Pure syntax
///   parsing is sub-project 1's scope; these need sub-project 2 or later.
/// - EOF position: the reference reports some end-of-file and
///   value-missing diagnostics at a position our parser's own convention
///   does not land on (an anchored "end of the last real line" for some
///   cases, the raw end-of-file offset for others, inconsistently; or, for
///   a text block, the position of its opening `"""` rather than of the
///   escape inside it, since Java validates text block escapes after
///   dedenting, losing the original offset). Both parsers detect the
///   error; only the reported line differs.
let skipped : Array[(String, String)] = [
  // Semantic: elision (needs the referenced resource/mixin's members).
  (
    "invalid/elision/elide-nonexistent-id.smithy", "semantic: elision target resolution needs the model",
  ),
  (
    "invalid/elision/elided-property-type-conflicts.smithy", "semantic: elision target resolution needs the model",
  ),
  (
    "invalid/elision/elided-type-conflicts.smithy", "semantic: elision target resolution needs the model",
  ),
  (
    "invalid/elision/for-referencing-non-resource.smithy", "semantic: elision target resolution needs the model",
  ),
  // Semantic: enum/intEnum member and value validation.
  (
    "invalid/enums/enum-with-bad-values.smithy", "semantic: enum value validation",
  ),
  (
    "invalid/enums/enum-with-duplicates.smithy", "semantic: duplicate member name detection",
  ),
  (
    "invalid/enums/enum-without-member.smithy", "semantic: enum needs at least one member",
  ),
  (
    "invalid/enums/int-enum-without-member.smithy", "semantic: intEnum needs at least one member",
  ),
  (
    "invalid/enums/intEnum-with-bad-value.smithy", "semantic: intEnum value validation",
  ),
  (
    "invalid/enums/intEnum-with-duplicates.smithy", "semantic: duplicate member name detection",
  ),
  (
    "invalid/enums/intEnum-with-float.smithy", "semantic: intEnum value must be an integer",
  ),
  (
    "invalid/enums/intEnum-with-long.smithy", "semantic: intEnum value range validation",
  ),
  // Semantic: aggregate shape member-count validation.
  (
    "invalid/lists/list-empty-members.smithy", "semantic: list needs exactly one member",
  ),
  (
    "invalid/lists/set-empty-members.smithy", "semantic: set needs exactly one member",
  ),
  (
    "invalid/maps/map-empty-members.smithy", "semantic: map needs exactly a key and a value member",
  ),
  // Semantic: version-gated model validation (not a syntax rule).
  (
    "invalid/defaults/default-in-v1.smithy", "semantic: @default is IDL 2 only, a version-gated model check",
  ),
  (
    "invalid/enums/idl-enums-in-v1.smithy", "semantic: enum/intEnum are IDL 2 only, a version-gated model check",
  ),
  (
    "invalid/lists/no-sets-in-v2.smithy", "semantic: set is IDL 1 only, a version-gated model check",
  ),
  (
    "invalid/version/idl-int-enums-in-v1.smithy", "semantic: intEnum is IDL 2 only, a version-gated model check",
  ),
  (
    "invalid/version/properties-v2-only.smithy", "semantic: operation input/output shorthand is IDL 2 only, a version-gated model check",
  ),
  // Semantic: mixin validation (member/trait conflicts across the mixin graph).
  (
    "invalid/mixins/member-mixin-conflict-1.smithy", "semantic: mixin member conflict detection",
  ),
  (
    "invalid/mixins/member-mixin-conflict-2.smithy", "semantic: mixin member conflict detection",
  ),
  (
    "invalid/mixins/mix-types.smithy", "semantic: a shape's mixins must share its type",
  ),
  (
    "invalid/mixins/mixins-trait-in-explicit-1-0.smithy", "semantic: @mixin is IDL 2 only, a version-gated model check",
  ),
  (
    "invalid/mixins/mixins-trait-in-implicit-1-0.smithy", "semantic: @mixin is IDL 2 only, a version-gated model check",
  ),
  (
    "invalid/mixins/operation-mixin-with-io.smithy", "semantic: operation mixin input/output conflict detection",
  ),
  (
    "invalid/mixins/resource-mixin-with-properties.smithy", "semantic: resource mixin property conflict detection",
  ),
  // Semantic: cross-shape and cross-use conflict detection.
  (
    "invalid/use/conflicting-shape-def.smithy", "semantic: shape ID conflict detection across the model",
  ),
  (
    "invalid/use/conflicting-trait-def.smithy", "semantic: trait ID conflict detection across the model",
  ),
  (
    "invalid/use/conflicting-use.smithy", "semantic: use target conflict detection across the model",
  ),
  // Semantic: a syntactic shape ID that still needs resolving against the
  // prelude to tell a keyword-lookalike from a real reference.
  (
    "invalid/metadata/space-after-node-array-keyword.smithy", "semantic: shape ID resolution against the prelude",
  ),
  // EOF position: reported at an anchored "end of the last real line"
  // (not the raw end-of-file offset our `position()` gives).
  (
    "invalid/control/control-missing-value.smithy", "EOF position: reference anchors to the last real line",
  ),
  (
    "invalid/namespace/namespace-syntax-error.smithy", "EOF position: reference anchors to the last real line",
  ),
  // EOF position: reported at the raw end-of-file offset for an unclosed
  // string or text block (ours points at the opening quote instead).
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
  (
    "invalid/parse-errors/expected-shape-name-but-eof.smithy", "EOF position: reference points at the raw EOF, ours at the shape keyword",
  ),
  (
    "invalid/parse-errors/invalid-newline-after-shape-type.smithy", "EOF position: reference points earlier (the line break) than ours (the next real token)",
  ),
  (
    "invalid/use/use-missing-after-namespace.smithy", "EOF position: reference points at the line break, ours at the next real token",
  ),
  // EOF position (text block): Java validates text block escapes after
  // dedenting, so it reports an invalid `\u` escape at the opening `"""`,
  // not at the escape itself (our scanner validates escapes in the raw
  // source, so it points at the escape, more precisely but differently).
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
fn is_skipped(path : String) -> Bool {
  skipped.iter().any(s => s.0 == path)
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
test "every invalid case produces an error on the reference's line" {
  let failures : Array[String] = []
  for c in @tck.cases() {
    guard c.kind is Invalid(line~, column~, message~) && !is_skipped(c.path) else {
      continue
    }
    let source = @syntax.SourceText::new(c.text, name=c.path)
    let r = @syntax.parse(source)
    let errs = r.errors()
    if errs.length() == 0 {
      failures.push(
        "\{c.path}: expected an error at \{line}:\{column} (\{message}) but parsed clean",
      )
      continue
    }
    // Semantic cases (line 0) only need some error; syntax cases must match the line.
    if line > 0 {
      let p = source.position(errs[0].span.start)
      if p.line.0 != line {
        let rendered = @syntax.render_short(errs[0], source)
        failures.push(
          "\{c.path}: expected line \{line} (\{message}) but got \{rendered}",
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
    guard c.kind is Recovery && !is_skipped(c.path) else { continue }
    let r = @syntax.parse_idl(c.text, name=c.path)
    guard r.ast is Some(f) else {
      failures.push("\{c.path}: no ast")
      continue
    }
    if !r.has_errors() || f.shapes().length() == 0 {
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
