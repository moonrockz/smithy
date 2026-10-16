///|
/// Cases whose line does not match yet, with the reason. `is_skipped`
/// excuses only the line comparison (and, for a recovery case, the
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
/// The one invalid case that genuinely cannot produce any diagnostic
/// without data a syntax parser does not have: resolving a bare
/// identifier as a shape ID against the prelude's shape list. (Faking a
/// signal here - say, flagging every unqualified identifier that is not
/// `true`/`false`/`null` - would risk false positives on every other
/// case that legitimately references a shape by a bare name.) Unlike
/// `skipped`, this also excuses the "produces at least one error" check:
/// there is, deliberately, nothing to report.
let needs_prelude : Array[String] = [
  "invalid/metadata/space-after-node-array-keyword.smithy",
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
    guard c.kind is Invalid(line~, column~, message~) else { continue }
    let source = @syntax.SourceText::new(c.text, name=c.path)
    let r = @syntax.parse(source)
    let errs = r.errors()
    // Every invalid case must produce at least one error, skipped or
    // not: `skipped` excuses a reporting-convention difference, never a
    // silent false negative. `needs_prelude` is the one narrower,
    // explicit exception: a case that provably needs data (the prelude)
    // no syntax parser has.
    if errs.length() == 0 && !needs_prelude.contains(c.path) {
      failures.push(
        "\{c.path}: expected an error at \{line}:\{column} (\{message}) but parsed clean",
      )
      continue
    }
    // Semantic cases (line 0) only need some error; syntax cases must match
    // the line, unless skipped (a known position-reporting difference).
    // `errs.length() > 0` guards the `needs_prelude` case above, which
    // reaches here with no errors at all.
    if line > 0 && !is_skipped(c.path) && errs.length() > 0 {
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
