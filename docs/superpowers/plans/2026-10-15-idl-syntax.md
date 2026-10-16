# Smithy IDL Syntax Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new module `moonrockz/smithy-syntax` that scans and parses Smithy IDL 2.0 text into a typed AST with spans, a lossless CST, and Elm/Rust style diagnostics, with recovery per statement and a vendored reference corpus proving parity.

**Architecture:** The scanner is a pipeline of pure functions: `scan_at(text, offset)` returns one `Step` (a token or a trivia piece, where the next one starts, and an optional diagnostic), `scan_pieces` unfolds it over the text, and `attach_trivia` groups the pieces into tokens. The parser exposes a pure contract (`parse(SourceText) -> ParseResult`); inside one call a private cursor advances over the token view, and every result, diagnostic and CST group comes back as a value. Packages depend one way: `span` ← `diagnostic` ← `scanner` ← `ast` ← `cst` ← `parser` ← `report` ← root facade.

**Tech Stack:** MoonBit 0.10.15 (moon, moonx), `moonbitlang/core` (bigint, quickcheck, debug, strconv), `moonbitlang/x@0.5.5` (decimal), `moonrockz/expect@0.6.1` (test assertions), mise tasks, beads for tracking (epic `smithy-2qe.1`).

**Spec:** `docs/superpowers/specs/2026-10-15-idl-syntax-design.md`

## Global Constraints

- Module path `pkgs/smithy-syntax`, module name `moonrockz/smithy-syntax`, version `0.1.0`, `source = "src"`, license Apache-2.0, `warnings = "-implicit_impl_as_method"` in `moon.mod` (the derive promotion warning of this toolchain).
- No primitive obsession for positions: text positions are `@span.Offset` (a UTF-16 unit index, never negative), counts are `@span.Length` (never negative), lines and columns are `@span.Line` and `@span.Column` (1-based, never zero), nesting is `@parser.Depth`. A raw `Int` is used only for array indexes and loop counters that never leave a function. Newtypes are `pub struct X(Int)` (read-only outside their package) with validating constructors.
- Functional style: public functions are pure (a value in, a value out, no hidden state). Mutation is allowed only for local accumulators and the parser's private cursor inside one `parse` call. Diagnostics are returned as values, never pushed into shared state across functions. Linear multi-stage flows are written as `|>` pipelines.
- Text output goes through core's `Logger` trait (`&Logger`), the sink that `StringBuilder`, `@buffer.Buffer` and `Show::output` share; a renderer never holds a concrete `StringBuilder` in its API. The async `@io.Writer` of `moonbitlang/async` is byte-oriented and belongs to the CLI boundary (sub-project 5), which writes rendered strings to it.
- Every value type with an invariant (`Offset`, `Length`, `Line`, `Column`, `Span`, `Depth`) has quickcheck laws beside its unit tests, in a `*_law_test.mbt` file.
- Three test layers: unit and law tests inside `pkgs/smithy-syntax` (every target), the compatibility kit (TCK) parity tests in `tests/tck`, and acceptance features in Gherkin (`tests/features/*.feature`) run by `moonrockz/moonspec@0.11.0` from `tests/bdd`. The tests module depends on `moonbitlang/async`, which supports js and native, so `mise run test` runs the tests module on those two targets only; the library runs on all four.
- LF and CRLF are line breaks; a lone CR is not.
- Every AST node has `span`; every list field is `ArrayView[T]`; every public type derives `Eq, Debug`. `derive(Show)` is deprecated on this toolchain: write `impl Show` by hand where a type needs it.
- Diagnostic codes are `SM-SCAN-001`..`SM-SCAN-007` and `SM-PARSE-001`..`SM-PARSE-011`, exactly as listed in Task 3; a test checks the table against what is emitted.
- The parser never panics and never raises out of `parse`; `max_nesting` is `Depth(100)`.
- Lossless: `TokenStream::to_source()` and `IdlCst::to_source()` equal the input text, with and without errors.
- Commits use Conventional Commits, plain English, no AI attribution lines (AGENTS.md). Run `mise run format` before each commit; the pre-commit hook runs `moon fmt --check` and `moon check --deny-warn`.
- Build and test from the workspace root: `moon check`, `moon test`, `moon test --target js|wasm|wasm-gc|native`. On this ARM64 Windows machine, `.config/mise/config.local.toml` (gitignored) disables the pinned `http:moonbit` and uses `~/.moon/bin`; if `mise run` fails with "No URL for platform windows-arm64", recreate that file (see Task 1 step 1).
- Every public function and type has a `///|` doc comment; package READMEs are `README.mbt.md` with ` ```mbt check ` blocks that `moon test` runs.
- Messages are in Elm's voice: first person, what I was parsing, what I saw, what I expected. Never "syntax error" alone.
- Test inputs and expected outputs that span lines are written as MoonBit multiline literals (`#|` lines, parenthesized; `$|` lines when the text interpolates), never as `"...\n..."` strings. The exceptions are texts whose point is an invisible character (CRLF, a lone CR, a tab, a unicode escape), which stay escaped so the character is visible in the source.

## Review Focus

1. **CRLF files.** A Windows-authored model (`\r\n`) must scan, parse, and `to_source` byte for byte, with `MISSING LINE BREAK` never reported between two statements separated by CRLF. Tests in Task 4 (scanner) and Task 9 (BR rule).
2. **Text block edge cases.** A text block whose closing `"""` is on its own line, one whose last line has only spaces, and one with a `\` line continuation must decode exactly as the spec's algorithm says. Tests in Task 5.
3. **Adjacent-token shape IDs.** `foo . bar#Baz` (spaces around the dot) is not a shape ID; `string com.foo#Bam` is the reference's parse error at the dot. Tests in Task 11.
4. **Deep nesting on wasm.** A trait with 150 nested arrays must produce `TOO MUCH NESTING`, not a stack overflow, on the wasm target. Test in Task 10, run with `--target wasm-gc`.
5. **Recovery does not swallow the next statement.** A broken structure followed by a valid `string Foo` must yield one error and still produce `Foo` in the AST, also when the broken shape's brace is unclosed. Tests in Task 12.

---

### Task 1: Module scaffold `pkgs/smithy-syntax`

**Files:**
- Create: `pkgs/smithy-syntax/moon.mod`
- Create: `pkgs/smithy-syntax/src/moon.pkg`
- Create: `pkgs/smithy-syntax/src/lib.mbt`
- Create: `pkgs/smithy-syntax/src/lib_test.mbt`
- Create: `pkgs/smithy-syntax/README.mbt.md`
- Create: `pkgs/smithy-syntax/README.md`
- Modify: `moon.work`
- Modify: `README.md` (package table)

**Interfaces:**
- Produces: `@syntax.version() -> String` returning `"0.1.0"`.

- [ ] **Step 1: Make sure the toolchain runs through mise on this machine**

Run: `mise run validate`
If it fails with `No URL for platform windows-arm64`, write `.config/mise/config.local.toml`:

```toml
# Local overrides for this ARM64 Windows machine (gitignored). The pinned http:moonbit has no
# windows-arm64 archive; use the official install in ~/.moon/bin, which is the same moonc version.
[settings]
disable_tools = ["http:moonbit"]

[env]
_.path = ["~/.moon/bin"]
```

Then run `mise trust`, `moon update`, and `mise run validate` again. Expected: `✅ All package configurations valid`.

- [ ] **Step 2: Create the module manifest**

`pkgs/smithy-syntax/moon.mod`:

```toml
name = "moonrockz/smithy-syntax"

version = "0.1.0"

description = "Smithy IDL syntax for MoonBit: lossless scanner, typed AST, CST, parser and diagnostics"

repository = "https://github.com/moonrockz/smithy"

license = "Apache-2.0"

keywords = [ "smithy", "idl", "parser", "ast", "moonbit" ]

readme = "README.mbt.md"

source = "src"

warnings = "-implicit_impl_as_method"

import {
  "moonbitlang/x@0.5.5",
  "moonrockz/expect@0.6.1",
}
```

- [ ] **Step 3: Create the root package and its version test**

`pkgs/smithy-syntax/src/moon.pkg`:

```
import {
}

import {
  "moonrockz/smithy-syntax" @syntax,
} for "test"
```

`pkgs/smithy-syntax/src/lib.mbt`:

```moonbit
///|
/// The version of smithy-syntax, the same as `version` in `moon.mod`.
pub fn version() -> String {
  "0.1.0"
}
```

`pkgs/smithy-syntax/src/lib_test.mbt`:

```moonbit
///|
test "the module reports its version" {
  inspect(@syntax.version(), content="0.1.0")
}
```

- [ ] **Step 4: Add the workspace member and run the test to see it pass**

`moon.work`:

```
members = [
  ".",
  "./pkgs/smithy",
  "./pkgs/smithy-syntax",
  "./apps/smithy",
]
```

Run: `moon test` (from the workspace root)
Expected: `Total tests: 2, passed: 2, failed: 0.`

- [ ] **Step 5: Write the READMEs and update the root package table**

`pkgs/smithy-syntax/README.mbt.md`:

````markdown
# moonrockz/smithy-syntax

Smithy IDL syntax for MoonBit: a lossless scanner, a typed AST with spans, a
CST that prints the source back byte for byte, a parser with recovery per
statement, and diagnostics in the style of Elm and Rust.

```mbt check
test {
  inspect(@syntax.version(), content="0.1.0")
}
```

Packages: `span`, `diagnostic`, `scanner`, `ast`, `cst`, `parser`, `report`
and the root facade. See the design in
`docs/superpowers/specs/2026-10-15-idl-syntax-design.md`.
````

`pkgs/smithy-syntax/README.md`:

```markdown
# moonrockz/smithy-syntax

Smithy IDL syntax for MoonBit. See [README.mbt.md](README.mbt.md).
```

In the root `README.md` package table add the row:

```
| `pkgs/smithy-syntax` | `moonrockz/smithy-syntax` | Smithy IDL scanner, AST, CST, parser and diagnostics |
```

and in the Layout tree add `├── pkgs/smithy-syntax/        # IDL syntax (moonrockz/smithy-syntax)`.

- [ ] **Step 6: Validate, lint, format and commit**

Run: `mise run format && mise run lint && mise run validate && moon test`
Expected: all green, 3 tests (the README check block counts).

```bash
git add moon.work README.md pkgs/smithy-syntax
git commit -m "feat(syntax): scaffold the moonrockz/smithy-syntax module"
```

---

### Task 2: `span` package: typed offsets, spans, positions and source text

**Files:**
- Create: `pkgs/smithy-syntax/src/span/moon.pkg`
- Create: `pkgs/smithy-syntax/src/span/units.mbt`
- Create: `pkgs/smithy-syntax/src/span/span.mbt`
- Create: `pkgs/smithy-syntax/src/span/source_text.mbt`
- Create: `pkgs/smithy-syntax/src/span/units_test.mbt`
- Create: `pkgs/smithy-syntax/src/span/span_test.mbt`
- Create: `pkgs/smithy-syntax/src/span/source_text_test.mbt`
- Create: `pkgs/smithy-syntax/src/span/span_law_test.mbt`
- Create: `pkgs/smithy-syntax/src/span/README.mbt.md`

**Interfaces:**
- Produces: `Offset(Int)` read-only, with `Offset::new(Int) -> Offset?`, `zero()`, `advance(Length) -> Offset`, `next() -> Offset`, `distance(Offset) -> Length`, `to(Offset) -> Span`, `Compare`; `Length(Int)` read-only, with `Length::new(Int) -> Length?`, `zero()`, `one()`, `of_string(String) -> Length`, `+` (`Add`), `Compare`; `Line(Int)` and `Column(Int)` read-only, with `::new(Int) -> X?`, `first()`, `next()`, `Compare`; `Span { start : Offset, length : Length }` with `Span::new(start, length)`, `end()`, `contains(Offset)`, `is_empty()`, `join(Span)`; `Position { line, column }` with `Position::new`; `SourceText` with `SourceText::new(text, name?)`, `text()`, `name()`, `end() -> Offset`, `line_count() -> Int`, `position(Offset) -> Position`, `line_span(Line) -> Span?`, `line_text(Line) -> String?`, `slice(Span) -> String`.

- [ ] **Step 1: Write the failing unit-type tests**

`span/moon.pkg`:

```
import {
}

import {
  "moonrockz/smithy-syntax/span",
  "moonrockz/expect",
  "moonbitlang/core/debug",
  "moonbitlang/core/quickcheck",
  "moonbitlang/core/quickcheck/splitmix",
} for "test"
```

`span/units_test.mbt`:

```moonbit
///|
fn off(n : Int) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(o) else { fail("bad offset \{n}") }
  o
}

///|
fn len(n : Int) -> @span.Length raise {
  guard @span.Length::new(n) is Some(l) else { fail("bad length \{n}") }
  l
}

///|
test "offsets and lengths are never negative" {
  inspect(@span.Offset::new(-1), content="None")
  inspect(@span.Length::new(-1), content="None")
  inspect(@span.Offset::new(0).map(o => o.0), content="Some(0)")
  inspect(@span.Line::new(0), content="None")
  inspect(@span.Column::new(0), content="None")
  inspect(@span.Line::first().0, content="1")
}

///|
test "offset arithmetic" {
  @expect.expect_all(e => {
    e.expect(off(3).advance(len(4))).to_equal(off(7))
    e.expect(off(3).next()).to_equal(off(4))
    e.expect(off(3).distance(off(10))).to_equal(len(7))
    e.expect(off(10).distance(off(3))).to_equal(len(7))
    e.expect(len(2) + len(3)).to_equal(len(5))
    e.expect(off(2) < off(3)).to_be_true()
    e.expect(@span.Length::of_string("héllo")).to_equal(len(5))
  })
}

///|
test "lines and columns step" {
  inspect(@span.Line::first().next().0, content="2")
  inspect(@span.Column::first().next().0, content="2")
}
```

- [ ] **Step 2: Implement units.mbt**

```moonbit
///|
/// A UTF-16 unit index into a source text. Never negative: `Offset::new`
/// is the only way in from an `Int`.
pub struct Offset(Int) derive(Eq, Compare, Hash, Debug)

///|
pub fn Offset::new(n : Int) -> Offset? {
  if n < 0 {
    None
  } else {
    Some(Offset(n))
  }
}

///|
pub fn Offset::zero() -> Offset {
  Offset(0)
}

///|
/// `Add` is homogeneous in MoonBit, so stepping an offset by a length is a
/// named method.
pub fn Offset::advance(self : Offset, by : Length) -> Offset {
  Offset(self.0 + by.0)
}

///|
pub fn Offset::next(self : Offset) -> Offset {
  Offset(self.0 + 1)
}

///|
/// The number of units between two offsets, in either order.
pub fn Offset::distance(self : Offset, other : Offset) -> Length {
  if other.0 >= self.0 {
    Length(other.0 - self.0)
  } else {
    Length(self.0 - other.0)
  }
}

///|
/// The span from `self` to `end`, ordered either way.
pub fn Offset::to(self : Offset, end : Offset) -> Span {
  if end.0 >= self.0 {
    { start: self, length: Length(end.0 - self.0) }
  } else {
    { start: end, length: Length(self.0 - end.0) }
  }
}

///|
/// A count of UTF-16 units. Never negative.
pub struct Length(Int) derive(Eq, Compare, Hash, Debug)

///|
pub fn Length::new(n : Int) -> Length? {
  if n < 0 {
    None
  } else {
    Some(Length(n))
  }
}

///|
pub fn Length::zero() -> Length {
  Length(0)
}

///|
pub fn Length::one() -> Length {
  Length(1)
}

///|
/// The length of a string in UTF-16 units.
pub fn Length::of_string(s : String) -> Length {
  Length(s.length())
}

///|
pub impl Add for Length with add(a, b) {
  Length(a.0 + b.0)
}

///|
/// A 1-based line number.
pub struct Line(Int) derive(Eq, Compare, Hash, Debug)

///|
pub fn Line::new(n : Int) -> Line? {
  if n < 1 {
    None
  } else {
    Some(Line(n))
  }
}

///|
pub fn Line::first() -> Line {
  Line(1)
}

///|
pub fn Line::next(self : Line) -> Line {
  Line(self.0 + 1)
}

///|
/// A 1-based column, counting UTF-16 units as the Java reference does.
pub struct Column(Int) derive(Eq, Compare, Hash, Debug)

///|
pub fn Column::new(n : Int) -> Column? {
  if n < 1 {
    None
  } else {
    Some(Column(n))
  }
}

///|
pub fn Column::first() -> Column {
  Column(1)
}

///|
pub fn Column::next(self : Column) -> Column {
  Column(self.0 + 1)
}
```

- [ ] **Step 3: Write the failing span and position tests**

`span/span_test.mbt`:

```moonbit
///|
fn o(n : Int) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(x) else { fail("bad offset \{n}") }
  x
}

///|
test "a span is a start and a length, half open" {
  let s = o(2).to(o(5))
  @expect.expect_all(e => {
    e.expect(s.start).to_equal(o(2))
    e.expect(s.end()).to_equal(o(5))
    e.expect(s.contains(o(2))).to_be_true()
    e.expect(s.contains(o(4))).to_be_true()
    e.expect(s.contains(o(5))).to_be_false()
    e.expect(o(3).to(o(3)).is_empty()).to_be_true()
    e.expect(o(5).to(o(2))).to_equal(s)
  })
  debug_inspect(s, content="{ start: Offset(2), length: Length(3) }")
}

///|
test "join covers both spans" {
  let a = o(2).to(o(5))
  let b = o(9).to(o(12))
  @expect.expect(a.join(b)).to_equal(o(2).to(o(12)))
  @expect.expect(b.join(a)).to_equal(o(2).to(o(12)))
}

///|
test "positions compare and print" {
  let p = @span.Position::new(@span.Line::first().next(), @span.Column::first())
  debug_inspect(p, content="{ line: Line(2), column: Column(1) }")
}
```

- [ ] **Step 4: Implement span.mbt**

```moonbit
///|
/// A half-open range of a source text: `start` included, `length` units.
/// Built from a length, so the end never precedes the start.
pub(all) struct Span {
  start : Offset
  length : Length
} derive(Eq, Debug, Hash)

///|
pub fn Span::new(start : Offset, length : Length) -> Span {
  { start, length }
}

///|
pub fn Span::end(self : Span) -> Offset {
  self.start.advance(self.length)
}

///|
pub fn Span::contains(self : Span, offset : Offset) -> Bool {
  self.start <= offset && offset < self.end()
}

///|
pub fn Span::is_empty(self : Span) -> Bool {
  self.length == Length::zero()
}

///|
/// The smallest span that covers both.
pub fn Span::join(self : Span, other : Span) -> Span {
  let start = if self.start < other.start { self.start } else { other.start }
  let end = if self.end() > other.end() { self.end() } else { other.end() }
  start.to(end)
}

///|
/// A 1-based line and column.
pub(all) struct Position {
  line : Line
  column : Column
} derive(Eq, Debug, Hash)

///|
pub fn Position::new(line : Line, column : Column) -> Position {
  { line, column }
}
```

- [ ] **Step 5: Write the failing SourceText tests**

`span/source_text_test.mbt`:

```moonbit
///|
fn at(n : Int) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(x) else { fail("bad offset \{n}") }
  x
}

///|
fn pos(line : Int, column : Int) -> @span.Position raise {
  guard @span.Line::new(line) is Some(l) && @span.Column::new(column) is Some(c) else {
    fail("bad position")
  }
  @span.Position::new(l, c)
}

///|
test "positions are 1-based and count UTF-16 units" {
  let st = @span.SourceText::new("ab\ncd\r\nef")
  @expect.expect_all(e => {
    e.expect(st.line_count()).to_equal(3)
    e.expect(st.position(at(0))).to_equal(pos(1, 1))
    e.expect(st.position(at(2))).to_equal(pos(1, 3))
    e.expect(st.position(at(3))).to_equal(pos(2, 1))
    e.expect(st.position(at(7))).to_equal(pos(3, 1))
    // Past the end clamps to the end of the last line.
    e.expect(st.position(at(99))).to_equal(pos(3, 3))
    e.expect(st.end()).to_equal(at(9))
  })
}

///|
test "a lone CR is not a line break" {
  let st = @span.SourceText::new("a\rb\nc")
  inspect(st.line_count(), content="2")
  inspect(st.position(at(2)).line.0, content="1")
}

///|
test "line_text strips the line break" {
  let st = @span.SourceText::new("ab\ncd\r\nef")
  let l = (n : Int) => @span.Line::new(n).unwrap()
  @expect.expect_all(e => {
    e.expect(st.line_text(l(1))).to_equal(Some("ab"))
    e.expect(st.line_text(l(2))).to_equal(Some("cd"))
    e.expect(st.line_text(l(3))).to_equal(Some("ef"))
    e.expect(st.line_text(l(4))).to_equal(None)
    e.expect(st.line_span(l(2))).to_equal(Some(at(3).to(at(5))))
    e.expect(st.slice(at(3).to(at(5)))).to_equal("cd")
  })
}

///|
test "a surrogate pair is two columns, as the reference counts" {
  let st = @span.SourceText::new("\u{1F600}x")
  inspect(st.position(at(2)).column.0, content="3")
}

///|
test "name is optional" {
  inspect(@span.SourceText::new("", name="a.smithy").name(), content="Some(\"a.smithy\")")
  inspect(@span.SourceText::new("").name(), content="None")
}
```

- [ ] **Step 6: Implement source_text.mbt**

```moonbit
///|
/// A source text with its line table. The table is built once; every
/// lookup is a pure function of it.
pub struct SourceText {
  priv text : String
  priv name : String?
  /// The offset of the first unit of each line; `line_starts[0] == 0`.
  priv line_starts : Array[Int]
}

///|
/// LF and CRLF end a line; a lone CR does not.
pub fn SourceText::new(text : String, name? : String) -> SourceText {
  let line_starts = [0]
  for i in 0..<text.length() {
    if text.code_unit_at(i).to_int() == '\n'.to_int() {
      line_starts.push(i + 1)
    }
  }
  { text, name, line_starts }
}

///|
pub fn SourceText::text(self : SourceText) -> String {
  self.text
}

///|
pub fn SourceText::name(self : SourceText) -> String? {
  self.name
}

///|
/// The offset just past the last unit.
pub fn SourceText::end(self : SourceText) -> Offset {
  Offset(self.text.length())
}

///|
/// One more than the number of line breaks.
pub fn SourceText::line_count(self : SourceText) -> Int {
  self.line_starts.length()
}

///|
/// The 0-based index of the line that holds `unit` (clamped to the text).
fn SourceText::line_index(self : SourceText, unit : Int) -> Int {
  let mut lo = 0
  let mut hi = self.line_starts.length() - 1
  while lo < hi {
    let mid = lo + (hi - lo + 1) / 2
    if self.line_starts[mid] <= unit {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  lo
}

///|
/// The line and column of `offset`. An offset past the end is the position
/// just after the last unit.
pub fn SourceText::position(self : SourceText, offset : Offset) -> Position {
  let unit = if offset.0 > self.text.length() { self.text.length() } else { offset.0 }
  let line = self.line_index(unit)
  Position::new(Line(line + 1), Column(unit - self.line_starts[line] + 1))
}

///|
/// The span of a line without its line break; `None` past the last line.
pub fn SourceText::line_span(self : SourceText, line : Line) -> Span? {
  guard line.0 <= self.line_starts.length() else { return None }
  let start = self.line_starts[line.0 - 1]
  let mut end = if line.0 < self.line_starts.length() {
    self.line_starts[line.0]
  } else {
    self.text.length()
  }
  if end > start && self.text.code_unit_at(end - 1).to_int() == '\n'.to_int() {
    end -= 1
  }
  if end > start && self.text.code_unit_at(end - 1).to_int() == '\r'.to_int() {
    end -= 1
  }
  Some(Offset(start).to(Offset(end)))
}

///|
/// The text of a line, without its line break.
pub fn SourceText::line_text(self : SourceText, line : Line) -> String? {
  self.line_span(line).map(s => self.slice(s))
}

///|
/// The text of `span`, clamped to the text.
pub fn SourceText::slice(self : SourceText, span : Span) -> String {
  let n = self.text.length()
  let a = if span.start.0 > n { n } else { span.start.0 }
  let b = if span.end().0 > n { n } else { span.end().0 }
  self.text.unsafe_substring(start=a, end=b)
}
```

- [ ] **Step 7: Write the laws for the unit types and the source text**

`span/span_law_test.mbt`. The generators live in this test file so the package has no test dependency on `lawkit` (Task 6), which depends on `span`.

```moonbit
///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// A random non-negative offset, at most 1000.
pub(all) struct AnyOffset(@span.Offset) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for AnyOffset with fn arbitrary(_size, rs) {
  AnyOffset(@span.Offset::new(pick(rs, 1001)).unwrap())
}

///|
pub(all) struct AnyLength(@span.Length) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for AnyLength with fn arbitrary(_size, rs) {
  AnyLength(@span.Length::new(pick(rs, 1001)).unwrap())
}

///|
/// A random text of ASCII letters, spaces, LF, CRLF and lone CR, with an
/// offset inside it (or at its end).
pub(all) struct TextAndOffset(String, @span.Offset) derive(Debug)

///|
pub impl @quickcheck.Arbitrary for TextAndOffset with fn arbitrary(size, rs) {
  let pieces = ["a", "b", " ", "\n", "\r\n", "\r", "é", "\u{1F600}"]
  let sb = StringBuilder()
  for _ in 0..<pick(rs, size + 1) {
    sb.write_string(pieces[pick(rs, pieces.length())])
  }
  let text = sb.to_string()
  TextAndOffset(text, @span.Offset::new(pick(rs, text.length() + 1)).unwrap())
}

///|
test "law: Offset::new accepts exactly the non-negative ints" {
  @quickcheck.check((n : Int) => (@span.Offset::new(n) is Some(_)) == (n >= 0), count=300, seed=1001)
  @quickcheck.check((n : Int) => (@span.Length::new(n) is Some(_)) == (n >= 0), count=300, seed=1002)
  @quickcheck.check((n : Int) => (@span.Line::new(n) is Some(_)) == (n >= 1), count=300, seed=1003)
  @quickcheck.check((n : Int) => (@span.Column::new(n) is Some(_)) == (n >= 1), count=300, seed=1004)
}

///|
test "law: advance and distance round-trip, and advance never moves backwards" {
  @quickcheck.check(
    (p : (AnyOffset, AnyLength)) => {
      let (AnyOffset(o), AnyLength(l)) = p
      let moved = o.advance(l)
      o.distance(moved) == l && moved >= o && o.next() == o.advance(@span.Length::one())
    },
    count=300,
    seed=1005,
  )
}

///|
test "law: distance and to are symmetric, and to's end is the larger offset" {
  @quickcheck.check(
    (p : (AnyOffset, AnyOffset)) => {
      let (AnyOffset(a), AnyOffset(b)) = p
      let s = a.to(b)
      a.distance(b) == b.distance(a) &&
      s == b.to(a) &&
      s.end() == (if a > b { a } else { b }) &&
      s.start == (if a < b { a } else { b }) &&
      s.length == a.distance(b)
    },
    count=300,
    seed=1006,
  )
}

///|
test "law: Length addition is a commutative monoid with zero" {
  @quickcheck.check(
    (p : (AnyLength, AnyLength, AnyLength)) => {
      let (AnyLength(a), AnyLength(b), AnyLength(c)) = p
      a + b == b + a && (a + b) + c == a + (b + c) && a + @span.Length::zero() == a
    },
    count=300,
    seed=1007,
  )
}

///|
test "law: a span contains its start when non-empty and never its end; join covers and is idempotent" {
  @quickcheck.check(
    (p : (AnyOffset, AnyOffset, AnyOffset, AnyOffset)) => {
      let (AnyOffset(a), AnyOffset(b), AnyOffset(c), AnyOffset(d)) = p
      let s = a.to(b)
      let u = c.to(d)
      let j = s.join(u)
      (s.contains(s.start) == !s.is_empty()) &&
      !s.contains(s.end()) &&
      j == u.join(s) &&
      j.join(s) == j &&
      j.start <= s.start && j.start <= u.start && j.end() >= s.end() && j.end() >= u.end()
    },
    count=300,
    seed=1008,
  )
}

///|
test "law: position and line_span agree, and position is monotone in the offset" {
  @quickcheck.check(
    (t : TextAndOffset) => {
      let TextAndOffset(text, o) = t
      let st = @span.SourceText::new(text)
      let p = st.position(o)
      guard st.line_span(p.line) is Some(ls) else { return false }
      // The column counts units from the line start, also on the line break.
      let agrees = o.0 - ls.start.0 + 1 == p.column.0 && o >= ls.start
      let in_range = p.line.0 >= 1 && p.line.0 <= st.line_count()
      let monotone = o.0 == 0 || {
        let q = st.position(@span.Offset::new(o.0 - 1).unwrap())
        q.line < p.line || (q.line == p.line && q.column < p.column)
      }
      agrees && in_range && monotone
    },
    count=400,
    max_size=24,
    seed=1009,
  )
}

///|
test "law: slice of a line span is the line text and never panics on any span" {
  @quickcheck.check(
    (t : TextAndOffset) => {
      let TextAndOffset(text, o) = t
      let st = @span.SourceText::new(text)
      let p = st.position(o)
      let by_line = st.line_span(p.line).map(s => st.slice(s)) == st.line_text(p.line)
      let any_span = st.slice(o.to(st.end())).length() == st.end().0 - o.0
      by_line && any_span
    },
    count=300,
    max_size=24,
    seed=1010,
  )
}
```

Run: `moon test -p moonrockz/smithy-syntax/span`
Expected: all laws pass. A counterexample means the type's invariant is wrong, not the law, unless the law mis-states the spec.

- [ ] **Step 8: Run the tests, write the README, commit**

Run: `moon test -p moonrockz/smithy-syntax/span`
Expected: all pass. If a `debug_inspect` of a newtype prints differently (for example `Offset(2)` versus `2`), confirm the value and update the `content`.

`span/README.mbt.md`:

````markdown
# span

Typed positions: `Offset` (a UTF-16 unit index), `Length`, `Line` and
`Column` are never negative or zero where that makes no sense, because
their constructors are the only way in. A `Span` is a start and a length.
`SourceText` maps offsets to positions and lines.

```mbt check
test {
  let st = @span.SourceText::new("string Foo\nstring Bar\n", name="a.smithy")
  let at = @span.Offset::new(11).unwrap()
  debug_inspect(st.position(at), content="{ line: Line(2), column: Column(1) }")
  inspect(st.line_text(@span.Line::first().next()), content="Some(\"string Bar\")")
}
```
````

```bash
mise run format
git add pkgs/smithy-syntax/src/span
git commit -m "feat(syntax): add the span package with typed offsets, spans and positions"
```

---

### Task 3: `diagnostic` package

**Files:**
- Create: `pkgs/smithy-syntax/src/diagnostic/moon.pkg`
- Create: `pkgs/smithy-syntax/src/diagnostic/diagnostic.mbt`
- Create: `pkgs/smithy-syntax/src/diagnostic/codes.mbt`
- Create: `pkgs/smithy-syntax/src/diagnostic/diagnostic_test.mbt`
- Create: `pkgs/smithy-syntax/src/diagnostic/README.mbt.md`

**Interfaces:**
- Consumes: `@span.Span`, `@span.Offset`.
- Produces: `Severity = Error | Warning`; `Label { span, text }`; `Diagnostic { code, severity, title, message, span, labels : ArrayView[Label], notes : ArrayView[String], hint : String?, example : String? }`; `Diagnostic::new(code~, severity~, title~, message~, span~, labels? : Array[Label], notes? : Array[String], hint? : String, example? : String)`; `is_error()`; `with_context(label : Label, note : String) -> Diagnostic` (a copy with the label and note prepended, used by the parser's context stack); `codes() -> ArrayView[String]`; `description(code) -> String?`.

- [ ] **Step 1: Write the failing tests**

`diagnostic/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax/span",
}

import {
  "moonrockz/smithy-syntax/diagnostic",
  "moonrockz/smithy-syntax/span",
  "moonrockz/expect",
  "moonbitlang/core/debug",
} for "test"
```

`diagnostic/diagnostic_test.mbt`:

```moonbit
///|
fn sp(a : Int, b : Int) -> @span.Span raise {
  guard @span.Offset::new(a) is Some(x) && @span.Offset::new(b) is Some(y) else { fail("bad span") }
  x.to(y)
}

///|
test "a diagnostic has defaults for the optional parts" {
  let d = @diagnostic.Diagnostic::new(
    code="SM-PARSE-001",
    severity=Error,
    title="UNEXPECTED TOKEN",
    message="I was expecting a shape name here",
    span=sp(4, 7),
  )
  @expect.expect_all(e => {
    e.expect(d.is_error()).to_be_true()
    e.expect(d.labels.length()).to_equal(0)
    e.expect(d.notes.length()).to_equal(0)
    e.expect(d.hint).to_equal(None)
    e.expect(d.example).to_equal(None)
  })
}

///|
test "a warning is not an error" {
  let d = @diagnostic.Diagnostic::new(
    code="SM-PARSE-009",
    severity=Warning,
    title="DETACHED DOC COMMENT",
    message="this documentation comment is not followed by a shape",
    span=sp(0, 10),
    hint="Move it right before the shape it documents.",
  )
  inspect(d.is_error(), content="false")
  inspect(d.hint, content="Some(\"Move it right before the shape it documents.\")")
}

///|
test "with_context prepends a label and a note and keeps the rest" {
  let d = @diagnostic.Diagnostic::new(
    code="SM-PARSE-001",
    severity=Error,
    title="UNEXPECTED TOKEN",
    message="m",
    span=sp(4, 7),
    notes=["later"],
  )
  let c = d.with_context({ span: sp(0, 9), text: "the structure started here" }, "I was parsing a structure.")
  @expect.expect_all(e => {
    e.expect(c.labels.length()).to_equal(1)
    e.expect(c.labels[0].text).to_equal("the structure started here")
    e.expect(c.notes.to_array()).to_equal(["I was parsing a structure.", "later"])
    e.expect(c.message).to_equal("m")
    e.expect(d.labels.length()).to_equal(0)
  })
}

///|
test "every code has a description and the table is in order" {
  let codes = @diagnostic.codes()
  inspect(codes.length(), content="18")
  inspect(codes[0], content="SM-SCAN-001")
  inspect(codes[7], content="SM-PARSE-001")
  inspect(codes[17], content="SM-PARSE-011")
  for c in codes {
    inspect(@diagnostic.description(c) is Some(_), content="true")
  }
  inspect(@diagnostic.description("SM-NOPE-001"), content="None")
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `moon test -p moonrockz/smithy-syntax/diagnostic`
Expected: compile error.

- [ ] **Step 3: Implement diagnostic.mbt and codes.mbt**

`diagnostic.mbt`:

```moonbit
///|
/// How serious a diagnostic is. A file with an `Error` is rejected; a
/// `Warning` does not stop parsing.
pub(all) enum Severity {
  Error
  Warning
} derive(Eq, Debug, Hash)

///|
/// A secondary span with the text shown under it ("the structure started
/// here").
pub(all) struct Label {
  span : @span.Span
  text : String
} derive(Eq, Debug)

///|
/// A problem found while scanning or parsing, with everything a rich
/// report needs: a `title` in capitals (`UNFINISHED SHAPE`), a one-line
/// `message` under the primary `span`, secondary `labels`, `notes` in the
/// first person, an optional `hint` and an optional correct `example`.
/// Immutable: `with_context` returns a new value.
pub(all) struct Diagnostic {
  code : String
  severity : Severity
  title : String
  message : String
  span : @span.Span
  labels : ArrayView[Label]
  notes : ArrayView[String]
  hint : String?
  example : String?
} derive(Eq, Debug)

///|
pub fn Diagnostic::new(
  code~ : String,
  severity~ : Severity,
  title~ : String,
  message~ : String,
  span~ : @span.Span,
  labels? : Array[Label],
  notes? : Array[String],
  hint? : String,
  example? : String,
) -> Diagnostic {
  {
    code,
    severity,
    title,
    message,
    span,
    labels: labels.unwrap_or([])[:],
    notes: notes.unwrap_or([])[:],
    hint,
    example,
  }
}

///|
pub fn Diagnostic::is_error(self : Diagnostic) -> Bool {
  self.severity == Error
}

///|
/// A copy with `label` as the first label and `note` as the first note.
pub fn Diagnostic::with_context(self : Diagnostic, label : Label, note : String) -> Diagnostic {
  let labels = [label]
  labels.append(self.labels.to_array())
  let notes = [note]
  notes.append(self.notes.to_array())
  { ..self, labels: labels[:], notes: notes[:] }
}
```

`codes.mbt`:

```moonbit
///|
/// Every diagnostic code with its one-line description. The scanner and
/// the parser emit only codes from this table; the laws check that.
let table : Array[(String, String)] = [
  ("SM-SCAN-001", "Unexpected character"),
  ("SM-SCAN-002", "Unterminated string"),
  ("SM-SCAN-003", "Unterminated text block"),
  ("SM-SCAN-004", "Text block must start with a line break"),
  ("SM-SCAN-005", "Unknown escape sequence"),
  ("SM-SCAN-006", "Invalid unicode escape"),
  ("SM-SCAN-007", "Invalid number"),
  ("SM-PARSE-001", "Unexpected token"),
  ("SM-PARSE-002", "Unexpected end of file"),
  ("SM-PARSE-003", "Missing line break between statements"),
  ("SM-PARSE-004", "Expected a statement"),
  ("SM-PARSE-005", "Invalid shape ID or shape name"),
  ("SM-PARSE-006", "Unsupported Smithy version"),
  ("SM-PARSE-007", "Syntax that needs Smithy IDL version 2"),
  ("SM-PARSE-008", "Documentation comment before apply"),
  ("SM-PARSE-009", "Detached documentation comment (warning)"),
  ("SM-PARSE-010", "Too much nesting"),
  ("SM-PARSE-011", "Unknown operation property"),
]

///|
/// Every diagnostic code, in table order.
pub fn codes() -> ArrayView[String] {
  table.map(entry => entry.0)[:]
}

///|
/// The one-line description of a code, or `None` for an unknown code.
pub fn description(code : String) -> String? {
  for entry in table {
    if entry.0 == code {
      return Some(entry.1)
    }
  }
  None
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `moon test -p moonrockz/smithy-syntax/diagnostic`
Expected: all pass.

- [ ] **Step 5: README and commit**

`diagnostic/README.mbt.md`:

````markdown
# diagnostic

A `Diagnostic` is a code (`SM-SCAN-nnn`, `SM-PARSE-nnn`), a severity, a
title, a message under its primary span, secondary labels, notes, and an
optional hint and example. It is a value: `with_context` returns a copy.
`codes()` lists every code.

```mbt check
test {
  inspect(@diagnostic.description("SM-PARSE-003"), content="Some(\"Missing line break between statements\")")
}
```
````

```bash
mise run format
git add pkgs/smithy-syntax/src/diagnostic
git commit -m "feat(syntax): add the diagnostic package with the code table"
```

---

### Task 4: `scanner` types and the pure scanning pipeline (punctuation, identifiers, trivia)

**Files:**
- Create: `pkgs/smithy-syntax/src/scanner/moon.pkg`
- Create: `pkgs/smithy-syntax/src/scanner/types.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/chars.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/scan.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/pipeline.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/scan_test.mbt`

**Interfaces:**
- Consumes: `@span.Offset`, `@span.Length`, `@span.Span`, `@span.SourceText`, `@diagnostic.Diagnostic`.
- Produces: `TokenKind` (18 variants), `CommentKind = Line | Doc`, `Comment { kind, text, span }`, `Trivia = Whitespace(String, Span) | Newline(String, Span) | Comma(Span) | Comment(Comment)` with `text()`, `span()`, `is_newline()`, `is_comment()`; `Token { kind, lexeme, span, trivia_before, trivia_after }` with `to_source()`; `TokenStream { tokens, trivia, diagnostics }` with `to_source()`, `has_errors()`; `Piece = Tok(TokenKind, String, Span) | Triv(Trivia)`; `Step { piece, end : Offset, diagnostics : ArrayView[Diagnostic] }`; the pure functions `scan_at(text : String, at : Offset) -> Step?`, `scan_pieces(text : String) -> Array[Step]`, `attach_trivia(steps : Array[Step]) -> TokenStream`, `tokenize(SourceText) -> TokenStream`, `tokenize_text(String) -> TokenStream`.

- [ ] **Step 1: Write the types**

`scanner/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax/span",
  "moonrockz/smithy-syntax/diagnostic",
}

import {
  "moonrockz/smithy-syntax/scanner",
  "moonrockz/smithy-syntax/span",
  "moonrockz/smithy-syntax/diagnostic",
  "moonrockz/expect",
  "moonbitlang/core/debug",
  "moonbitlang/core/quickcheck",
} for "test"
```

`scanner/types.mbt`:

```moonbit
///|
/// The token kinds, the reference's `IdlToken` without its whitespace
/// kinds (those are `Trivia`) and without `EOF`. Keywords are identifiers:
/// Smithy keywords are contextual and the parser recognizes them.
pub(all) enum TokenKind {
  Identifier
  Number
  String
  TextBlock
  At
  Colon
  Walrus
  Equal
  Dot
  Pound
  Dollar
  LBrace
  RBrace
  LBracket
  RBracket
  LParen
  RParen
  /// Text a lexical error covers; the diagnostic is in the stream.
  Error
} derive(Eq, Debug, Hash)

///|
/// `//` or `///`.
pub(all) enum CommentKind {
  Line
  Doc
} derive(Eq, Debug, Hash)

///|
/// A comment. `span` covers the slashes and the text up to the line break
/// (not included); `text` is what follows the slashes.
pub(all) struct Comment {
  kind : CommentKind
  text : String
  span : @span.Span
} derive(Eq, Debug)

///|
/// Text between tokens. The specification treats a comma as whitespace, so
/// it is trivia here.
pub(all) enum Trivia {
  Whitespace(String, @span.Span)
  Newline(String, @span.Span)
  Comma(@span.Span)
  Comment(Comment)
} derive(Eq, Debug)

///|
/// The source text of the trivia.
pub fn Trivia::text(self : Trivia) -> String {
  match self {
    Whitespace(text, _) | Newline(text, _) => text
    Comma(_) => ","
    Comment(c) => (if c.kind == Doc { "///" } else { "//" }) + c.text
  }
}

///|
pub fn Trivia::span(self : Trivia) -> @span.Span {
  match self {
    Whitespace(_, s) | Newline(_, s) | Comma(s) => s
    Comment(c) => c.span
  }
}

///|
pub fn Trivia::is_newline(self : Trivia) -> Bool {
  self is Newline(_, _)
}

///|
pub fn Trivia::is_comment(self : Trivia) -> Bool {
  self is Comment(_)
}

///|
/// A token with the trivia around it. Trivia after a token up to and
/// including the first line break is its `trivia_after`; everything else
/// is the next token's `trivia_before`.
pub(all) struct Token {
  kind : TokenKind
  lexeme : String
  span : @span.Span
  trivia_before : ArrayView[Trivia]
  trivia_after : ArrayView[Trivia]
} derive(Eq, Debug)

///|
/// `trivia_before`, the lexeme and `trivia_after`, as in the source.
pub fn Token::to_source(self : Token) -> String {
  let sb = StringBuilder()
  for t in self.trivia_before {
    sb.write_string(t.text())
  }
  sb.write_string(self.lexeme)
  for t in self.trivia_after {
    sb.write_string(t.text())
  }
  sb.to_string()
}

///|
/// The result of a scan. `trivia` is the trivia of a text with no tokens,
/// and empty otherwise. `diagnostics` are the lexical problems in order.
pub(all) struct TokenStream {
  tokens : ArrayView[Token]
  trivia : ArrayView[Trivia]
  diagnostics : ArrayView[@diagnostic.Diagnostic]
} derive(Eq, Debug)

///|
/// The scanned text, byte for byte.
pub fn TokenStream::to_source(self : TokenStream) -> String {
  let sb = StringBuilder()
  for t in self.trivia {
    sb.write_string(t.text())
  }
  for token in self.tokens {
    sb.write_string(token.to_source())
  }
  sb.to_string()
}

///|
pub fn TokenStream::has_errors(self : TokenStream) -> Bool {
  self.diagnostics.iter().any(d => d.is_error())
}

///|
/// What one scanning step produces, in source order.
pub(all) enum Piece {
  Tok(TokenKind, String, @span.Span)
  Triv(Trivia)
} derive(Eq, Debug)

///|
/// One step of the scan: the piece read at an offset, where the next step
/// starts, and the lexical problems found in the piece (several for a
/// string with several bad escapes).
pub(all) struct Step {
  piece : Piece
  end : @span.Offset
  diagnostics : ArrayView[@diagnostic.Diagnostic]
} derive(Eq, Debug)
```

- [ ] **Step 2: Write the failing tests**

`scanner/scan_test.mbt`:

```moonbit
///|
fn off(n : Int) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(o) else { fail("bad offset") }
  o
}

///|
fn stream(text : String) -> @scanner.TokenStream {
  @scanner.tokenize_text(text)
}

///|
fn kinds(text : String) -> Array[@scanner.TokenKind] {
  stream(text).tokens.iter().map(t => t.kind).collect()
}

///|
fn lexemes(text : String) -> Array[String] {
  stream(text).tokens.iter().map(t => t.lexeme).collect()
}

///|
fn codes(text : String) -> Array[String] {
  stream(text).diagnostics.iter().map(d => d.code).collect()
}

///|
test "scan_at is a pure function of the text and an offset" {
  let text = "ab cd"
  guard @scanner.scan_at(text, off(3)) is Some(step) else { fail("no step") }
  debug_inspect(step.piece, content="Tok(Identifier, \"cd\", { start: Offset(3), length: Length(2) })")
  inspect(step.end, content="Offset(5)")
  inspect(step.diagnostics.length(), content="0")
  inspect(@scanner.scan_at(text, off(5)) is None, content="true")
  // Calling it twice gives the same answer: nothing is remembered.
  inspect(@scanner.scan_at(text, off(3)) == @scanner.scan_at(text, off(3)), content="true")
}

///|
test "punctuation" {
  @expect.expect(kinds("@ : := = . # $ { } [ ] ( )")).to_equal([
    At, Colon, Walrus, Equal, Dot, Pound, Dollar, LBrace, RBrace, LBracket,
    RBracket, LParen, RParen,
  ])
}

///|
test "identifiers and keywords are identifiers" {
  @expect.expect(lexemes("namespace smithy.example _x __y1 Foo_Bar")).to_equal([
    "namespace", "smithy", ".", "example", "_x", "__y1", "Foo_Bar",
  ])
  inspect(kinds("structure")[0], content="Identifier")
}

///|
test "a shape id scans as adjacent pieces" {
  @expect.expect(kinds("smithy.api#String$member")).to_equal([
    Identifier, Dot, Identifier, Pound, Identifier, Dollar, Identifier,
  ])
}

///|
test "whitespace, commas and comments are trivia" {
  let s = stream(
    (
      #|a, b // c
      #|/// doc
      #|d
    ),
  )
  inspect(s.tokens.length(), content="3")
  @expect.expect(s.tokens[0].trivia_after.map(t => t.text())).to_equal([",", " "])
  @expect.expect(s.tokens[1].trivia_after.map(t => t.text())).to_equal([" ", "// c", "\n"])
  @expect.expect(s.tokens[2].trivia_before.map(t => t.text())).to_equal(["/// doc", "\n"])
  guard s.tokens[2].trivia_before[0] is Comment(c) else { fail("not a comment") }
  inspect(c.kind, content="Doc")
  inspect(c.text, content=" doc")
  debug_inspect(c.span, content="{ start: Offset(10), length: Length(7) }")
}

///|
test "trivia after a token stops at the first line break" {
  let s = stream(
    (
      #|a
      #|
      #|  b
    ),
  )
  @expect.expect(s.tokens[0].trivia_after.map(t => t.text())).to_equal(["\n"])
  @expect.expect(s.tokens[1].trivia_before.map(t => t.text())).to_equal(["\n", "  "])
}

///|
test "CRLF is one newline trivia and the scan is lossless" {
  let text = "string Foo\r\nstring Bar\r\n"
  let s = stream(text)
  inspect(s.to_source() == text, content="true")
  @expect.expect(s.tokens[1].trivia_after.map(t => t.text())).to_equal(["\r\n"])
  inspect(s.tokens[1].trivia_after[0].is_newline(), content="true")
}

///|
test "a text with only trivia keeps it on the stream" {
  let s = stream(
    (
      #|  // hi
      #|
    ),
  )
  inspect(s.tokens.length(), content="0")
  inspect(s.trivia.length(), content="3")
  inspect(s.to_source(), content=(
    #|  // hi
    #|
  ))
}

///|
test "an unexpected character is an Error token with SM-SCAN-001" {
  let s = stream("a ^ b")
  @expect.expect(kinds("a ^ b")).to_equal([Identifier, Error, Identifier])
  @expect.expect(codes("a ^ b")).to_equal(["SM-SCAN-001"])
  inspect(s.to_source(), content="a ^ b")
  inspect(s.diagnostics[0].message, content="I don't know what to do with `^`")
}

///|
test "a lone CR is whitespace, not a newline" {
  @expect.expect(stream("a\rb").tokens[0].trivia_after.map(t => t.text())).to_equal(["\r"])
  inspect(stream("a\rb").tokens[0].trivia_after[0].is_newline(), content="false")
}

///|
test "the pipeline stages compose" {
  let text = "a b"
  let steps = @scanner.scan_pieces(text)
  inspect(steps.length(), content="3")
  let s = text |> @scanner.scan_pieces |> @scanner.attach_trivia
  inspect(s.tokens.length(), content="2")
  inspect(s == stream(text), content="true")
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `moon test -p moonrockz/smithy-syntax/scanner`
Expected: compile error, `tokenize_text` not found.

- [ ] **Step 4: Implement chars.mbt (pure character access)**

```moonbit
///|
/// The code unit at `at` as a `Char`, or `None` past the end. A unit of a
/// surrogate pair comes back as itself; the scanner only compares against
/// ASCII, and lexemes are sliced from the text, so no character is lost.
fn unit_at(text : String, at : @span.Offset) -> Char? {
  if at.0 >= text.length() {
    None
  } else {
    Some(text.code_unit_at(at.0).to_int().unsafe_to_char())
  }
}

///|
/// The unit `k` places after `at`.
fn peek(text : String, at : @span.Offset, k : Int) -> Char? {
  unit_at(text, @span.Offset::new(at.0 + k).unwrap_or(at))
}

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_alpha(c) || is_digit(c) || c == '_'
}

///|
fn is_hex(c : Char) -> Bool {
  is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
/// Whether the text at `at` starts with `s`.
fn looking_at(text : String, at : @span.Offset, s : String) -> Bool {
  let n = s.length()
  if at.0 + n > text.length() {
    return false
  }
  for k in 0..<n {
    if text.code_unit_at(at.0 + k) != s.code_unit_at(k) {
      return false
    }
  }
  true
}

///|
/// The offset of the first unit at or after `from` that fails `pred` (or
/// the end of the text).
fn skip_while(text : String, from : @span.Offset, pred : (Char) -> Bool) -> @span.Offset {
  let mut at = from
  while unit_at(text, at) is Some(c) && pred(c) {
    at = at.next()
  }
  at
}

///|
fn slice(text : String, from : @span.Offset, to : @span.Offset) -> String {
  text.unsafe_substring(start=from.0, end=to.0)
}

///|
/// A `Step` for a token from `at` to `end`.
fn token_step(kind : TokenKind, text : String, at : @span.Offset, end : @span.Offset) -> Step {
  { piece: Tok(kind, slice(text, at, end), at.to(end)), end, diagnostics: [][:] }
}

///|
fn trivia_step(t : Trivia, end : @span.Offset) -> Step {
  { piece: Triv(t), end, diagnostics: [][:] }
}

///|
/// A `Step` for an `Error` token with one diagnostic.
fn error_step(text : String, at : @span.Offset, end : @span.Offset, d : @diagnostic.Diagnostic) -> Step {
  { piece: Tok(Error, slice(text, at, end), at.to(end)), end, diagnostics: [d][:] }
}

///|
fn lexical(
  code : String,
  title : String,
  message : String,
  span : @span.Span,
  notes? : Array[String],
  hint? : String,
) -> @diagnostic.Diagnostic {
  @diagnostic.Diagnostic::new(code~, severity=Error, title~, message~, span~, notes?, hint?)
}
```

- [ ] **Step 5: Implement scan.mbt (every function is `(text, at) -> Step`)**

```moonbit
///|
/// `IdentifierStart = (1*"_" (ALPHA / DIGIT)) / ALPHA`.
fn at_identifier_start(text : String, at : @span.Offset) -> Bool {
  match unit_at(text, at) {
    Some(c) if is_alpha(c) => true
    Some('_') => {
      let after = skip_while(text, at, c => c == '_')
      match unit_at(text, after) {
        Some(c) => is_alpha(c) || is_digit(c)
        None => false
      }
    }
    _ => false
  }
}

///|
fn scan_identifier(text : String, at : @span.Offset) -> Step {
  token_step(Identifier, text, at, skip_while(text, at, is_ident_char))
}

///|
/// Spaces and tabs; a lone `\r` too, since it is not a line break.
fn scan_whitespace(text : String, at : @span.Offset) -> Step {
  let mut end = at
  while unit_at(text, end) is Some(' ' | '\t' | '\r') {
    if unit_at(text, end) == Some('\r') && peek(text, end, 1) == Some('\n') {
      break
    }
    end = end.next()
  }
  trivia_step(Whitespace(slice(text, at, end), at.to(end)), end)
}

///|
fn scan_newline(text : String, at : @span.Offset) -> Step {
  let end = if unit_at(text, at) == Some('\r') { at.next().next() } else { at.next() }
  trivia_step(Newline(slice(text, at, end), at.to(end)), end)
}

///|
/// `//` or `///` to the end of the line (the line break is not included).
fn scan_comment(text : String, at : @span.Offset) -> Step {
  let kind = if peek(text, at, 2) == Some('/') { Doc } else { Line }
  let text_start = at.advance(if kind == Doc { @span.Length::new(3).unwrap() } else { @span.Length::new(2).unwrap() })
  let mut end = text_start
  while unit_at(text, end) is Some(c) && c != '\n' {
    if c == '\r' && peek(text, end, 1) == Some('\n') {
      break
    }
    end = end.next()
  }
  trivia_step(Comment({ kind, text: slice(text, text_start, end), span: at.to(end) }), end)
}

///|
fn scan_single(kind : TokenKind, text : String, at : @span.Offset) -> Step {
  token_step(kind, text, at, at.next())
}

///|
/// One unexpected character (both units of a surrogate pair) as an `Error`
/// token with `SM-SCAN-001`.
fn scan_unexpected(text : String, at : @span.Offset) -> Step {
  let c = text.code_unit_at(at.0).to_int()
  let is_high = c >= 0xD800 && c <= 0xDBFF
  let low_follows = match peek(text, at, 1) {
    Some(l) => l.to_int() >= 0xDC00 && l.to_int() <= 0xDFFF
    None => false
  }
  let end = if is_high && low_follows { at.next().next() } else { at.next() }
  let shown = slice(text, at, end)
  error_step(
    text,
    at,
    end,
    lexical(
      "SM-SCAN-001",
      "UNEXPECTED CHARACTER",
      "I don't know what to do with `\{shown}`",
      at.to(end),
      notes=[
        "I was reading tokens and found a character that cannot start one. Smithy IDL uses letters, digits, `_`, quotes, numbers and the punctuation `@ : := = . # $ { } [ ] ( ) ,`.",
      ],
    ),
  )
}

///|
/// One token or one piece of trivia at `at`, or `None` at the end of the
/// text. Pure: the same text and offset always give the same step.
pub fn scan_at(text : String, at : @span.Offset) -> Step? {
  guard unit_at(text, at) is Some(c) else { return None }
  Some(
    match c {
      '\n' => scan_newline(text, at)
      '\r' =>
        if peek(text, at, 1) == Some('\n') {
          scan_newline(text, at)
        } else {
          scan_whitespace(text, at)
        }
      ' ' | '\t' => scan_whitespace(text, at)
      ',' => trivia_step(Comma(at.to(at.next())), at.next())
      '/' if peek(text, at, 1) == Some('/') => scan_comment(text, at)
      '@' => scan_single(At, text, at)
      ':' =>
        if peek(text, at, 1) == Some('=') {
          token_step(Walrus, text, at, at.next().next())
        } else {
          scan_single(Colon, text, at)
        }
      '=' => scan_single(Equal, text, at)
      '.' => scan_single(Dot, text, at)
      '#' => scan_single(Pound, text, at)
      '$' => scan_single(Dollar, text, at)
      '{' => scan_single(LBrace, text, at)
      '}' => scan_single(RBrace, text, at)
      '[' => scan_single(LBracket, text, at)
      ']' => scan_single(RBracket, text, at)
      '(' => scan_single(LParen, text, at)
      ')' => scan_single(RParen, text, at)
      '"' => scan_string_or_text_block(text, at)
      '-' => scan_number(text, at)
      _ =>
        if is_digit(c) {
          scan_number(text, at)
        } else if at_identifier_start(text, at) {
          scan_identifier(text, at)
        } else {
          scan_unexpected(text, at)
        }
    },
  )
}
```

Until Task 5 lands, add two stubs at the bottom of `scan.mbt` so the package compiles (Task 5 replaces them):

```moonbit
///|
fn scan_string_or_text_block(text : String, at : @span.Offset) -> Step {
  scan_unexpected(text, at)
}

///|
fn scan_number(text : String, at : @span.Offset) -> Step {
  scan_unexpected(text, at)
}
```

- [ ] **Step 6: Implement pipeline.mbt**

```moonbit
///|
/// Every step of the text, in order: an unfold over `scan_at`. The only
/// state is the offset local to this function.
pub fn scan_pieces(text : String) -> Array[Step] {
  let steps : Array[Step] = []
  let mut at = @span.Offset::zero()
  while scan_at(text, at) is Some(step) {
    steps.push(step)
    at = step.end
  }
  steps
}

///|
/// Group the steps into tokens with trivia and collect the diagnostics.
/// Trivia after a token up to and including the first line break is its
/// `trivia_after`; the rest goes to the next token's `trivia_before`.
/// Trailing trivia after the last token's line break stays with that token.
pub fn attach_trivia(steps : Array[Step]) -> TokenStream {
  let tokens : Array[Token] = []
  let diagnostics : Array[@diagnostic.Diagnostic] = []
  let mut before : Array[Trivia] = []
  let mut i = 0
  let n = steps.length()
  while i < n {
    diagnostics.append(steps[i].diagnostics.to_array())
    match steps[i].piece {
      Triv(t) => {
        before.push(t)
        i += 1
      }
      Tok(kind, lexeme, span) => {
        i += 1
        let after : Array[Trivia] = []
        while i < n && steps[i].piece is Triv(t) {
          after.push(t)
          i += 1
          if t.is_newline() {
            break
          }
        }
        tokens.push({ kind, lexeme, span, trivia_before: before[:], trivia_after: after[:] })
        before = []
      }
    }
  }
  let trivia : Array[Trivia] = if tokens.is_empty() {
    before
  } else {
    let last = tokens[tokens.length() - 1]
    let merged = last.trivia_after.to_array()
    merged.append(before)
    tokens[tokens.length() - 1] = { ..last, trivia_after: merged[:] }
    []
  }
  { tokens: tokens[:], trivia: trivia[:], diagnostics: diagnostics[:] }
}

///|
/// Scan `source`: a pipeline of pure stages. The scan never fails and is
/// lossless: `TokenStream::to_source()` is the text.
pub fn tokenize(source : @span.SourceText) -> TokenStream {
  source.text() |> scan_pieces |> attach_trivia
}

///|
pub fn tokenize_text(text : String) -> TokenStream {
  @span.SourceText::new(text) |> tokenize
}
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `moon test -p moonrockz/smithy-syntax/scanner`
Expected: all pass. If a `debug_inspect` of a span or newtype prints differently from the expected string, confirm the values and update the `content`.

- [ ] **Step 8: Format and commit**

```bash
mise run format
git add pkgs/smithy-syntax/src/scanner
git commit -m "feat(syntax): add the scanner types and the pure scanning pipeline"
```

---

### Task 5: Scanner numbers, strings, text blocks and the decoders

**Files:**
- Modify: `pkgs/smithy-syntax/src/scanner/scan.mbt` (delete the two stubs)
- Create: `pkgs/smithy-syntax/src/scanner/numbers.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/strings.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/decode.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/numbers_test.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/strings_test.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/decode_test.mbt`

**Interfaces:**
- Produces: `scan_number(text, at) -> Step`, `scan_string_or_text_block(text, at) -> Step` (private, pure); `unescape(lexeme : String) -> String` (the value of a quoted string token, quotes included in the input); `text_block_value(lexeme : String) -> String` (the value of a text block token, the three quotes included); `is_integer_lexeme(lexeme : String) -> Bool`.

- [ ] **Step 1: Write the failing number tests**

`scanner/numbers_test.mbt`:

```moonbit
///|
fn nkinds(text : String) -> Array[@scanner.TokenKind] {
  @scanner.tokenize_text(text).tokens.iter().map(t => t.kind).collect()
}

///|
fn ncodes(text : String) -> Array[String] {
  @scanner.tokenize_text(text).diagnostics.iter().map(d => d.code).collect()
}

///|
test "valid numbers" {
  for text in ["0", "7", "42", "-1", "1.5", "-0.25", "1e3", "1E-3", "2.5e+10", "0.0"] {
    @expect.expect(nkinds(text)).because(text).to_equal([Number])
    @expect.expect(ncodes(text)).because(text).to_equal([])
  }
}

///|
test "invalid numbers are one Error token with SM-SCAN-007" {
  for text in ["01", "1.", "1e", "1e+", "-", "-a", "1.e5", "00"] {
    @expect.expect(nkinds(text)[0]).because(text).to_equal(Error)
    @expect.expect(ncodes(text)).because(text).to_equal(["SM-SCAN-007"])
  }
  inspect(@scanner.tokenize_text("01 x").to_source(), content="01 x")
}

///|
test "a number stops at punctuation" {
  @expect.expect(nkinds("[1,2]")).to_equal([LBracket, Number, Number, RBracket])
}

///|
test "is_integer_lexeme" {
  @expect.expect_all(e => {
    e.expect(@scanner.is_integer_lexeme("42")).to_be_true()
    e.expect(@scanner.is_integer_lexeme("-42")).to_be_true()
    e.expect(@scanner.is_integer_lexeme("4.2")).to_be_false()
    e.expect(@scanner.is_integer_lexeme("4e2")).to_be_false()
  })
}
```

- [ ] **Step 2: Implement numbers.mbt and delete the `scan_number` stub**

```moonbit
///|
/// The digits at `from`: the offset after them and whether there was one.
fn digits(text : String, from : @span.Offset) -> (@span.Offset, Bool) {
  let end = skip_while(text, from, is_digit)
  (end, end > from)
}

///|
/// `Number = [Minus] Int [Frac] [Exp]`, with `Int = "0" / DigitOneToNine
/// *DIGIT`. A run that does not fit is one `Error` token covering every
/// digit, sign, dot, `e`, `+`/`-` and glued letter, with `SM-SCAN-007`.
fn scan_number(text : String, at : @span.Offset) -> Step {
  let mut ok = true
  let mut end = at
  if unit_at(text, end) == Some('-') {
    end = end.next()
  }
  // Int
  match unit_at(text, end) {
    Some('0') => {
      end = end.next()
      let (after, more) = digits(text, end)
      if more {
        ok = false
        end = after
      }
    }
    Some(c) if is_digit(c) => end = digits(text, end).0
    _ => ok = false
  }
  // Frac
  if unit_at(text, end) == Some('.') {
    let (after, some) = digits(text, end.next())
    end = after
    if !some {
      ok = false
    }
  }
  // Exp
  if unit_at(text, end) is Some('e' | 'E') {
    end = end.next()
    if unit_at(text, end) is Some('+' | '-') {
      end = end.next()
    }
    let (after, some) = digits(text, end)
    end = after
    if !some {
      ok = false
    }
  }
  // A letter or dot glued to a number is part of the bad run (`1x`, `-a`).
  if unit_at(text, end) is Some(c) && (is_ident_char(c) || c == '.') {
    ok = false
    end = skip_while(text, end, c => is_ident_char(c) || c == '.')
  }
  if ok {
    token_step(Number, text, at, end)
  } else {
    let shown = slice(text, at, end)
    error_step(
      text,
      at,
      end,
      lexical(
        "SM-SCAN-007",
        "INVALID NUMBER",
        "I cannot read `\{shown}` as a number",
        at.to(end),
        notes=[
          "A number is an optional `-`, then `0` or digits with no leading zero, then an optional fraction like `.25` and an optional exponent like `e10` or `E-3`.",
        ],
        hint="Write `0.5` rather than `.5`, `1.0` rather than `1.`, and drop leading zeros.",
      ),
    )
  }
}

///|
/// Whether a `Number` lexeme has no fraction and no exponent.
pub fn is_integer_lexeme(lexeme : String) -> Bool {
  for ch in lexeme {
    if ch == '.' || ch == 'e' || ch == 'E' {
      return false
    }
  }
  true
}
```

- [ ] **Step 3: Run the number tests**

Run: `moon test -p moonrockz/smithy-syntax/scanner`
Expected: number tests pass.

- [ ] **Step 4: Write the failing string and text block tests**

`scanner/strings_test.mbt`:

```moonbit
///|
fn skinds(text : String) -> Array[@scanner.TokenKind] {
  @scanner.tokenize_text(text).tokens.iter().map(t => t.kind).collect()
}

///|
fn scodes(text : String) -> Array[String] {
  @scanner.tokenize_text(text).diagnostics.iter().map(d => d.code).collect()
}

///|
test "quoted strings" {
  @expect.expect(skinds(
    (
      #|"" "hi" "a\"b" "multi
      #|line"
    ),
  )).to_equal([
    String, String, String, String,
  ])
  inspect(@scanner.tokenize_text("\"a\\\"b\"").tokens[0].lexeme, content="\"a\\\"b\"")
}

///|
test "an unterminated string runs to the end and is SM-SCAN-002" {
  let s = @scanner.tokenize_text(
    (
      #|"abc
      #|string Foo
    ),
  )
  @expect.expect(skinds(
    (
      #|"abc
      #|string Foo
    ),
  )).to_equal([Error])
  @expect.expect(scodes(
    (
      #|"abc
      #|string Foo
    ),
  )).to_equal(["SM-SCAN-002"])
  inspect(s.to_source(), content=(
    #|"abc
    #|string Foo
  ))
}

///|
test "bad escapes keep the String token and report each one" {
  @expect.expect(skinds("\"a\\qb\"")).to_equal([String])
  @expect.expect(scodes("\"a\\qb\"")).to_equal(["SM-SCAN-005"])
  @expect.expect(scodes("\"\\q\\z\"")).to_equal(["SM-SCAN-005", "SM-SCAN-005"])
  @expect.expect(scodes("\"\\u12\"")).to_equal(["SM-SCAN-006"])
  @expect.expect(scodes("\"\\u12G4\"")).to_equal(["SM-SCAN-006"])
  @expect.expect(scodes("\"\\n\\t\\r\\b\\f\\/\\\\\\\"\\u00e9\"")).to_equal([])
}

///|
test "text blocks" {
  let text = (
    #|"""
    #|    hello
    #|    """
  )
  @expect.expect(skinds(text)).to_equal([TextBlock])
  @expect.expect(scodes(text)).to_equal([])
  inspect(@scanner.tokenize_text(text).tokens[0].lexeme == text, content="true")
}

///|
test "a text block may hold one or two quotes in a row" {
  let text = (
    #|"""
    #|  say "hi" or ""hey""
    #|  """
  )
  @expect.expect(skinds(text)).to_equal([TextBlock])
}

///|
test "a text block must start with a line break" {
  @expect.expect(scodes("\"\"\"hello\"\"\"")).to_equal(["SM-SCAN-004"])
  @expect.expect(skinds("\"\"\"hello\"\"\"")).to_equal([TextBlock])
  @expect.expect(scodes(
    (
      #|"""   
      #| x
      #|"""
    ),
  )).to_equal([])
}

///|
test "an unterminated text block is SM-SCAN-003" {
  @expect.expect(scodes(
    (
      #|"""
      #| abc
    ),
  )).to_equal(["SM-SCAN-003"])
  @expect.expect(skinds(
    (
      #|"""
      #| abc
    ),
  )).to_equal([Error])
}
```

- [ ] **Step 5: Implement strings.mbt and delete the `scan_string_or_text_block` stub**

```moonbit
///|
/// Check one escape at `at` (which holds the `\`): the offset after it and
/// its diagnostic, if any. The token is still a string; `unescape` keeps a
/// bad escape verbatim.
fn check_escape(text : String, at : @span.Offset) -> (@span.Offset, @diagnostic.Diagnostic?) {
  match unit_at(text, at.next()) {
    Some('\\' | '"' | 'b' | 'f' | 'n' | 'r' | 't' | '/') => (at.next().next(), None)
    Some('u') => {
      let mut end = at.next().next()
      let mut good = 0
      while good < 4 && unit_at(text, end) is Some(c) && is_hex(c) {
        end = end.next()
        good += 1
      }
      if good < 4 {
        (
          end,
          Some(
            lexical(
              "SM-SCAN-006",
              "INVALID UNICODE ESCAPE",
              "a `\\u` escape needs exactly four hex digits",
              at.to(end),
              hint="Write the code point as four hex digits, like `\\u00e9`.",
            ),
          ),
        )
      } else {
        (end, None)
      }
    }
    Some(c) => {
      let end = at.next().next()
      (
        end,
        Some(
          lexical(
            "SM-SCAN-005",
            "UNKNOWN ESCAPE",
            "I don't know the escape `\\\{c}`",
            at.to(end),
            notes=[
              "The escapes I know are `\\\\`, `\\\"`, `\\b`, `\\f`, `\\n`, `\\r`, `\\t`, `\\/` and `\\uXXXX`.",
            ],
          ),
        ),
      )
    }
    None => (at.next(), None)
  }
}

///|
/// A quoted string (which may span lines) or a text block.
fn scan_string_or_text_block(text : String, at : @span.Offset) -> Step {
  if looking_at(text, at, "\"\"\"") {
    scan_text_block(text, at)
  } else {
    scan_quoted(text, at)
  }
}

///|
/// Read string content from `from` until `closer` matches. The offset of
/// the closer (or the end of the text) and the escape diagnostics found.
fn string_body(text : String, from : @span.Offset, closer : String) -> (@span.Offset, Array[@diagnostic.Diagnostic]) {
  let found : Array[@diagnostic.Diagnostic] = []
  let mut at = from
  while unit_at(text, at) is Some(c) {
    if c == '"' && looking_at(text, at, closer) {
      return (at, found)
    }
    if c == '\\' {
      let (after, d) = check_escape(text, at)
      if d is Some(x) {
        found.push(x)
      }
      at = after
    } else {
      at = at.next()
    }
  }
  (at, found)
}

///|
fn scan_quoted(text : String, at : @span.Offset) -> Step {
  let (closer, found) = string_body(text, at.next(), "\"")
  match unit_at(text, closer) {
    Some(_) => {
      let end = closer.next()
      { piece: Tok(String, slice(text, at, end), at.to(end)), end, diagnostics: found[:] }
    }
    None =>
      error_step(
        text,
        at,
        closer,
        lexical(
          "SM-SCAN-002",
          "UNTERMINATED STRING",
          "this string never ends",
          at.to(closer),
          hint="Add the closing `\"`.",
          notes=[
            "I found an opening quote but reached the end of the file before the closing one. A string may span lines, so I read everything after the quote as the string.",
          ],
        ),
      )
  }
}

///|
/// `TextBlock = ThreeDquotes [SP] NL *TextBlockContent ThreeDquotes`.
fn scan_text_block(text : String, at : @span.Offset) -> Step {
  let three = @span.Length::new(3).unwrap()
  let after_quotes = skip_while(text, at.advance(three), c => c == ' ' || c == '\t')
  let (content_start, has_break) = match unit_at(text, after_quotes) {
    Some('\n') => (after_quotes.next(), true)
    Some('\r') if peek(text, after_quotes, 1) == Some('\n') => (after_quotes.next().next(), true)
    _ => (at.advance(three), false)
  }
  let found : Array[@diagnostic.Diagnostic] = []
  if !has_break {
    found.push(
      lexical(
        "SM-SCAN-004",
        "TEXT BLOCK MUST START WITH A LINE BREAK",
        "the opening `\"\"\"` must be followed by a line break",
        at.to(content_start),
        hint="Put the text on the line after the opening quotes, and the closing quotes on their own line.",
      ),
    )
  }
  let (closer, escapes) = string_body(text, content_start, "\"\"\"")
  found.append(escapes)
  match unit_at(text, closer) {
    Some(_) => {
      let end = closer.advance(three)
      { piece: Tok(TextBlock, slice(text, at, end), at.to(end)), end, diagnostics: found[:] }
    }
    None =>
      error_step(
        text,
        at,
        closer,
        lexical(
          "SM-SCAN-003",
          "UNTERMINATED TEXT BLOCK",
          "this text block never ends",
          at.to(closer),
          hint="Add the closing `\"\"\"`.",
        ),
      )
  }
}
```

- [ ] **Step 6: Run the string tests**

Run: `moon test -p moonrockz/smithy-syntax/scanner`
Expected: string tests pass.

- [ ] **Step 7: Write the failing decoder tests (Review Focus 2 lives here)**

`scanner/decode_test.mbt`:

```moonbit
///|
test "unescape decodes the known escapes and keeps unknown ones" {
  @expect.expect_all(e => {
    e.expect(@scanner.unescape("\"\"")).to_equal("")
    e.expect(@scanner.unescape("\"a\\nb\"")).to_equal(
      (
        #|a
        #|b
      ),
    )
    e.expect(@scanner.unescape("\"\\t\\r\\b\\f\\/\\\\\\\"\"")).to_equal("\t\r\u{8}\u{c}/\\\"")
    e.expect(@scanner.unescape("\"\\u00e9\"")).to_equal("é")
    e.expect(@scanner.unescape("\"\\uD83D\\uDE00\"")).to_equal("\u{1F600}")
    e.expect(@scanner.unescape("\"a\\qb\"")).to_equal("a\\qb")
    e.expect(@scanner.unescape("\"\\u12\"")).to_equal("\\u12")
  })
}

///|
test "text_block_value removes incidental whitespace" {
  let block = (
    #|"""
    #|    hello
    #|      world
    #|    """
  )
  inspect(@scanner.text_block_value(block), content=(
    #|hello
    #|  world
    #|
  ))
}

///|
test "the closing quotes on the content's last line keep that line" {
  let block = (
    #|"""
    #|  a
    #|  b"""
  )
  inspect(@scanner.text_block_value(block), content=(
    #|a
    #|b
  ))
}

///|
test "the closing quotes' own line counts toward the common prefix" {
  let block = (
    #|"""
    #|      deep
    #|  """
  )
  inspect(@scanner.text_block_value(block), content=(
    #|    deep
    #|
  ))
}

///|
test "a closing delimiter at the margin keeps all indentation" {
  let block = (
    #|"""
    #|    kept
    #|"""
  )
  inspect(@scanner.text_block_value(block), content=(
    #|    kept
    #|
  ))
}

///|
test "trailing spaces are removed and escapes run after stripping" {
  let block = "\"\"\"\n  a   \n  b\\tc\n  \"\"\""
  inspect(@scanner.text_block_value(block), content="a\nb\tc\n")
}

///|
test "an escaped line break joins lines" {
  let block = (
    #|"""
    #|  a\
    #|  b
    #|  """
  )
  inspect(@scanner.text_block_value(block), content=(
    #|ab
    #|
  ))
}

///|
test "CRLF inside a text block is a line break" {
  let block = "\"\"\"\r\n  a\r\n  b\r\n  \"\"\""
  inspect(@scanner.text_block_value(block), content=(
    #|a
    #|b
    #|
  ))
}

///|
test "quotes inside a text block" {
  let block = (
    #|"""
    #|  say "hi" or ""hey""
    #|  """
  )
  inspect(@scanner.text_block_value(block), content=(
    #|say "hi" or ""hey""
    #|
  ))
}
```

- [ ] **Step 8: Implement decode.mbt (pure functions from lexeme to value)**

```moonbit
///|
/// The decoded form of `s`: the escapes the specification lists; an
/// unknown or malformed escape is kept verbatim; `\` before a line break
/// (text blocks) adds nothing.
fn decode_escapes(s : String) -> String {
  let sb = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.code_unit_at(i).to_int().unsafe_to_char()
    if c != '\\' || i + 1 >= n {
      sb.write_char(c)
      i += 1
      continue
    }
    let e = s.code_unit_at(i + 1).to_int().unsafe_to_char()
    match e {
      '\\' | '"' | '/' => {
        sb.write_char(e)
        i += 2
      }
      'b' => {
        sb.write_char('\u{8}')
        i += 2
      }
      'f' => {
        sb.write_char('\u{c}')
        i += 2
      }
      'n' => {
        sb.write_char('\n')
        i += 2
      }
      'r' => {
        sb.write_char('\r')
        i += 2
      }
      't' => {
        sb.write_char('\t')
        i += 2
      }
      '\n' => i += 2
      'u' => {
        let mut value = 0
        let mut good = 0
        while good < 4 && i + 2 + good < n {
          let h = s.code_unit_at(i + 2 + good).to_int().unsafe_to_char()
          guard is_hex(h) else { break }
          let d = if is_digit(h) {
            h.to_int() - '0'.to_int()
          } else if h >= 'a' {
            h.to_int() - 'a'.to_int() + 10
          } else {
            h.to_int() - 'A'.to_int() + 10
          }
          value = value * 16 + d
          good += 1
        }
        if good == 4 {
          sb.write_char(value.unsafe_to_char())
          i += 6
        } else {
          sb.write_char('\\')
          i += 1
        }
      }
      _ => {
        sb.write_char('\\')
        i += 1
      }
    }
  }
  sb.to_string()
}

///|
/// The value of a `String` token: the lexeme with its quotes removed and
/// its escapes decoded.
pub fn unescape(lexeme : String) -> String {
  let inner = if lexeme.length() >= 2 {
    lexeme.unsafe_substring(start=1, end=lexeme.length() - 1)
  } else {
    ""
  }
  decode_escapes(inner)
}

///|
fn leading_spaces(line : String) -> Int {
  let mut k = 0
  while k < line.length() && line.code_unit_at(k).to_int() == ' '.to_int() {
    k += 1
  }
  k
}

///|
fn is_blank(line : String) -> Bool {
  leading_spaces(line) == line.length()
}

///|
/// The lines of a text block body, line breaks removed (`\r\n` and `\n`).
fn block_lines(body : String) -> Array[String] {
  body.split(
    (
      #|
      #|
    ),
  ).map(raw => raw.to_string().trim_end(chars="\r").to_string()).collect()
}

///|
/// The common leading-space count: over the non-blank lines, and over the
/// last line even when blank (it holds the closing quotes' indent).
fn common_indent(lines : Array[String]) -> Int {
  let last = lines.length() - 1
  let mut common = -1
  for idx, line in lines {
    if idx != last && is_blank(line) {
      continue
    }
    let k = leading_spaces(line)
    if common < 0 || k < common {
      common = k
    }
  }
  if common < 0 { 0 } else { common }
}

///|
/// The value of a `TextBlock` token, per the specification: drop the
/// opening quotes, optional spaces and the first line break; split the rest
/// into lines; remove the common indent and trailing spaces; join with
/// `\n`; then decode escapes.
pub fn text_block_value(lexeme : String) -> String {
  let n = lexeme.length()
  guard n >= 6 else { return "" }
  let mut i = 3
  while i < n && (lexeme.code_unit_at(i).to_int() == ' '.to_int() || lexeme.code_unit_at(i).to_int() == '\t'.to_int()) {
    i += 1
  }
  if i < n && lexeme.code_unit_at(i).to_int() == '\r'.to_int() {
    i += 1
  }
  if i < n && lexeme.code_unit_at(i).to_int() == '\n'.to_int() {
    i += 1
  }
  let lines = block_lines(lexeme.unsafe_substring(start=i, end=n - 3))
  let common = common_indent(lines)
  let last = lines.length() - 1
  lines
  .mapi((idx, line) => {
    if idx == last && is_blank(line) {
      // The closing quotes stood on their own line: the value ends with `\n`.
      ""
    } else {
      let cut = if leading_spaces(line) < common { leading_spaces(line) } else { common }
      line.unsafe_substring(start=cut, end=line.length()).trim_end(chars=" ").to_string()
    }
  })
  .join(
    (
      #|
      #|
    ),
  )
  |> decode_escapes
}
```

- [ ] **Step 9: Run every scanner test**

Run: `moon test -p moonrockz/smithy-syntax/scanner`
Expected: all pass. If `trim_end` returns a view that needs `.to_string()` differently on this toolchain, adjust; the behavior is what the tests pin.

- [ ] **Step 10: Format and commit**

```bash
mise run format
git add pkgs/smithy-syntax/src/scanner
git commit -m "feat(syntax): scan numbers, strings and text blocks, and decode their values"
```

---

### Task 6: `lawkit` generators and the scanner laws

**Files:**
- Create: `pkgs/smithy-syntax/src/lawkit/moon.pkg`
- Create: `pkgs/smithy-syntax/src/lawkit/smithy_text.mbt`
- Create: `pkgs/smithy-syntax/src/lawkit/smithy_text_test.mbt`
- Create: `pkgs/smithy-syntax/src/scanner/scanner_law_test.mbt`
- Modify: `pkgs/smithy-syntax/src/scanner/moon.pkg` (test imports)

**Interfaces:**
- Produces: `@lawkit.SmithyText` (quickcheck `Arbitrary` and `Shrink`) with `text()`; `@lawkit.token_pieces()`, `@lawkit.broken_pieces()`, `@lawkit.edge_chars()`, `@lawkit.small_model()` (a valid 2.0 model), `@lawkit.units(Array[Int]) -> String`.

- [ ] **Step 1: Write the generator package**

`lawkit/moon.pkg`:

```
import {
  "moonbitlang/core/quickcheck",
  "moonbitlang/core/quickcheck/splitmix",
}

import {
  "moonrockz/smithy-syntax/lawkit",
  "moonbitlang/core/quickcheck",
  "moonbitlang/core/debug",
} for "test"
```

`lawkit/smithy_text.mbt`:

```moonbit
///|
/// A string of these UTF-16 code units. A string literal cannot hold a
/// lone surrogate; this can.
pub fn units(xs : Array[Int]) -> String {
  let sb = StringBuilder()
  for x in xs {
    sb.write_char(x.unsafe_to_char())
  }
  sb.to_string()
}

///|
/// Characters at the edges of what the scanner handles: lone surrogates, a
/// pair, CR, CRLF, LF, tab, a byte order mark, ASCII, non-ASCII, nothing.
pub fn edge_chars() -> Array[String] {
  [
    units([0xD800]),
    units([0xDC00]),
    units([0xD83D, 0xDE00]),
    "\r",
    "\r\n",
    "\n",
    "\t",
    "\u{FEFF}",
    "a",
    "é",
    "€",
    "",
  ]
}

///|
/// Token texts of the Smithy IDL, one of each kind, plus keywords.
pub fn token_pieces() -> Array[String] {
  [
    "namespace", "use", "metadata", "apply", "structure", "list", "map", "set",
    "union", "enum", "intEnum", "service", "resource", "operation", "string",
    "integer", "blob", "boolean", "document", "byte", "short", "long", "float",
    "double", "bigInteger", "bigDecimal", "timestamp", "with", "for", "input",
    "output", "errors", "true", "false", "null", "Foo", "foo_bar", "_x", "__y1",
    "smithy.api#String", "Foo$bar", "0", "42", "-1", "1.5", "1e3", "\"\"",
    "\"hi\"", "\"a\\nb\"", "\"\"\"\n  x\n  \"\"\"", "@", ":", ":=", "=", ".",
    "#", "$", "{", "}", "[", "]", "(", ")", ",", " ", "\n", "\r\n", "\t", "//",
    "///", "// c", "/// d", "$version: \"2\"",
  ]
}

///|
/// Fragments the scanner rejects: open strings and blocks, bad escapes,
/// bad numbers, odd characters.
pub fn broken_pieces() -> Array[String] {
  [
    "\"", "\"abc", "\\", "\"\\q\"", "\"\\u", "\"\\u12\"", "\"\"\"", "\"\"\"x\"\"\"",
    "01", "1.", "1e", "1e+", "-", "-a", "^", "&", ";", "'", "`", "~", "|", "!",
    "?", "%", "*", "+", "<", ">", "\u{00A0}", "\u{201C}",
  ]
}

///|
/// A small valid Smithy 2.0 model: every statement form, every shape
/// kind, docs, traits, mixins, elision, an inline shape and an apply.
pub fn small_model() -> String {
  (
    #|$version: "2"
    #|
    #|metadata foo = ["bar"]
    #|
    #|namespace smithy.example
    #|
    #|use smithy.api#String
    #|
    #|/// Docs.
    #|@deprecated(message: "old")
    #|structure Foo with [Mix] {
    #|    @required
    #|    bar: String = "x"
    #|    $baz
    #|}
    #|
    #|@mixin
    #|structure Mix {
    #|    baz: Integer
    #|}
    #|
    #|enum Color {
    #|    RED = "red"
    #|    BLUE
    #|}
    #|
    #|list Names {
    #|    member: String
    #|}
    #|
    #|service Shop {
    #|    version: "2024-01-01"
    #|    operations: [GetFoo]
    #|}
    #|
    #|operation GetFoo {
    #|    input := {
    #|        id: String
    #|    }
    #|    output: Foo
    #|    errors: [NotFound]
    #|}
    #|
    #|@error("client")
    #|structure NotFound {}
    #|
    #|apply Foo @since("1.0")
    #|
  )
}

///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn one_of(rs : @splitmix.RandomState, xs : Array[String]) -> String {
  xs[pick(rs, xs.length())]
}

///|
/// One piece: a token, a broken fragment, an edge character, an edge
/// character inside a literal or comment form, or a cut of the small model.
fn piece(rs : @splitmix.RandomState) -> String {
  match pick(rs, 10) {
    0 | 1 | 2 => one_of(rs, token_pieces())
    3 | 4 => one_of(rs, broken_pieces())
    5 | 6 => one_of(rs, edge_chars())
    7 => {
      let edge = one_of(rs, edge_chars())
      match pick(rs, 6) {
        0 => "\"" + edge + "\""
        1 => "\"" + edge
        2 => "// " + edge
        3 => "/// " + edge + "\n"
        4 => "\"\\" + edge + "\""
        _ => "\"\"\"\n" + edge + "\n\"\"\""
      }
    }
    _ => {
      let m = small_model()
      let cut = pick(rs, m.length() + 1)
      if pick(rs, 2) == 0 {
        m.unsafe_substring(start=0, end=cut)
      } else {
        m.unsafe_substring(start=cut, end=m.length())
      }
    }
  }
}

///|
/// Text that is mostly not valid Smithy, for laws that must hold for any
/// text: no crash, lossless scan, spans in bounds. It is a list of pieces;
/// `text()` joins them. It shrinks by dropping a piece or halving the
/// longest one.
pub(all) struct SmithyText(Array[String]) derive(Debug)

///|
pub fn SmithyText::text(self : SmithyText) -> String {
  self.0.join("")
}

///|
pub impl @quickcheck.Arbitrary for SmithyText with fn arbitrary(size, rs) {
  SmithyText(Array::makei(pick(rs, size + 1), _ => piece(rs)))
}

///|
pub impl @quickcheck.Shrink for SmithyText with fn shrink(self) {
  let SmithyText(parts) = self
  let out = Array::makei(parts.length(), i => {
    let fewer = parts.copy()
    ignore(fewer.remove(i))
    SmithyText(fewer)
  })
  let mut longest = -1
  for i, p in parts {
    if p.length() > 1 && (longest < 0 || p.length() > parts[longest].length()) {
      longest = i
    }
  }
  if longest >= 0 {
    let halved = parts.copy()
    let p = parts[longest]
    halved[longest] = p.unsafe_substring(start=0, end=p.length() / 2)
    out.push(SmithyText(halved))
  }
  out.iter()
}
```

`lawkit/smithy_text_test.mbt`:

```moonbit
///|
test "the generator produces text and shrinks toward fewer pieces" {
  let t = @lawkit.SmithyText(["a", "bcd"])
  inspect(t.text(), content="abcd")
  let shrunk : Array[@lawkit.SmithyText] = @quickcheck.Shrink::shrink(t).collect()
  inspect(shrunk.length(), content="3")
}

///|
test "the small model is non-empty and ends with a line break" {
  let m = @lawkit.small_model()
  inspect(m.length() > 100, content="true")
  inspect(m.has_suffix(
    (
      #|
      #|
    ),
  ), content="true")
}
```

Add `"moonrockz/smithy-syntax/lawkit"` to the scanner's test imports in `scanner/moon.pkg`.

- [ ] **Step 2: Write the scanner laws**

`scanner/scanner_law_test.mbt`:

```moonbit
///|
test "law: the scan is lossless for any text" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      @scanner.tokenize_text(text).to_source() == text
    },
    count=400,
    max_size=16,
    seed=2031,
  )
}

///|
test "law: scan_at is pure and its steps chain to the end of the text" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      let mut at = @span.Offset::zero()
      let mut ok = true
      while @scanner.scan_at(text, at) is Some(step) {
        ok = ok && step.end > at && @scanner.scan_at(text, at) == Some(step)
        at = step.end
      }
      ok && at.0 == text.length()
    },
    count=400,
    max_size=16,
    seed=2037,
  )
}

///|
test "law: token and trivia spans tile the text in order" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      let s = @scanner.tokenize_text(text)
      let mut at = @span.Offset::zero()
      let mut ok = true
      let step = (span : @span.Span) => {
        ok = ok && span.start == at
        at = span.end()
      }
      for tr in s.trivia {
        step(tr.span())
      }
      for tok in s.tokens {
        for tr in tok.trivia_before {
          step(tr.span())
        }
        step(tok.span)
        for tr in tok.trivia_after {
          step(tr.span())
        }
      }
      ok && at.0 == text.length()
    },
    count=400,
    max_size=16,
    seed=2032,
  )
}

///|
test "law: every Error token has exactly one diagnostic that starts inside it" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let s = @scanner.tokenize_text(t.text())
      let errors = s.tokens.iter().filter(tok => tok.kind == Error).collect()
      let error_codes = ["SM-SCAN-001", "SM-SCAN-002", "SM-SCAN-003", "SM-SCAN-007"]
      let error_diags = s.diagnostics.iter().filter(d => error_codes.contains(d.code)).collect()
      if errors.length() != error_diags.length() {
        return false
      }
      let mut ok = true
      for i, tok in errors {
        let d = error_diags[i]
        ok = ok && d.span.start >= tok.span.start && d.span.start <= tok.span.end()
      }
      ok
    },
    count=400,
    max_size=16,
    seed=2033,
  )
}

///|
test "law: a lexeme is the source text of its span" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      let s = @scanner.tokenize_text(text)
      s.tokens.iter().all(tok => text.unsafe_substring(start=tok.span.start.0, end=tok.span.end().0) == tok.lexeme)
    },
    count=300,
    max_size=16,
    seed=2034,
  )
}

///|
test "law: trivia_after holds at most one newline, and it is last" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let s = @scanner.tokenize_text(t.text())
      let mut ok = true
      for i, tok in s.tokens {
        if i == s.tokens.length() - 1 {
          continue
        }
        let newlines = tok.trivia_after.iter().filter(x => x.is_newline()).count()
        ok = ok && newlines <= 1
        if newlines == 1 {
          ok = ok && tok.trivia_after[tok.trivia_after.length() - 1].is_newline()
        }
      }
      ok
    },
    count=300,
    max_size=16,
    seed=2035,
  )
}

///|
test "law: every diagnostic code is in the table" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let s = @scanner.tokenize_text(t.text())
      s.diagnostics.iter().all(d => @diagnostic.description(d.code) is Some(_))
    },
    count=300,
    max_size=16,
    seed=2036,
  )
}
```

- [ ] **Step 3: Run the laws on two targets**

Run: `moon test -p moonrockz/smithy-syntax/scanner && moon test -p moonrockz/smithy-syntax/scanner --target js`
Expected: all pass. A failing law prints a shrunk counterexample; fix the scanner, not the law, unless the law mis-states the spec.

- [ ] **Step 4: Format and commit**

```bash
mise run format
git add pkgs/smithy-syntax/src/lawkit pkgs/smithy-syntax/src/scanner
git commit -m "test(syntax): add the lawkit text generator and the scanner laws"
```

---

### Task 7: `ast` package

**Files:**
- Create: `pkgs/smithy-syntax/src/ast/moon.pkg`
- Create: `pkgs/smithy-syntax/src/ast/node.mbt`
- Create: `pkgs/smithy-syntax/src/ast/values.mbt`
- Create: `pkgs/smithy-syntax/src/ast/shapes.mbt`
- Create: `pkgs/smithy-syntax/src/ast/file.mbt`
- Create: `pkgs/smithy-syntax/src/ast/ast_test.mbt`
- Create: `pkgs/smithy-syntax/src/ast/README.mbt.md`

**Interfaces:**
- Consumes: `@span.Span`, `@decimal.Decimal` (from `moonbitlang/x/decimal`), `BigInt`.
- Produces: every type below, exactly with these names and fields. Later tasks build and match on them.

- [ ] **Step 1: Write the package manifest and the leaf types**

`ast/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax/span",
  "moonbitlang/x/decimal",
  "moonbitlang/core/bigint",
}

import {
  "moonrockz/smithy-syntax/ast",
  "moonrockz/smithy-syntax/span",
  "moonrockz/expect",
  "moonbitlang/core/debug",
} for "test"
```

`ast/node.mbt`:

```moonbit
///|
/// A leaf value with its span.
pub(all) struct Node[T] {
  value : T
  span : @span.Span
} derive(Eq, Debug)

///|
pub fn[T] Node::new(value : T, span : @span.Span) -> Node[T] {
  { value, span }
}

///|
/// A syntactic, unresolved shape ID: `namespace#name$member`. A relative
/// ID has no namespace; resolution against `use` statements and the
/// prelude is the loader's job.
pub(all) struct ShapeId {
  namespace : String?
  name : String
  member : String?
} derive(Eq, Debug, Hash)

///|
pub fn ShapeId::new(name : String, namespace? : String, member? : String) -> ShapeId {
  { namespace, name, member }
}

///|
pub fn ShapeId::is_absolute(self : ShapeId) -> Bool {
  self.namespace is Some(_)
}

///|
/// The ID as written: `ns#name$member`.
pub impl Show for ShapeId with output(self, logger) {
  match self.namespace {
    Some(ns) => {
      logger.write_string(ns)
      logger.write_string("#")
    }
    None => ()
  }
  logger.write_string(self.name)
  match self.member {
    Some(m) => {
      logger.write_string("$")
      logger.write_string(m)
    }
    None => ()
  }
}

///|
/// One `///` line, the slashes stripped, the line break not included.
pub(all) struct DocComment {
  text : String
  span : @span.Span
} derive(Eq, Debug)
```

- [ ] **Step 2: Write the node value types**

`ast/values.mbt`:

```moonbit
///|
/// The exact value of a number literal.
pub(all) enum NumberValue {
  Integer(BigInt)
  Decimal(@decimal.Decimal)
} derive(Eq, Debug)

///|
/// A number literal: the lexeme as written and its exact value.
pub(all) struct NumberLiteral {
  text : String
  value : NumberValue
} derive(Eq, Debug)

///|
/// The value as an `Int64` when it is an integer that fits.
pub fn NumberLiteral::as_int64(self : NumberLiteral) -> Int64? {
  match self.value {
    Integer(b) => if b >= BigInt::from_int64(-9223372036854775807L - 1L) && b <= BigInt::from_int64(9223372036854775807L) {
      Some(b.to_int64())
    } else {
      None
    }
    Decimal(_) => None
  }
}

///|
/// The value as a `Double` (lossy for large integers and long decimals).
pub fn NumberLiteral::as_double(self : NumberLiteral) -> Double {
  match self.value {
    Integer(b) => b.to_double()
    Decimal(d) => d.to_double()
  }
}

///|
pub(all) enum Keyword {
  True
  False
  Null
} derive(Eq, Debug, Hash)

///|
/// `NodeObjectKvp`: a key (an identifier or a quoted string) and a value.
pub(all) struct NodeKvp {
  key : Node[String]
  value : NodeValue
  span : @span.Span
} derive(Eq, Debug)

///|
/// `NodeValue`. Strings hold their decoded value; `ShapeId` is a bare
/// identifier or shape ID in value position (`@foo(bar)`).
pub(all) enum NodeValue {
  Array(ArrayView[NodeValue], @span.Span)
  Object(ArrayView[NodeKvp], @span.Span)
  Number(NumberLiteral, @span.Span)
  Keyword(Keyword, @span.Span)
  String(String, @span.Span)
  TextBlock(String, @span.Span)
  ShapeId(ShapeId, @span.Span)
} derive(Eq, Debug)

///|
pub fn NodeValue::span(self : NodeValue) -> @span.Span {
  match self {
    Array(_, s) | Object(_, s) | Number(_, s) | Keyword(_, s) => s
    String(_, s) | TextBlock(_, s) | ShapeId(_, s) => s
  }
}

///|
/// The string value of a `String` or `TextBlock`, else `None`.
pub fn NodeValue::as_string(self : NodeValue) -> String? {
  match self {
    String(s, _) | TextBlock(s, _) => Some(s)
    _ => None
  }
}

///|
/// The value of `key` in an object, else `None`.
pub fn NodeValue::get(self : NodeValue, key : String) -> NodeValue? {
  guard self is Object(kvps, _) else { return None }
  for kvp in kvps {
    if kvp.key.value == key {
      return Some(kvp.value)
    }
  }
  None
}
```

- [ ] **Step 3: Write the shape types**

`ast/shapes.mbt`:

```moonbit
///|
pub(all) enum SimpleType {
  Blob
  Boolean
  Document
  String
  Byte
  Short
  Integer
  Long
  Float
  Double
  BigInteger
  BigDecimal
  Timestamp
} derive(Eq, Debug, Hash)

///|
/// The simple type named by a keyword, or `None`.
pub fn SimpleType::of(word : String) -> SimpleType? {
  match word {
    "blob" => Some(Blob)
    "boolean" => Some(Boolean)
    "document" => Some(Document)
    "string" => Some(String)
    "byte" => Some(Byte)
    "short" => Some(Short)
    "integer" => Some(Integer)
    "long" => Some(Long)
    "float" => Some(Float)
    "double" => Some(Double)
    "bigInteger" => Some(BigInteger)
    "bigDecimal" => Some(BigDecimal)
    "timestamp" => Some(Timestamp)
    _ => None
  }
}

///|
pub fn SimpleType::keyword(self : SimpleType) -> String {
  match self {
    Blob => "blob"
    Boolean => "boolean"
    Document => "document"
    String => "string"
    Byte => "byte"
    Short => "short"
    Integer => "integer"
    Long => "long"
    Float => "float"
    Double => "double"
    BigInteger => "bigInteger"
    BigDecimal => "bigDecimal"
    Timestamp => "timestamp"
  }
}

///|
pub(all) enum EnumType {
  Enum
  IntEnum
} derive(Eq, Debug, Hash)

///|
/// `Set` is Smithy 1.0 syntax; it parses in every version and the loader
/// decides what it means.
pub(all) enum AggregateType {
  List
  Map
  Union
  Structure
  Set
} derive(Eq, Debug, Hash)

///|
pub(all) enum EntityType {
  Service
  Resource
} derive(Eq, Debug, Hash)

///|
/// Every shape keyword, for recovery and for `ShapeKind` in the CST.
pub(all) enum ShapeKind {
  Simple(SimpleType)
  Enum(EnumType)
  Aggregate(AggregateType)
  Entity(EntityType)
  Operation
} derive(Eq, Debug, Hash)

///|
/// `Simple(String)`, `Aggregate(Structure)`, ... for messages and CST names.
pub impl Show for ShapeKind with output(self, logger) {
  match self {
    Simple(t) => logger.write_string("Simple(\{t.keyword()})")
    Enum(Enum) => logger.write_string("Enum(Enum)")
    Enum(IntEnum) => logger.write_string("Enum(IntEnum)")
    Aggregate(t) => logger.write_string("Aggregate(\{t.keyword()})")
    Entity(Service) => logger.write_string("Entity(Service)")
    Entity(Resource) => logger.write_string("Entity(Resource)")
    Operation => logger.write_string("Operation")
  }
}

///|
pub fn AggregateType::keyword(self : AggregateType) -> String {
  match self {
    List => "List"
    Map => "Map"
    Union => "Union"
    Structure => "Structure"
    Set => "Set"
  }
}

///|
/// The shape kind a keyword starts, or `None`.
pub fn ShapeKind::of(word : String) -> ShapeKind? {
  match word {
    "enum" => Some(Enum(Enum))
    "intEnum" => Some(Enum(IntEnum))
    "list" => Some(Aggregate(List))
    "map" => Some(Aggregate(Map))
    "union" => Some(Aggregate(Union))
    "structure" => Some(Aggregate(Structure))
    "set" => Some(Aggregate(Set))
    "service" => Some(Entity(Service))
    "resource" => Some(Entity(Resource))
    "operation" => Some(Operation)
    _ => SimpleType::of(word).map(t => Simple(t))
  }
}

///|
/// `with [A, B]`.
pub(all) struct Mixins {
  ids : ArrayView[Node[ShapeId]]
  span : @span.Span
} derive(Eq, Debug)

///|
/// `@id`, `@id(value)` or `@id(key: value, ...)`. `@id()` is
/// `Structure([])`.
pub(all) enum TraitBody {
  Structure(ArrayView[NodeKvp])
  Node(NodeValue)
} derive(Eq, Debug)

///|
pub(all) struct Trait {
  id : Node[ShapeId]
  body : TraitBody?
  span : @span.Span
} derive(Eq, Debug)

///|
/// `name: Target` or the elided `$name`.
pub(all) enum MemberTarget {
  Explicit(Node[ShapeId])
  Elided
} derive(Eq, Debug)

///|
pub(all) struct Member {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  name : Node[String]
  target : MemberTarget
  default : NodeValue?
  span : @span.Span
} derive(Eq, Debug)

///|
pub(all) struct EnumMember {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  name : Node[String]
  value : NodeValue?
  span : @span.Span
} derive(Eq, Debug)

///|
/// `:= { ... }` with its own traits, `for` and mixins.
pub(all) struct InlineShape {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  for_resource : Node[ShapeId]?
  mixins : Mixins?
  members : ArrayView[Member]
  span : @span.Span
} derive(Eq, Debug)

///|
pub(all) enum OperationTarget {
  Reference(Node[ShapeId])
  Inline(InlineShape)
} derive(Eq, Debug)

///|
pub(all) enum OperationProperty {
  Input(OperationTarget, @span.Span)
  Output(OperationTarget, @span.Span)
  Errors(ArrayView[Node[ShapeId]], @span.Span)
} derive(Eq, Debug)

///|
/// `Shape`, one case per grammar production. `name` is the identifier
/// after the keyword.
pub(all) enum Shape {
  Simple(kind~ : SimpleType, name~ : Node[String], mixins~ : Mixins?)
  Enum(
    kind~ : EnumType,
    name~ : Node[String],
    mixins~ : Mixins?,
    members~ : ArrayView[EnumMember]
  )
  Aggregate(
    kind~ : AggregateType,
    name~ : Node[String],
    for_resource~ : Node[ShapeId]?,
    mixins~ : Mixins?,
    members~ : ArrayView[Member]
  )
  Entity(
    kind~ : EntityType,
    name~ : Node[String],
    mixins~ : Mixins?,
    body~ : NodeValue
  )
  Operation(
    name~ : Node[String],
    mixins~ : Mixins?,
    properties~ : ArrayView[OperationProperty]
  )
} derive(Eq, Debug)

///|
pub fn Shape::name(self : Shape) -> Node[String] {
  match self {
    Simple(name~, ..) | Enum(name~, ..) | Aggregate(name~, ..) => name
    Entity(name~, ..) | Operation(name~, ..) => name
  }
}

///|
pub fn Shape::kind(self : Shape) -> ShapeKind {
  match self {
    Simple(kind~, ..) => Simple(kind)
    Enum(kind~, ..) => Enum(kind)
    Aggregate(kind~, ..) => Aggregate(kind)
    Entity(kind~, ..) => Entity(kind)
    Operation(..) => Operation
  }
}
```

- [ ] **Step 4: Write the file-level types**

`ast/file.mbt`:

```moonbit
///|
/// `$key: value`.
pub(all) struct ControlStatement {
  key : Node[String]
  value : NodeValue
  span : @span.Span
} derive(Eq, Debug)

///|
/// `metadata key = value`.
pub(all) struct MetadataStatement {
  key : Node[String]
  value : NodeValue
  span : @span.Span
} derive(Eq, Debug)

///|
/// `namespace a.b.c`.
pub(all) struct NamespaceStatement {
  namespace : Node[String]
  span : @span.Span
} derive(Eq, Debug)

///|
/// `use a.b#Name`.
pub(all) struct UseStatement {
  id : Node[ShapeId]
  span : @span.Span
} derive(Eq, Debug)

///|
/// Doc comments and traits, then the shape.
pub(all) struct ShapeStatement {
  docs : ArrayView[DocComment]
  traits : ArrayView[Trait]
  shape : Shape
  span : @span.Span
} derive(Eq, Debug)

///|
/// `apply Target @trait` or `apply Target { @a @b }`.
pub(all) struct ApplyStatement {
  target : Node[ShapeId]
  traits : ArrayView[Trait]
  block : Bool
  span : @span.Span
} derive(Eq, Debug)

///|
pub(all) enum Statement {
  Shape(ShapeStatement)
  Apply(ApplyStatement)
} derive(Eq, Debug)

///|
pub fn Statement::span(self : Statement) -> @span.Span {
  match self {
    Shape(s) => s.span
    Apply(a) => a.span
  }
}

///|
/// One IDL file: control section, metadata section, then the shape section
/// (`namespace`, `use` statements, shape and apply statements).
pub(all) struct IdlFile {
  control : ArrayView[ControlStatement]
  metadata : ArrayView[MetadataStatement]
  namespace : NamespaceStatement?
  uses : ArrayView[UseStatement]
  statements : ArrayView[Statement]
  span : @span.Span
} derive(Eq, Debug)

///|
/// The shape statements, without the apply statements.
pub fn IdlFile::shapes(self : IdlFile) -> Array[ShapeStatement] {
  let out = []
  for s in self.statements {
    if s is Shape(sh) {
      out.push(sh)
    }
  }
  out
}

///|
/// The value of the `$key` control statement, else `None`.
pub fn IdlFile::control_value(self : IdlFile, key : String) -> NodeValue? {
  for c in self.control {
    if c.key.value == key {
      return Some(c.value)
    }
  }
  None
}
```

- [ ] **Step 5: Write the tests**

`ast/ast_test.mbt`:

```moonbit
///|
fn sp(a : Int, b : Int) -> @span.Span raise {
  guard @span.Offset::new(a) is Some(x) && @span.Offset::new(b) is Some(y) else { fail("bad span") }
  x.to(y)
}

///|
test "shape ids print as written" {
  inspect(@ast.ShapeId::new("String", namespace="smithy.api"), content="smithy.api#String")
  inspect(@ast.ShapeId::new("Foo", member="bar"), content="Foo$bar")
  inspect(@ast.ShapeId::new("Foo").is_absolute(), content="false")
}

///|
test "keywords map to shape kinds" {
  @expect.expect_all(e => {
    e.expect(@ast.ShapeKind::of("structure")).to_equal(Some(Aggregate(Structure)))
    e.expect(@ast.ShapeKind::of("intEnum")).to_equal(Some(Enum(IntEnum)))
    e.expect(@ast.ShapeKind::of("bigDecimal")).to_equal(Some(Simple(BigDecimal)))
    e.expect(@ast.ShapeKind::of("operation")).to_equal(Some(Operation))
    e.expect(@ast.ShapeKind::of("apply")).to_equal(None)
    e.expect(@ast.SimpleType::Timestamp.keyword()).to_equal("timestamp")
    e.expect(@ast.ShapeKind::Aggregate(Structure).to_string()).to_equal("Aggregate(Structure)")
    e.expect(@ast.ShapeKind::Simple(String).to_string()).to_equal("Simple(string)")
  })
}

///|
test "number literals convert" {
  let i : @ast.NumberLiteral = { text: "42", value: Integer(BigInt::from_int(42)) }
  inspect(i.as_int64(), content="Some(42)")
  inspect(i.as_double(), content="42")
  let huge : @ast.NumberLiteral = {
    text: "99999999999999999999",
    value: Integer(BigInt::from_string("99999999999999999999")),
  }
  inspect(huge.as_int64(), content="None")
}

///|
test "node values expose strings and object keys" {
  let obj : @ast.NodeValue = Object(
    [{ key: @ast.Node::new("a", sp(1, 2)), value: String("x", sp(4, 7)), span: sp(1, 7) }][:],
    sp(0, 8),
  )
  inspect(obj.get("a").bind(v => v.as_string()), content="Some(\"x\")")
  inspect(obj.get("b"), content="None")
  debug_inspect(obj.span(), content="{ start: Offset(0), length: Length(8) }")
}

///|
test "a shape reports its name and kind" {
  let s : @ast.Shape = Simple(kind=String, name=@ast.Node::new("Foo", sp(7, 10)), mixins=None)
  inspect(s.name().value, content="Foo")
  debug_inspect(s.kind(), content="Simple(String)")
}
```

- [ ] **Step 6: Run the tests**

Run: `moon test -p moonrockz/smithy-syntax/ast`
Expected: all pass.

- [ ] **Step 7: README and commit**

`ast/README.mbt.md`:

````markdown
# ast

The typed Smithy IDL tree. Every node has a `span`; every list is a
read-only `ArrayView`; shape IDs are syntactic and unresolved.

```mbt check
test {
  let id = @ast.ShapeId::new("String", namespace="smithy.api")
  inspect(id, content="smithy.api#String")
}
```
````

```bash
mise run format
git add pkgs/smithy-syntax/src/ast
git commit -m "feat(syntax): add the IDL AST types"
```

---

### Task 8: `cst` package

**Files:**
- Create: `pkgs/smithy-syntax/src/cst/moon.pkg`
- Create: `pkgs/smithy-syntax/src/cst/types.mbt`
- Create: `pkgs/smithy-syntax/src/cst/cst_test.mbt`
- Create: `pkgs/smithy-syntax/src/cst/README.mbt.md`

**Interfaces:**
- Consumes: `@scanner.Token`, `@scanner.TokenStream`, `@scanner.Trivia`, `@ast.ShapeKind`, `@span.Span`.
- Produces: `StatementKind = Control | Metadata | Namespace | Use | Shape(@ast.ShapeKind) | Apply | Skipped`; `StatementCst { kind, name : String?, tokens : ArrayView[Token], span }` with `StatementCst::new(kind~, name~, tokens~)` and `to_source()`; `IdlCst { tokens, trivia, statements }` with `IdlCst::new(stream, statements)`, `to_source()`, `skipped() -> Array[StatementCst]`.

- [ ] **Step 1: Write the failing tests**

`cst/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax/span",
  "moonrockz/smithy-syntax/scanner",
  "moonrockz/smithy-syntax/ast",
}

import {
  "moonrockz/smithy-syntax/cst",
  "moonrockz/smithy-syntax/scanner",
  "moonrockz/expect",
  "moonbitlang/core/debug",
} for "test"
```

`cst/cst_test.mbt`:

```moonbit
///|
fn o(n : Int) -> @span.Offset raise {
  guard @span.Offset::new(n) is Some(x) else { fail("bad offset") }
  x
}

///|
test "statements tile the stream and print the source back" {
  let text = (
    #|namespace a.b
    #|
    #|string Foo // c
    #|
  )
  let s = @scanner.tokenize_text(text)
  let ns = @cst.StatementCst::new(kind=Namespace, name=Some("a.b"), tokens=s.tokens[0:4])
  let foo = @cst.StatementCst::new(kind=Shape(Simple(String)), name=Some("Foo"), tokens=s.tokens[4:6])
  let cst = @cst.IdlCst::new(s, [ns, foo])
  @expect.expect_all(e => {
    e.expect(cst.to_source()).to_equal(text)
    // Trivia after a token stops at its first line break; the blank line
    // belongs to the next token, so it prints with `string`.
    e.expect(ns.to_source()).to_equal(
      (
        #|namespace a.b
        #|
      ),
    )
    e.expect(foo.to_source()).to_equal(
      (
        #|
        #|string Foo // c
        #|
      ),
    )
    e.expect(ns.span).to_equal(o(0).to(o(13)))
    e.expect(foo.span).to_equal(o(15).to(o(25)))
    e.expect(cst.skipped().length()).to_equal(0)
  })
}

///|
test "an empty statement has an empty span" {
  let s = @scanner.tokenize_text("")
  let st = @cst.StatementCst::new(kind=Skipped, name=None, tokens=s.tokens[0:0])
  debug_inspect(st.span, content="{ start: Offset(0), length: Length(0) }")
  inspect(@cst.IdlCst::new(s, [st]).to_source(), content="")
}

///|
test "a text with only trivia prints back" {
  let s = @scanner.tokenize_text(
    (
      #|// only
      #|
    ),
  )
  inspect(@cst.IdlCst::new(s, []).to_source(), content=(
    #|// only
    #|
  ))
}
```

Add `"moonrockz/smithy-syntax/span"` to the test imports.

- [ ] **Step 2: Implement types.mbt**

```moonbit
///|
/// What a statement's tokens parsed as. `Skipped` is a run the parser
/// reported and skipped (recovery per statement).
pub(all) enum StatementKind {
  Control
  Metadata
  Namespace
  Use
  Shape(@ast.ShapeKind)
  Apply
  Skipped
} derive(Eq, Debug)

///|
/// `Control`, `Shape(Aggregate(Structure))`, ... for tests and tools.
pub impl Show for StatementKind with output(self, logger) {
  match self {
    Control => logger.write_string("Control")
    Metadata => logger.write_string("Metadata")
    Namespace => logger.write_string("Namespace")
    Use => logger.write_string("Use")
    Shape(k) => logger.write_string("Shape(\{k})")
    Apply => logger.write_string("Apply")
    Skipped => logger.write_string("Skipped")
  }
}

///|
/// The tokens of one statement, with their trivia. `name` is the control
/// key, metadata key, namespace, used shape ID, shape name or apply
/// target; `None` for a skipped run. `span` runs from the first token's
/// start to the last token's end, trivia excluded; empty at 0 with no token.
pub(all) struct StatementCst {
  kind : StatementKind
  name : String?
  tokens : ArrayView[@scanner.Token]
  span : @span.Span
} derive(Eq, Debug)

///|
pub fn StatementCst::new(
  kind~ : StatementKind,
  name~ : String?,
  tokens~ : ArrayView[@scanner.Token],
) -> StatementCst {
  let span = if tokens.length() == 0 {
    @span.Offset::zero().to(@span.Offset::zero())
  } else {
    tokens[0].span.start.to(tokens[tokens.length() - 1].span.end())
  }
  { kind, name, tokens, span }
}

///|
/// The text of the statement's tokens with their trivia.
pub fn StatementCst::to_source(self : StatementCst) -> String {
  let sb = StringBuilder()
  for t in self.tokens {
    sb.write_string(t.to_source())
  }
  sb.to_string()
}

///|
/// Every token of a file, grouped per statement. `statements` tile
/// `tokens` in order; `trivia` is the stream's trivia for a text with no
/// token.
pub(all) struct IdlCst {
  tokens : ArrayView[@scanner.Token]
  trivia : ArrayView[@scanner.Trivia]
  statements : ArrayView[StatementCst]
} derive(Eq, Debug)

///|
pub fn IdlCst::new(
  stream : @scanner.TokenStream,
  statements : Array[StatementCst],
) -> IdlCst {
  { tokens: stream.tokens, trivia: stream.trivia, statements: statements[:] }
}

///|
/// The scanned text, byte for byte.
pub fn IdlCst::to_source(self : IdlCst) -> String {
  let sb = StringBuilder()
  for t in self.trivia {
    sb.write_string(t.text())
  }
  for token in self.tokens {
    sb.write_string(token.to_source())
  }
  sb.to_string()
}

///|
/// The runs the parser skipped.
pub fn IdlCst::skipped(self : IdlCst) -> Array[StatementCst] {
  self.statements.iter().filter(s => s.kind == Skipped).collect()
}
```

- [ ] **Step 3: Run the tests, write the README, commit**

Run: `moon test -p moonrockz/smithy-syntax/cst`
Expected: all pass.

`cst/README.mbt.md`:

````markdown
# cst

The token stream grouped per statement. `IdlCst::to_source()` is the text
byte for byte, also when the parser skipped a statement.

```mbt check
test {
  let s = @scanner.tokenize_text("string Foo\n")
  let st = @cst.StatementCst::new(kind=Shape(Simple(String)), name=Some("Foo"), tokens=s.tokens)
  inspect(@cst.IdlCst::new(s, [st]).to_source(), content="string Foo\n")
}
```
````

```bash
mise run format
git add pkgs/smithy-syntax/src/cst
git commit -m "feat(syntax): add the statement-level CST"
```

---

### Task 9: Parser core: lookahead, errors, file sections, the line-break rule

**Files:**
- Create: `pkgs/smithy-syntax/src/parser/moon.pkg`
- Create: `pkgs/smithy-syntax/src/parser/error.mbt`
- Create: `pkgs/smithy-syntax/src/parser/parser.mbt`
- Create: `pkgs/smithy-syntax/src/parser/file.mbt`
- Create: `pkgs/smithy-syntax/src/parser/values.mbt` (stub `parse_node_value` for this task; Task 10 fills it)
- Create: `pkgs/smithy-syntax/src/parser/file_test.mbt`

**Interfaces:**
- Consumes: scanner, ast, cst, diagnostic, span.
- Produces: `Version = V1 | V2`; `ParseResult { ast : @ast.IdlFile?, cst : @cst.IdlCst, version : Version?, diagnostics : ArrayView[Diagnostic] }` with `has_errors()`, `errors()`; `parse(SourceText) -> ParseResult`; `parse_tokens(TokenStream) -> ParseResult`; `parse_text(String) -> ParseResult`; `Depth` (a nesting count: `Depth::zero()`, `deeper()`, `shallower()`, `Compare`), `max_nesting : Depth`; `suberror ParseError { ParseError(@diagnostic.Diagnostic) }`. Internal helpers later tasks call: `Parser::peek() -> Token?`, `peek1()`, `advance()`, `at_keyword(word)`, `expect_kind(kind, what) -> Token raise ParseError`, `expect_identifier(what)`, `adjacent()`, `expect_br()`, `fail(code, title, message, span, ...) -> T raise ParseError`, `push_context(name, span)`, `pop_context()`, `enter()`, `leave()`, `take_docs_before(offset : @span.Offset) -> Array[DocComment]`, `parse_shape_id() -> Node[ShapeId] raise ParseError`, `parse_node_value() -> NodeValue raise ParseError`.

- [ ] **Step 1: Write the error and result types**

`parser/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax/span",
  "moonrockz/smithy-syntax/diagnostic",
  "moonrockz/smithy-syntax/scanner",
  "moonrockz/smithy-syntax/ast",
  "moonrockz/smithy-syntax/cst",
  "moonbitlang/x/decimal",
  "moonbitlang/core/bigint",
}

import {
  "moonrockz/smithy-syntax/parser",
  "moonrockz/smithy-syntax/span",
  "moonrockz/smithy-syntax/diagnostic",
  "moonrockz/smithy-syntax/scanner",
  "moonrockz/smithy-syntax/ast",
  "moonrockz/smithy-syntax/cst",
  "moonrockz/smithy-syntax/lawkit",
  "moonrockz/expect",
  "moonbitlang/core/debug",
  "moonbitlang/core/quickcheck",
} for "test"
```

`parser/error.mbt`:

```moonbit
///|
/// A syntax error, carrying its finished diagnostic. Raised inside a
/// statement; `parse` catches it, records it and recovers.
pub(all) suberror ParseError {
  ParseError(@diagnostic.Diagnostic)
} derive(Debug)

///|
pub fn ParseError::diagnostic(self : ParseError) -> @diagnostic.Diagnostic {
  let ParseError(d) = self
  d
}

///|
/// The IDL version a file declares with `$version`.
pub(all) enum Version {
  V1
  V2
} derive(Eq, Debug, Hash)

///|
/// `1`, `1.0`, `2`, `2.0`, else `None`.
pub fn Version::of(text : String) -> Version? {
  match text {
    "1" | "1.0" => Some(V1)
    "2" | "2.0" => Some(V2)
    _ => None
  }
}

///|
/// What `parse` returns. `ast` is `None` only when nothing at all could be
/// read; otherwise it is the (possibly partial) tree. `cst` has every
/// token. `version` is the declared `$version`, `None` when absent.
pub(all) struct ParseResult {
  ast : @ast.IdlFile?
  cst : @cst.IdlCst
  version : Version?
  diagnostics : ArrayView[@diagnostic.Diagnostic]
} derive(Debug)

///|
pub fn ParseResult::has_errors(self : ParseResult) -> Bool {
  self.diagnostics.iter().any(d => d.is_error())
}

///|
pub fn ParseResult::errors(self : ParseResult) -> Array[@diagnostic.Diagnostic] {
  self.diagnostics.iter().filter(d => d.is_error()).collect()
}

///|
/// A nesting count of node values, member blocks and trait bodies.
pub struct Depth(Int) derive(Eq, Compare, Debug)

///|
pub fn Depth::zero() -> Depth {
  Depth(0)
}

///|
pub fn Depth::deeper(self : Depth) -> Depth {
  Depth(self.0 + 1)
}

///|
pub fn Depth::shallower(self : Depth) -> Depth {
  if self.0 > 0 {
    Depth(self.0 - 1)
  } else {
    self
  }
}

///|
/// Deepest nesting the parser enters; deeper text is `SM-PARSE-010`, never
/// a stack overflow.
pub let max_nesting : Depth = Depth(100)
```

- [ ] **Step 2: Write the parser state and helpers**

`parser/parser.mbt`:

```moonbit
///|
/// A construct the parser is inside, for titles and secondary labels.
priv struct Context {
  what : String
  span : @span.Span
}

///|
/// The parser state over a token stream. `Error` tokens are holes: `peek`
/// skips them (the scanner already reported them).
priv struct Parser {
  tokens : ArrayView[@scanner.Token]
  text_end : @span.Offset
  /// The array index of the next token; an index, so an `Int`.
  mut pos : Int
  mut depth : Depth
  contexts : Array[Context]
  diagnostics : Array[@diagnostic.Diagnostic]
  /// Every doc comment in order, and the first one not yet taken.
  doc_comments : Array[@ast.DocComment]
  mut doc_head : Int
  mut version : Version?
}

///|
fn Parser::new(stream : @scanner.TokenStream) -> Parser {
  let doc_comments : Array[@ast.DocComment] = []
  fn gather(trivia : ArrayView[@scanner.Trivia]) {
    for t in trivia {
      if t is Comment(c) && c.kind == Doc {
        doc_comments.push({ text: c.text, span: c.span })
      }
    }
  }

  gather(stream.trivia)
  for token in stream.tokens {
    gather(token.trivia_before)
    gather(token.trivia_after)
  }
  let text_end = @span.Offset::zero().advance(@span.Length::of_string(stream.to_source()))
  let p = {
    tokens: stream.tokens,
    text_end,
    pos: 0,
    depth: Depth::zero(),
    contexts: [],
    diagnostics: [],
    doc_comments,
    doc_head: 0,
    version: None,
  }
  p.skip_holes()
  p
}

///|
fn Parser::skip_holes(self : Parser) -> Unit {
  while self.pos < self.tokens.length() && self.tokens[self.pos].kind == Error {
    self.pos += 1
  }
}

///|
fn Parser::peek(self : Parser) -> @scanner.Token? {
  if self.pos < self.tokens.length() {
    Some(self.tokens[self.pos])
  } else {
    None
  }
}

///|
/// The token after `peek()`, holes skipped.
fn Parser::peek1(self : Parser) -> @scanner.Token? {
  let mut i = self.pos + 1
  while i < self.tokens.length() && self.tokens[i].kind == Error {
    i += 1
  }
  if i < self.tokens.length() {
    Some(self.tokens[i])
  } else {
    None
  }
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.tokens.length()
}

///|
fn Parser::advance(self : Parser) -> @scanner.Token? {
  let t = self.peek()
  if t is Some(_) {
    self.pos += 1
    self.skip_holes()
  }
  t
}

///|
/// Whether `peek()` is the identifier `word`.
fn Parser::at_keyword(self : Parser, word : String) -> Bool {
  self.peek() is Some(t) && t.kind == Identifier && t.lexeme == word
}

///|
fn Parser::at_kind(self : Parser, kind : @scanner.TokenKind) -> Bool {
  self.peek() is Some(t) && t.kind == kind
}

///|
/// Whether no trivia separates `peek()` from the token before it.
fn Parser::adjacent(self : Parser) -> Bool {
  guard self.pos > 0 && self.pos < self.tokens.length() else { return false }
  let prev = self.tokens[self.pos - 1]
  let cur = self.tokens[self.pos]
  prev.trivia_after.length() == 0 && cur.trivia_before.length() == 0 && prev.span.end() == cur.span.start
}

///|
/// Where an error with no better place goes: the current token, or the end
/// of the text.
fn Parser::here(self : Parser) -> @span.Span {
  match self.peek() {
    Some(t) => t.span
    None => self.text_end.to(self.text_end)
  }
}

///|
/// How the current token reads in a message: "`foo`", "end of file".
fn Parser::found(self : Parser) -> String {
  match self.peek() {
    None => "the end of the file"
    Some(t) =>
      match t.kind {
        String | TextBlock => "a string"
        Number => "the number `\{t.lexeme}`"
        _ => "`\{t.lexeme}`"
      }
  }
}

///|
fn Parser::push_context(self : Parser, what : String, span : @span.Span) -> Unit {
  self.contexts.push({ what, span })
}

///|
fn Parser::pop_context(self : Parser) -> Unit {
  ignore(self.contexts.pop())
}

///|
/// Build and raise a diagnostic. The innermost context gives a secondary
/// label ("the structure started here") and the first note.
fn[T] Parser::fail(
  self : Parser,
  code : String,
  title : String,
  message : String,
  span : @span.Span,
  notes? : Array[String],
  hint? : String,
  example? : String,
  labels? : Array[@diagnostic.Label],
) -> T raise ParseError {
  let code = if self.peek() is None && code == "SM-PARSE-001" {
    "SM-PARSE-002"
  } else {
    code
  }
  let base = @diagnostic.Diagnostic::new(
    code~,
    severity=Error,
    title~,
    message~,
    span~,
    labels?,
    notes?,
    hint?,
    example?,
  )
  raise ParseError(
    match self.contexts.last() {
      Some(c) =>
        base.with_context(
          { span: c.span, text: "\{c.what} started here" },
          "I was parsing \{c.what} when I got stuck.",
        )
      None => base
    },
  )
}

///|
/// Record a diagnostic without raising (warnings, and errors the parser
/// can continue past).
fn Parser::report(
  self : Parser,
  code : String,
  severity : @diagnostic.Severity,
  title : String,
  message : String,
  span : @span.Span,
  notes? : Array[String],
  hint? : String,
) -> Unit {
  self.diagnostics.push(
    @diagnostic.Diagnostic::new(code~, severity~, title~, message~, span~, notes?, hint?),
  )
}

///|
/// `peek()` must have `kind`; `what` names it in the error ("a `{`").
fn Parser::expect_kind(
  self : Parser,
  kind : @scanner.TokenKind,
  what : String,
) -> @scanner.Token raise ParseError {
  match self.peek() {
    Some(t) if t.kind == kind => {
      ignore(self.advance())
      t
    }
    _ =>
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting \{what} but found \{self.found()}",
        self.here(),
      )
  }
}

///|
fn Parser::expect_identifier(self : Parser, what : String) -> @ast.Node[String] raise ParseError {
  let t = self.expect_kind(Identifier, what)
  @ast.Node::new(t.lexeme, t.span)
}

///|
/// The grammar's `BR`: after a statement there must be a line break or a
/// comment before the next token (or the end of the file).
fn Parser::expect_br(self : Parser) -> Unit raise ParseError {
  guard self.pos > 0 else { return }
  guard self.peek() is Some(next) else { return }
  let prev = self.tokens[self.pos - 1]
  let has_break = prev.trivia_after.iter().any(t => t.is_newline() || t.is_comment()) ||
    next.trivia_before.iter().any(t => t.is_newline() || t.is_comment())
  if !has_break {
    self.fail(
      "SM-PARSE-003",
      "MISSING LINE BREAK",
      "I was expecting a line break here but found \{self.found()}",
      next.span,
      notes=[
        "Each statement must end with a line break (or a comment, which ends at a line break). Commas are whitespace in Smithy, so a comma does not separate statements.",
      ],
      hint="Put `\{next.lexeme}` on its own line.",
    )
  }
}

///|
fn Parser::enter(self : Parser) -> Unit raise ParseError {
  self.depth = self.depth.deeper()
  if self.depth > max_nesting {
    self.fail(
      "SM-PARSE-010",
      "TOO MUCH NESTING",
      "this is nested more than \{max_nesting.0} levels deep",
      self.here(),
      hint="Flatten the value; nothing in Smithy needs nesting this deep.",
    )
  }
}

///|
fn Parser::leave(self : Parser) -> Unit {
  self.depth = self.depth.shallower()
}

///|
/// The pending doc comments that start before `offset`, in order.
fn Parser::take_docs_before(self : Parser, offset : @span.Offset) -> Array[@ast.DocComment] {
  let out = []
  while self.doc_head < self.doc_comments.length() &&
        self.doc_comments[self.doc_head].span.start < offset {
    out.push(self.doc_comments[self.doc_head])
    self.doc_head += 1
  }
  out
}

///|
/// Report every pending doc comment before `offset` as detached.
fn Parser::detach_docs_before(self : Parser, offset : @span.Offset) -> Unit {
  for d in self.take_docs_before(offset) {
    self.report(
      "SM-PARSE-009",
      Warning,
      "DETACHED DOC COMMENT",
      "this documentation comment is not followed by a shape or member",
      d.span,
      notes=[
        "A `///` comment documents the shape, member or enum member that comes right after it. Nothing here can take documentation, so I ignored it.",
      ],
      hint="Move it right before the shape it documents, or make it a `//` comment.",
    )
  }
}

///|
/// `ShapeId = RootShapeId [ShapeIdMember]`, assembled from adjacent tokens:
/// `a.b#Name$member`. A dotted name without `#` is an error.
fn Parser::parse_shape_id(self : Parser) -> @ast.Node[@ast.ShapeId] raise ParseError {
  let first = self.expect_identifier("a shape ID")
  let start = first.span.start
  let mut end = first.span.end()
  let parts = [first.value]
  let mut namespace : String? = None
  let mut name = first.value
  let mut saw_dot = false
  while self.at_kind(Dot) && self.adjacent() {
    saw_dot = true
    ignore(self.advance())
    guard self.adjacent() && self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-005",
        "INVALID SHAPE ID",
        "I was expecting a namespace segment after `.`",
        self.here(),
        hint="A namespace looks like `com.example`, with no spaces around the dots.",
      )
    }
    let seg = self.expect_identifier("a namespace segment")
    parts.push(seg.value)
    end = seg.span.end()
  }
  if self.at_kind(Pound) && self.adjacent() {
    ignore(self.advance())
    guard self.adjacent() && self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-005",
        "INVALID SHAPE ID",
        "I was expecting a shape name after `#`",
        self.here(),
        example="smithy.api#String",
      )
    }
    let n = self.expect_identifier("a shape name")
    namespace = Some(parts.join("."))
    name = n.value
    end = n.span.end()
  } else if saw_dot {
    self.fail(
      "SM-PARSE-005",
      "INVALID SHAPE ID",
      "`\{parts.join(".")}` looks like a namespace, but a shape ID needs `#` and a shape name after it",
      start.to(end),
      hint="Write `\{parts.join(".")}#Name`, or just `Name` for a shape in this namespace.",
    )
  }
  let mut member : String? = None
  if self.at_kind(Dollar) && self.adjacent() {
    ignore(self.advance())
    guard self.adjacent() && self.at_kind(Identifier) else {
      self.fail(
        "SM-PARSE-005",
        "INVALID SHAPE ID",
        "I was expecting a member name after `$`",
        self.here(),
        example="Foo$bar",
      )
    }
    let m = self.expect_identifier("a member name")
    member = Some(m.value)
    end = m.span.end()
  }
  @ast.Node::new({ namespace, name, member }, start.to(end))
}
```

- [ ] **Step 3: Write the file-section parser with recovery (shape statements come in Task 11; here they are reported as "not yet supported" only through the stub, so keep tests to the sections)**

`parser/file.mbt`:

```moonbit
///|
/// Keywords that start a statement, for recovery and dispatch.
fn statement_keyword(word : String) -> Bool {
  word == "namespace" || word == "use" || word == "metadata" || word == "apply" ||
  @ast.ShapeKind::of(word) is Some(_)
}

///|
/// Whether the token at `i` is the first on its line.
fn Parser::first_on_line(self : Parser, i : Int) -> Bool {
  guard i >= 0 && i < self.tokens.length() else { return false }
  if i == 0 {
    return true
  }
  let prev = self.tokens[i - 1]
  prev.trivia_after.iter().any(t => t.is_newline()) ||
  self.tokens[i].trivia_before.iter().any(t => t.is_newline())
}

///|
/// Whether the token at `i` starts a statement for recovery: first on its
/// line and a statement keyword, `@`, `$`, or preceded by a doc comment.
fn Parser::at_statement_start(self : Parser, i : Int) -> Bool {
  guard self.first_on_line(i) else { return false }
  let t = self.tokens[i]
  match t.kind {
    At | Dollar => true
    Identifier => statement_keyword(t.lexeme)
    _ => t.trivia_before.iter().any(x => x is Comment(c) && c.kind == Doc)
  }
}

///|
/// Skip from `from` to the next statement start (or the end), and record
/// the run as `Skipped`.
fn Parser::recover(self : Parser, from : Int, out : Array[@cst.StatementCst]) -> Unit {
  let mut i = from + 1
  while i < self.tokens.length() && !self.at_statement_start(i) {
    i += 1
  }
  out.push(@cst.StatementCst::new(kind=Skipped, name=None, tokens=self.tokens[from:i]))
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
fn Parser::parse_control(self : Parser) -> @ast.ControlStatement raise ParseError {
  let dollar = self.expect_kind(Dollar, "`$`")
  self.push_context("a control statement", dollar.span)
  let key = self.parse_object_key()
  ignore(self.expect_kind(Colon, "`:` after the control key"))
  let value = self.parse_node_value()
  self.expect_br()
  self.pop_context()
  if key.value == "version" {
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
  { key, value, span: dollar.span.join(value.span()) }
}

///|
/// `MetadataStatement = "metadata" SP NodeObjectKey [SP] "=" [SP] NodeValue BR`.
fn Parser::parse_metadata(self : Parser) -> @ast.MetadataStatement raise ParseError {
  let kw = self.expect_kind(Identifier, "`metadata`")
  self.push_context("a metadata statement", kw.span)
  let key = self.parse_object_key()
  ignore(self.expect_kind(Equal, "`=` after the metadata key"))
  let value = self.parse_node_value()
  self.expect_br()
  self.pop_context()
  { key, value, span: kw.span.join(value.span()) }
}

///|
/// `NamespaceStatement = "namespace" SP Namespace BR`.
fn Parser::parse_namespace(self : Parser) -> @ast.NamespaceStatement raise ParseError {
  let kw = self.expect_kind(Identifier, "`namespace`")
  self.push_context("a namespace statement", kw.span)
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
        self.here(),
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
  { namespace: @ast.Node::new(parts.join("."), span), span: kw.span.join(span) }
}

///|
/// `UseStatement = "use" SP AbsoluteRootShapeId BR`.
fn Parser::parse_use(self : Parser) -> @ast.UseStatement raise ParseError {
  let kw = self.expect_kind(Identifier, "`use`")
  self.push_context("a use statement", kw.span)
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
  { id, span: kw.span.join(id.span) }
}

///|
/// A shape or apply statement. Task 11 implements this; until then every
/// statement start is reported.
fn Parser::parse_shape_or_apply(self : Parser) -> @ast.Statement raise ParseError {
  self.fail(
    "SM-PARSE-004",
    "EXPECTED A STATEMENT",
    "shape statements are not supported yet",
    self.here(),
  )
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
  let mut section = ControlSection
  let mut read_anything = false
  while !p.at_end() {
    let start_index = p.pos
    guard p.peek() is Some(t) else { break }
    let start_offset = t.span.start
    let outcome = try {
      // Section dispatch on the first token of the statement.
      if t.kind == Dollar && p.peek1() is Some(k) && k.kind == Identifier && p.first_on_line(start_index) && section is ControlSection {
        p.detach_docs_before(start_offset)
        let c = p.parse_control()
        control.push(c)
        Ok((@cst.StatementKind::Control, Some(c.key.value)))
      } else if p.at_keyword("metadata") && (section is ControlSection || section is MetadataSection) {
        p.detach_docs_before(start_offset)
        section = MetadataSection
        let m = p.parse_metadata()
        metadata.push(m)
        Ok((@cst.StatementKind::Metadata, Some(m.key.value)))
      } else if p.at_keyword("namespace") && namespace is None && !(section is UseSection || section is ShapeSection) {
        p.detach_docs_before(start_offset)
        section = NamespaceSection
        let n = p.parse_namespace()
        namespace = Some(n)
        Ok((@cst.StatementKind::Namespace, Some(n.namespace.value)))
      } else if p.at_keyword("use") && (section is NamespaceSection || section is UseSection) {
        p.detach_docs_before(start_offset)
        section = UseSection
        let u = p.parse_use()
        uses.push(u)
        Ok((@cst.StatementKind::Use, Some(u.id.value.to_string())))
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
          @cst.StatementCst::new(kind~, name~, tokens=p.tokens[start_index:p.pos]),
        )
      }
      Err(e) => {
        p.diagnostics.push(e.diagnostic())
        p.recover(start_index, cst_statements)
      }
    }
  }
  p.detach_docs_before(p.text_end.next())
  let ast : @ast.IdlFile? = if read_anything {
    Some({
      control: control[:],
      metadata: metadata[:],
      namespace,
      uses: uses[:],
      statements: statements[:],
      span: @span.Offset::zero().to(p.text_end),
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
  let all = scanner.to_array()
  all.append(parser.to_array())
  all.sort_by((a, b) => a.span.start.compare(b.span.start))
  all
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
fn[T] Parser::expected_statement(self : Parser, section : Section, has_namespace : Bool) -> T raise ParseError {
  let expected = match section {
    ControlSection => "a control statement (`$version: \"2\"`), `metadata`, or `namespace`"
    MetadataSection => "`metadata` or `namespace`"
    NamespaceSection | UseSection => "`use`, a shape statement, or `apply`"
    ShapeSection => "a shape statement or `apply`"
  }
  let notes = if !has_namespace && (self.at_keyword("use") || self.at_keyword("apply") || (self.peek() is Some(t) && t.kind == Identifier && @ast.ShapeKind::of(t.lexeme) is Some(_))) {
    ["Shapes, `use` and `apply` can only appear after a `namespace` statement."]
  } else if self.at_keyword("namespace") {
    ["A file has one `namespace` statement, and it must come before any `use`, shape or `apply` statement."]
  } else if self.at_keyword("metadata") || (self.peek() is Some(t) && t.kind == Dollar) {
    ["Control statements (`$...`) come first, then `metadata`, then `namespace`."]
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
pub fn parse_text(text : String) -> ParseResult {
  @span.SourceText::new(text) |> parse
}
```

`parser/values.mbt` stub for this task (Task 10 replaces it):

```moonbit
///|
/// `NodeObjectKey = QuotedText / Identifier`.
fn Parser::parse_object_key(self : Parser) -> @ast.Node[String] raise ParseError {
  match self.peek() {
    Some(t) if t.kind == Identifier => {
      ignore(self.advance())
      @ast.Node::new(t.lexeme, t.span)
    }
    Some(t) if t.kind == String => {
      ignore(self.advance())
      @ast.Node::new(@scanner.unescape(t.lexeme), t.span)
    }
    _ =>
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting a key (an identifier or a quoted string) but found \{self.found()}",
        self.here(),
      )
  }
}

///|
/// Task 10 fills this in; for now only quoted strings.
fn Parser::parse_node_value(self : Parser) -> @ast.NodeValue raise ParseError {
  let t = self.expect_kind(String, "a value")
  String(@scanner.unescape(t.lexeme), t.span)
}
```

- [ ] **Step 4: Write the failing tests for the sections and the BR rule**

`parser/file_test.mbt`:

```moonbit
///|
fn codes(text : String) -> Array[String] {
  @parser.parse_text(text).diagnostics.iter().map(d => d.code).collect()
}

///|
test "control, metadata, namespace and use parse in order" {
  let r = @parser.parse_text(
    (
      #|$version: "2"
      #|metadata a = "x"
      #|namespace com.foo
      #|use smithy.api#String
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  @expect.expect_all(e => {
    e.expect(r.has_errors()).to_be_false()
    e.expect(r.version).to_equal(Some(V2))
    e.expect(f.control.length()).to_equal(1)
    e.expect(f.metadata[0].key.value).to_equal("a")
    e.expect(f.namespace.map(n => n.namespace.value)).to_equal(Some("com.foo"))
    e.expect(f.uses[0].id.value.to_string()).to_equal("smithy.api#String")
    e.expect(r.cst.statements.length()).to_equal(4)
    e.expect(r.cst.to_source()).to_equal(
      (
        #|$version: "2"
        #|metadata a = "x"
        #|namespace com.foo
        #|use smithy.api#String
        #|
      ),
    )
  })
}

///|
test "an unsupported version is SM-PARSE-006" {
  @expect.expect(codes(
    (
      #|$version: "3"
      #|
    ),
  )).to_equal(["SM-PARSE-006"])
  @expect.expect(codes(
    (
      #|$version: "1.0"
      #|
    ),
  )).to_equal([])
  inspect(@parser.parse_text(
    (
      #|$version: "1"
      #|
    ),
  ).version, content="Some(V1)")
  inspect(@parser.parse_text(
    (
      #|namespace a
      #|
    ),
  ).version, content="None")
}

///|
test "two statements on one line is MISSING LINE BREAK, also with CRLF files" {
  @expect.expect(codes(
    (
      #|namespace a use b#C
      #|
    ),
  )).to_equal(["SM-PARSE-003"])
  @expect.expect(codes("namespace a\r\nuse b#C\r\n")).to_equal([])
  @expect.expect(codes(
    (
      #|namespace a // ok
      #|use b#C
      #|
    ),
  )).to_equal([])
  let r = @parser.parse_text(
    (
      #|namespace a use b#C
      #|
    ),
  )
  inspect(r.diagnostics[0].title, content="MISSING LINE BREAK")
  inspect(r.diagnostics[0].message, content="I was expecting a line break here but found `use`")
}

///|
test "statements out of order are EXPECTED A STATEMENT with a note" {
  let r = @parser.parse_text(
    (
      #|namespace a
      #|metadata x = "y"
      #|
    ),
  )
  @expect.expect(codes(
    (
      #|namespace a
      #|metadata x = "y"
      #|
    ),
  )).to_equal(["SM-PARSE-004"])
  inspect(r.diagnostics[0].notes[0], content="Control statements (`$...`) come first, then `metadata`, then `namespace`.")
  @expect.expect(codes(
    (
      #|use a#B
      #|
    ),
  )).to_equal(["SM-PARSE-004"])
}

///|
test "a use statement needs an absolute id" {
  @expect.expect(codes(
    (
      #|namespace a
      #|use Foo
      #|
    ),
  )).to_equal(["SM-PARSE-005"])
  @expect.expect(codes(
    (
      #|namespace a
      #|use a.b#Foo$bar
      #|
    ),
  )).to_equal(["SM-PARSE-005"])
}

///|
test "recovery skips to the next statement and keeps the CST lossless" {
  let text = (
    #|namespace a
    #|use Foo
    #|use smithy.api#String
    #|
  )
  let r = @parser.parse_text(text)
  guard r.ast is Some(f) else { fail("no ast") }
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(f.uses.length()).to_equal(1)
    e.expect(r.cst.skipped().length()).to_equal(1)
    e.expect(r.cst.skipped()[0].to_source()).to_equal(
      (
        #|use Foo
        #|
      ),
    )
    e.expect(r.cst.to_source()).to_equal(text)
  })
}

///|
test "an empty file has no ast and no errors" {
  let r = @parser.parse_text("")
  inspect(r.ast is None, content="true")
  inspect(r.has_errors(), content="false")
  inspect(@parser.parse_text(
    (
      #|// just a comment
      #|
    ),
  ).ast is None, content="true")
}

///|
test "doc comments before a namespace are detached warnings" {
  let r = @parser.parse_text(
    (
      #|/// hi
      #|namespace a
      #|
    ),
  )
  @expect.expect(codes(
    (
      #|/// hi
      #|namespace a
      #|
    ),
  )).to_equal(["SM-PARSE-009"])
  inspect(r.has_errors(), content="false")
  inspect(r.diagnostics[0].title, content="DETACHED DOC COMMENT")
}

///|
test "a scanner error is a hole the parser steps over" {
  let r = @parser.parse_text(
    (
      #|namespace a
      #|^
      #|use a#B
      #|
    ),
  )
  @expect.expect(codes(
    (
      #|namespace a
      #|^
      #|use a#B
      #|
    ),
  )).to_equal(["SM-SCAN-001"])
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(f.uses.length(), content="1")
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `moon test -p moonrockz/smithy-syntax/parser`
Expected: all pass. The last test depends on `skip_holes` running after `recover` and in `advance`; if the `^` leaves the `use` unparsed, check that `Parser::new` skipped the hole before the first `peek`.

- [ ] **Step 6: Add the Depth laws**

`parser/depth_law_test.mbt`:

```moonbit
///|
test "law: deeper then shallower is the identity, and shallower never goes below zero" {
  @quickcheck.check(
    (n : Int) => {
      let d = {
        let mut d = @parser.Depth::zero()
        for _ in 0..<(if n < 0 { 0 } else { n % 200 }) {
          d = d.deeper()
        }
        d
      }
      d.deeper().shallower() == d &&
      @parser.Depth::zero().shallower() == @parser.Depth::zero() &&
      d.deeper() > d &&
      (d > @parser.max_nesting) == (d.0 > 100)
    },
    count=300,
    seed=1011,
  )
}
```

Run: `moon test -p moonrockz/smithy-syntax/parser`

- [ ] **Step 7: Format and commit**

```bash
mise run format
git add pkgs/smithy-syntax/src/parser
git commit -m "feat(syntax): parse the control, metadata, namespace and use sections with recovery"
```

---

### Task 10: Node values and the nesting limit

**Files:**
- Modify: `pkgs/smithy-syntax/src/parser/values.mbt` (replace the stub)
- Create: `pkgs/smithy-syntax/src/parser/values_test.mbt`

**Interfaces:**
- Produces: `Parser::parse_node_value() -> @ast.NodeValue raise ParseError`, `Parser::parse_object_kvps(close : TokenKind, what : String) -> Array[@ast.NodeKvp] raise ParseError` (reads kvps until `close`, used by trait bodies too), `Parser::parse_number(token) -> @ast.NumberLiteral`.

- [ ] **Step 1: Write the failing tests (Review Focus 4 lives here)**

`parser/values_test.mbt`:

```moonbit
///|
/// Parse `metadata v = <text>` and return the value.
fn value(text : String) -> @ast.NodeValue raise {
  let r = @parser.parse_text(
    (
      $|metadata v = \{text}
      $|
    ),
  )
  guard r.ast is Some(f) && f.metadata.length() == 1 else {
    fail("no value: \{r.diagnostics}")
  }
  f.metadata[0].value
}

///|
fn vcodes(text : String) -> Array[String] {
  @parser.parse_text(
    (
      $|metadata v = \{text}
      $|
    ),
  ).diagnostics.iter().map(d => d.code).collect()
}

///|
test "scalars" {
  @expect.expect_all(e => {
    e.expect(value("\"hi\"").as_string()).to_equal(Some("hi"))
    e.expect(value("true") is Keyword(True, _)).to_be_true()
    e.expect(value("null") is Keyword(Null, _)).to_be_true()
    e.expect(value("Foo") is ShapeId({ name: "Foo", .. }, _)).to_be_true()
    e.expect(value("a.b#C$d") is ShapeId({ namespace: Some("a.b"), name: "C", member: Some("d") }, _)).to_be_true()
  })
}

///|
test "numbers are exact" {
  guard value("42") is Number(n, _) else { fail("not a number") }
  inspect(n.text, content="42")
  inspect(n.as_int64(), content="Some(42)")
  guard value("-1.50") is Number(d, _) else { fail("not a number") }
  debug_inspect(d.value is Decimal(_), content="true")
  inspect(d.as_double(), content="-1.5")
  guard value("1e3") is Number(x, _) else { fail("not a number") }
  inspect(x.as_double(), content="1000")
  guard value("99999999999999999999") is Number(big, _) else { fail("not a number") }
  inspect(big.as_int64(), content="None")
}

///|
test "arrays and objects with optional commas and nested values" {
  let v = value(
    (
      #|[1, 2 3,
      #| {a: "x", "b c": [true]}]
    ),
  )
  guard v is Array(items, _) else { fail("not an array") }
  inspect(items.length(), content="4")
  inspect(items[3].get("a").bind(x => x.as_string()), content="Some(\"x\")")
  guard items[3].get("b c") is Some(Array(inner, _)) else { fail("no b c") }
  inspect(inner.length(), content="1")
  inspect(value("{}") is Object(_, _), content="true")
  inspect(value("[]") is Array(_, _), content="true")
}

///|
test "a text block value is decoded" {
  inspect(value(
    (
      #|"""
      #|    hello
      #|    """
    ),
  ).as_string(), content="Some(\"hello\\n\")")
}

///|
test "an unclosed array is reported once with the array as context" {
  let r = @parser.parse_text(
    (
      #|metadata v = [1, 2
      #|namespace a
      #|
    ),
  )
  inspect(r.errors().length(), content="1")
  let d = r.errors()[0]
  inspect(d.labels[0].text, content="an array started here")
  inspect(d.notes[0], content="I was parsing an array when I got stuck.")
}

///|
test "a missing colon in an object names the key" {
  let r = @parser.parse_text(
    (
      #|metadata v = {a "x"}
      #|
    ),
  )
  inspect(r.errors()[0].message, content="I was expecting `:` after the key `a` but found a string")
}

///|
test "150 nested arrays is TOO MUCH NESTING, not a crash" {
  let sb = StringBuilder()
  for _ in 0..<150 {
    sb.write_string("[")
  }
  for _ in 0..<150 {
    sb.write_string("]")
  }
  @expect.expect(vcodes(sb.to_string())).to_equal(["SM-PARSE-010"])
  // 90 deep is fine.
  let ok = StringBuilder()
  for _ in 0..<90 {
    ok.write_string("[")
  }
  for _ in 0..<90 {
    ok.write_string("]")
  }
  @expect.expect(vcodes(ok.to_string())).to_equal([])
}
```

- [ ] **Step 2: Implement values.mbt**

```moonbit
///|
/// `NodeObjectKey = QuotedText / Identifier`.
fn Parser::parse_object_key(self : Parser) -> @ast.Node[String] raise ParseError {
  match self.peek() {
    Some(t) if t.kind == Identifier => {
      ignore(self.advance())
      @ast.Node::new(t.lexeme, t.span)
    }
    Some(t) if t.kind == String => {
      ignore(self.advance())
      @ast.Node::new(@scanner.unescape(t.lexeme), t.span)
    }
    _ =>
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting a key (an identifier or a quoted string) but found \{self.found()}",
        self.here(),
      )
  }
}

///|
/// The exact value of a `Number` token.
fn Parser::parse_number(self : Parser, t : @scanner.Token) -> @ast.NumberLiteral {
  let text = t.lexeme
  let value : @ast.NumberValue = if @scanner.is_integer_lexeme(text) {
    Integer(BigInt::from_string(text))
  } else {
    match @decimal.Decimal::from_string(text) {
      Some(d) => Decimal(d)
      // The scanner validated the digits; a lexeme the decimal parser
      // rejects (an exponent form it does not take) falls back to a
      // double, which is still a decimal value.
      None => Decimal(@decimal.Decimal::from_double(@strconv.parse_double(text) catch { _ => 0.0 }, 17).unwrap_or(@decimal.Decimal::from_int(0)))
    }
  }
  { text, value }
}

///|
/// `NodeObjectKvp *(WS NodeObjectKvp)` up to `close` (not consumed).
fn Parser::parse_object_kvps(
  self : Parser,
  close : @scanner.TokenKind,
  what : String,
) -> Array[@ast.NodeKvp] raise ParseError {
  let kvps : Array[@ast.NodeKvp] = []
  while !self.at_kind(close) {
    if self.at_end() {
      self.fail(
        "SM-PARSE-002",
        "UNFINISHED \{what.to_upper()}",
        "I reached the end of the file while reading \{what}",
        self.here(),
        hint="Add the closing bracket.",
      )
    }
    let key = self.parse_object_key()
    guard self.at_kind(Colon) else {
      self.fail(
        "SM-PARSE-001",
        "UNEXPECTED TOKEN",
        "I was expecting `:` after the key `\{key.value}` but found \{self.found()}",
        self.here(),
        example="{ \{key.value}: \"value\" }",
      )
    }
    ignore(self.advance())
    let value = self.parse_node_value()
    kvps.push({ key, value, span: key.span.join(value.span()) })
  }
  kvps
}

///|
/// `NodeValue = NodeArray / NodeObject / Number / NodeKeyword / NodeStringValue`.
fn Parser::parse_node_value(self : Parser) -> @ast.NodeValue raise ParseError {
  match self.peek() {
    None =>
      self.fail(
        "SM-PARSE-002",
        "UNEXPECTED END OF FILE",
        "I was expecting a value but reached the end of the file",
        self.here(),
      )
    Some(t) =>
      match t.kind {
        LBracket => {
          ignore(self.advance())
          self.enter()
          self.push_context("an array", t.span)
          let items : Array[@ast.NodeValue] = []
          while !self.at_kind(RBracket) {
            if self.at_end() {
              self.fail(
                "SM-PARSE-002",
                "UNFINISHED ARRAY",
                "I reached the end of the file while reading an array",
                self.here(),
                hint="Add the closing `]`.",
              )
            }
            items.push(self.parse_node_value())
          }
          let close = self.expect_kind(RBracket, "`]`")
          self.pop_context()
          self.leave()
          Array(items[:], t.span.join(close.span))
        }
        LBrace => {
          ignore(self.advance())
          self.enter()
          self.push_context("an object", t.span)
          let kvps = self.parse_object_kvps(RBrace, "an object")
          let close = self.expect_kind(RBrace, "`}`")
          self.pop_context()
          self.leave()
          Object(kvps[:], t.span.join(close.span))
        }
        Number => {
          ignore(self.advance())
          Number(self.parse_number(t), t.span)
        }
        String => {
          ignore(self.advance())
          String(@scanner.unescape(t.lexeme), t.span)
        }
        TextBlock => {
          ignore(self.advance())
          TextBlock(@scanner.text_block_value(t.lexeme), t.span)
        }
        Identifier =>
          match t.lexeme {
            "true" => {
              ignore(self.advance())
              Keyword(True, t.span)
            }
            "false" => {
              ignore(self.advance())
              Keyword(False, t.span)
            }
            "null" => {
              ignore(self.advance())
              Keyword(Null, t.span)
            }
            _ => {
              let id = self.parse_shape_id()
              ShapeId(id.value, id.span)
            }
          }
        _ =>
          self.fail(
            "SM-PARSE-001",
            "UNEXPECTED TOKEN",
            "I was expecting a value but found \{self.found()}",
            self.here(),
            notes=[
              "A value is a string, a number, `true`, `false`, `null`, a shape ID, an array `[...]` or an object `{...}`.",
            ],
          )
      }
  }
}
```

Add `"moonbitlang/core/strconv"` to the parser's imports in `parser/moon.pkg`. If `@strconv.parse_double` is not available under that name on this toolchain, use `@strconv.parse_double?` as the `.mbti` of core `strconv` shows and keep the fallback.

- [ ] **Step 3: Run the tests on native and wasm-gc**

Run: `moon test -p moonrockz/smithy-syntax/parser && moon test -p moonrockz/smithy-syntax/parser --target wasm-gc`
Expected: all pass, including the 150-deep test on wasm-gc.

- [ ] **Step 4: Format and commit**

```bash
mise run format
git add pkgs/smithy-syntax/src/parser
git commit -m "feat(syntax): parse node values with exact numbers and a nesting limit"
```

---

### Task 11: Shapes, traits, apply statements, doc comments and version gating

**Files:**
- Create: `pkgs/smithy-syntax/src/parser/traits.mbt`
- Create: `pkgs/smithy-syntax/src/parser/shapes.mbt`
- Modify: `pkgs/smithy-syntax/src/parser/file.mbt` (replace the `parse_shape_or_apply` stub)
- Create: `pkgs/smithy-syntax/src/parser/shapes_test.mbt`
- Create: `pkgs/smithy-syntax/src/parser/traits_test.mbt`
- Create: `pkgs/smithy-syntax/src/parser/docs_test.mbt`

**Interfaces:**
- Produces: `Parser::parse_traits() -> Array[@ast.Trait]`, `Parser::parse_trait()`, `Parser::parse_shape_or_apply() -> @ast.Statement`, `Parser::parse_shape(docs, traits, start) -> @ast.ShapeStatement`, `Parser::parse_members(owner : String) -> Array[@ast.Member]`, `Parser::parse_enum_members(owner)`, `Parser::parse_mixins() -> @ast.Mixins?`, `Parser::parse_for_resource() -> Node[ShapeId]?`, `Parser::parse_operation_body()`, `Parser::parse_inline_shape(start)`, `Parser::parse_apply(start)`, `Parser::require_v2(feature, span)`.

- [ ] **Step 1: Write the failing shape tests (Review Focus 3 lives here)**

`parser/shapes_test.mbt`:

```moonbit
///|
fn model(body : String) -> @parser.ParseResult {
  @parser.parse_text(
    (
      $|$version: "2"
      $|namespace com.foo
      $|
      $|\{body}
    ),
  )
}

///|
fn shapes(body : String) -> Array[@ast.ShapeStatement] raise {
  let r = model(body)
  guard r.ast is Some(f) else { fail("no ast: \{r.diagnostics}") }
  f.shapes()
}

///|
fn scodes(body : String) -> Array[String] {
  model(body).diagnostics.iter().map(d => d.code).collect()
}

///|
test "simple shapes" {
  let ss = shapes(
    (
      #|string Foo
      #|blob Bar with [Mix]
      #|
    ),
  )
  @expect.expect_all(e => {
    e.expect(ss.length()).to_equal(2)
    e.expect(ss[0].shape.name().value).to_equal("Foo")
    e.expect(ss[0].shape.kind()).to_equal(Simple(String))
    e.expect(ss[1].shape is Aggregate(..)).to_be_false()
  })
  guard ss[1].shape is Simple(mixins=Some(m), ..) else { fail("no mixins") }
  inspect(m.ids[0].value, content="Mix")
}

///|
test "structures with explicit and elided members and defaults" {
  let ss = shapes(
    (
      #|structure Foo for Res with [A, B] {
      #|    @required
      #|    bar: String = "x"
      #|    $baz
      #|    $qux = 1
      #|}
      #|
    ),
  )
  guard ss[0].shape is Aggregate(kind=Structure, for_resource=Some(res), mixins=Some(m), members~, ..) else {
    fail("not a structure")
  }
  @expect.expect_all(e => {
    e.expect(res.value.name).to_equal("Res")
    e.expect(m.ids.length()).to_equal(2)
    e.expect(members.length()).to_equal(3)
    e.expect(members[0].name.value).to_equal("bar")
    e.expect(members[0].traits.length()).to_equal(1)
    e.expect(members[0].target is Explicit(_)).to_be_true()
    e.expect(members[0].default.bind(d => d.as_string())).to_equal(Some("x"))
    e.expect(members[1].target is Elided).to_be_true()
    e.expect(members[2].default is Some(Number(_, _))).to_be_true()
  })
}

///|
test "list, map, union and set" {
  let ss = shapes(
    (
      #|list L { member: String }
      #|map M { key: String, value: Integer }
      #|union U { a: String }
      #|set S { member: String }
      #|
    ),
  )
  @expect.expect(ss.map(s => s.shape.kind())).to_equal([
    Aggregate(List), Aggregate(Map), Aggregate(Union), Aggregate(Set),
  ])
  guard ss[1].shape is Aggregate(members~, ..) else { fail("not a map") }
  inspect(members.length(), content="2")
}

///|
test "enum and intEnum members with values and traits" {
  let ss = shapes(
    (
      #|enum Color {
      #|  /// red
      #|  @deprecated
      #|  RED = "red"
      #|  BLUE
      #|}
      #|intEnum N { ONE = 1 }
      #|
    ),
  )
  guard ss[0].shape is Enum(kind=Enum, members~, ..) else { fail("not an enum") }
  @expect.expect_all(e => {
    e.expect(members.length()).to_equal(2)
    e.expect(members[0].docs[0].text).to_equal(" red")
    e.expect(members[0].traits.length()).to_equal(1)
    e.expect(members[0].value.bind(v => v.as_string())).to_equal(Some("red"))
    e.expect(members[1].value).to_equal(None)
  })
  guard ss[1].shape is Enum(kind=IntEnum, ..) else { fail("not an intEnum") }
}

///|
test "service and resource bodies are node objects" {
  let ss = shapes(
    (
      #|service S {
      #|  version: "1"
      #|  operations: [Op]
      #|}
      #|resource R { identifiers: { id: String } }
      #|
    ),
  )
  guard ss[0].shape is Entity(kind=Service, body~, ..) else { fail("not a service") }
  inspect(body.get("version").bind(v => v.as_string()), content="Some(\"1\")")
  guard ss[1].shape is Entity(kind=Resource, ..) else { fail("not a resource") }
}

///|
test "operations with references, inline shapes and errors" {
  let ss = shapes(
    (
      #|operation Op {
      #|    input := @sensitive for Res with [M] {
      #|        id: String
      #|    }
      #|    output: Out
      #|    errors: [E1, E2]
      #|}
      #|
    ),
  )
  guard ss[0].shape is Operation(properties~, ..) else { fail("not an operation") }
  inspect(properties.length(), content="3")
  guard properties[0] is Input(Inline(inline), _) else { fail("input not inline") }
  @expect.expect_all(e => {
    e.expect(inline.traits.length()).to_equal(1)
    e.expect(inline.for_resource.map(r => r.value.name)).to_equal(Some("Res"))
    e.expect(inline.mixins.map(m => m.ids.length())).to_equal(Some(1))
    e.expect(inline.members.length()).to_equal(1)
  })
  guard properties[1] is Output(Reference(out), _) else { fail("output not a reference") }
  inspect(out.value.name, content="Out")
  guard properties[2] is Errors(errs, _) else { fail("no errors") }
  inspect(errs.length(), content="2")
}

///|
test "an unknown operation property is SM-PARSE-011" {
  @expect.expect(scodes(
    (
      #|operation Op { inputs: Foo }
      #|
    ),
  )).to_equal(["SM-PARSE-011"])
}

///|
test "a shape name must be an identifier (the reference's parse errors)" {
  let r = model(
    (
      #|string com.foo#Bam
      #|
    ),
  )
  @expect.expect(scodes(
    (
      #|string com.foo#Bam
      #|
    ),
  )).to_equal(["SM-PARSE-005"])
  inspect(r.errors()[0].message, content="a shape name is a plain identifier, but `com.foo#Bam` has a namespace")
  @expect.expect(scodes(
    (
      #|string Foo$bar
      #|
    ),
  )).to_equal(["SM-PARSE-005"])
}

///|
test "spaces inside a shape id are not a shape id" {
  @expect.expect(scodes(
    (
      #|structure S { a: smithy.api # String }
      #|
    ),
  )).to_equal(["SM-PARSE-001"])
}

///|
test "a shape keyword needs a name on the same line" {
  @expect.expect(scodes(
    (
      #|string
      #|Foo
      #|
    ),
  )).to_equal(["SM-PARSE-001"])
  let r = model(
    (
      #|string
      #|
    ),
  )
  inspect(r.errors()[0].message, content="I was expecting a shape name after `string` but found the end of the file")
}

///|
test "members need a line break between them" {
  @expect.expect(scodes(
    (
      #|structure S { a: String b: String }
      #|
    ),
  )).to_equal(["SM-PARSE-003"])
  @expect.expect(scodes(
    (
      #|structure S { a: String, b: String }
      #|
    ),
  )).to_equal([])
}

///|
test "an unclosed structure is reported once, with the structure as context" {
  let r = model(
    (
      #|structure S {
      #|  a: String
      #|string Foo
      #|
    ),
  )
  let errs = r.errors()
  inspect(errs.length(), content="1")
  inspect(errs[0].labels[0].text, content="the structure `S` started here")
}
```

- [ ] **Step 2: Write the failing trait, apply and doc comment tests**

`parser/traits_test.mbt`:

```moonbit
///|
fn tmodel(body : String) -> @parser.ParseResult {
  @parser.parse_text(
    (
      $|$version: "2"
      $|namespace com.foo
      $|
      $|\{body}
    ),
  )
}

///|
fn traits_of(body : String) -> Array[@ast.Trait] raise {
  let r = tmodel(body)
  guard r.ast is Some(f) && f.shapes().length() > 0 else { fail("no shape: \{r.diagnostics}") }
  f.shapes()[0].traits.to_array()
}

///|
test "trait forms" {
  let ts = traits_of(
    (
      #|@a
      #|@b()
      #|@c("x")
      #|@d(k: 1, "j": [true])
      #|@smithy.api#e(Foo)
      #|string S
      #|
    ),
  )
  @expect.expect_all(e => {
    e.expect(ts.length()).to_equal(5)
    e.expect(ts[0].body).to_equal(None)
    e.expect(ts[1].body is Some(Structure(kv)) && kv.length() == 0).to_be_true()
    e.expect(ts[2].body is Some(Node(String("x", _)))).to_be_true()
    e.expect(ts[3].body is Some(Structure(kv)) && kv.length() == 2).to_be_true()
    e.expect(ts[4].id.value.to_string()).to_equal("smithy.api#e")
    e.expect(ts[4].body is Some(Node(ShapeId(_, _)))).to_be_true()
  })
}

///|
test "an unclosed trait body is reported with the trait as context" {
  let r = tmodel(
    (
      #|@a(k: 1
      #|string S
      #|
    ),
  )
  inspect(r.errors().length(), content="1")
  inspect(r.errors()[0].labels[0].text, content="the trait `@a` started here")
}

///|
test "apply statements" {
  let r = tmodel(
    (
      #|apply Foo @since("1")
      #|apply Bar$baz {
      #|  @a
      #|  @b
      #|}
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(r.has_errors(), content="false")
  guard f.statements[0] is Apply(a) && f.statements[1] is Apply(b) else { fail("not applies") }
  @expect.expect_all(e => {
    e.expect(a.target.value.name).to_equal("Foo")
    e.expect(a.traits.length()).to_equal(1)
    e.expect(a.block).to_be_false()
    e.expect(b.target.value.member).to_equal(Some("baz"))
    e.expect(b.traits.length()).to_equal(2)
    e.expect(b.block).to_be_true()
  })
}

///|
test "traits with nothing after them are an error, not a crash" {
  let r = tmodel(
    (
      #|@a
      #|
    ),
  )
  inspect(r.errors().length(), content="1")
  inspect(r.errors()[0].message, content="I was expecting a shape after the traits but found the end of the file")
}
```

`parser/docs_test.mbt`:

```moonbit
///|
fn dmodel(body : String) -> @parser.ParseResult {
  @parser.parse_text(
    (
      $|$version: "2"
      $|namespace com.foo
      $|
      $|\{body}
    ),
  )
}

///|
fn dcodes(body : String) -> Array[String] {
  dmodel(body).diagnostics.iter().map(d => d.code).collect()
}

///|
test "doc comments attach to shapes, members, enum members and inline shapes" {
  let r = dmodel(
    (
      #|/// Shape docs.
      #|/// Second line.
      #|@a
      #|structure S {
      #|    /// Member docs.
      #|    @b
      #|    m: String
      #|}
      #|
      #|operation Op {
      #|    /// Inline docs.
      #|    input := {}
      #|}
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  let ss = f.shapes()
  @expect.expect_all(e => {
    e.expect(r.has_errors()).to_be_false()
    e.expect(ss[0].docs.map(d => d.text)).to_equal([" Shape docs.", " Second line."])
  })
  guard ss[0].shape is Aggregate(members~, ..) else { fail("no members") }
  inspect(members[0].docs[0].text, content=" Member docs.")
  guard ss[1].shape is Operation(properties~, ..) && properties[0] is Input(Inline(inline), _) else {
    fail("no inline")
  }
  inspect(inline.docs[0].text, content=" Inline docs.")
}

///|
test "docs between the traits and the keyword still attach" {
  let r = dmodel(
    (
      #|@a
      #|/// late
      #|string S
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(f.shapes()[0].docs.length(), content="1")
  inspect(r.has_errors(), content="false")
}

///|
test "a doc comment with no shape after it is a warning" {
  @expect.expect(dcodes(
    (
      #|string S
      #|/// trailing
      #|
    ),
  )).to_equal(["SM-PARSE-009"])
  @expect.expect(dcodes(
    (
      #|structure S {
      #|  a: String
      #|  /// nothing
      #|}
      #|
    ),
  )).to_equal(["SM-PARSE-009"])
  inspect(dmodel(
    (
      #|string S
      #|/// trailing
      #|
    ),
  ).has_errors(), content="false")
}

///|
test "docs before apply are an error" {
  @expect.expect(dcodes(
    (
      #|/// no
      #|apply Foo @a
      #|
    ),
  )).to_equal(["SM-PARSE-008"])
}

///|
test "version 1 files reject 2.0 syntax with the reference's facts" {
  fn v1(body : String) -> Array[String] {
    @parser.parse_text(
      (
        $|$version: "1.0"
        $|namespace com.foo
        $|\{body}
      ),
    ).diagnostics.iter().map(d => d.code).collect()
  }

  @expect.expect_all(e => {
    e.expect(v1(
      (
        #|string S with [M]
        #|
      ),
    )).to_equal(["SM-PARSE-007"])
    e.expect(v1(
      (
        #|structure S { $a }
        #|
      ),
    )).to_equal(["SM-PARSE-007"])
    e.expect(v1(
      (
        #|structure S for R {}
        #|
      ),
    )).to_equal(["SM-PARSE-007"])
    e.expect(v1(
      (
        #|operation O { input := {} }
        #|
      ),
    )).to_equal(["SM-PARSE-007"])
    e.expect(v1(
      (
        #|structure S { a: String }
        #|
      ),
    )).to_equal([])
  })
  // A missing $version means 1.0.
  @expect.expect(
    @parser.parse_text(
      (
        #|namespace com.foo
        #|string S with [M]
        #|
      ),
    ).diagnostics.iter().map(d => d.code).collect(),
  ).to_equal(["SM-PARSE-007"])
  inspect(
    @parser.parse_text(
      (
        #|namespace a
        #|string S with [M]
        #|
      ),
    ).errors()[0].message,
    content="Mixins can only be used with Smithy version 2 or later",
  )
}
```

- [ ] **Step 3: Implement traits.mbt**

```moonbit
///|
/// `TraitStatements = *(Trait [WS])`.
fn Parser::parse_traits(self : Parser) -> Array[@ast.Trait] raise ParseError {
  let traits : Array[@ast.Trait] = []
  while self.at_kind(At) {
    traits.push(self.parse_trait())
  }
  traits
}

///|
/// `Trait = "@" ShapeId [TraitBody]`; `TraitBody = "(" [WS] [TraitStructure / TraitNode] ")"`.
/// A body is a structure when it starts with a key followed by `:`.
fn Parser::parse_trait(self : Parser) -> @ast.Trait raise ParseError {
  let at = self.expect_kind(At, "`@`")
  guard self.adjacent() && self.at_kind(Identifier) else {
    self.fail(
      "SM-PARSE-001",
      "UNEXPECTED TOKEN",
      "I was expecting a trait name right after `@` but found \{self.found()}",
      self.here(),
      example="@required",
    )
  }
  let id = self.parse_shape_id()
  self.push_context("the trait `@\{id.value}`", at.span)
  let mut end = id.span.end()
  let body : @ast.TraitBody? = if self.at_kind(LParen) {
    ignore(self.advance())
    self.enter()
    let b : @ast.TraitBody = if self.at_kind(RParen) {
      Structure([][:])
    } else if (self.at_kind(Identifier) || self.at_kind(String)) &&
      self.peek1() is Some(n) && n.kind == Colon {
      Structure(self.parse_object_kvps(RParen, "a trait body")[:])
    } else {
      Node(self.parse_node_value())
    }
    let close = self.expect_kind(RParen, "`)` to close the trait body")
    self.leave()
    end = close.span.end()
    Some(b)
  } else {
    None
  }
  self.pop_context()
  { id, body, span: at.span.start.to(end) }
}

///|
/// An error for 2.0-only syntax in a 1.0 file. The messages are the
/// reference's.
fn Parser::require_v2(self : Parser, feature : String, span : @span.Span) -> Unit raise ParseError {
  guard self.version != Some(V2) else { return }
  let message = match feature {
    "mixins" => "Mixins can only be used with Smithy version 2 or later"
    "elision" => "Members can only elide targets in IDL version 2 or later"
    "for" => "Resource properties can only be used with Smithy version 2 or later"
    _ => "Inlined operation inputs and outputs can only be used with Smithy version 2 or later"
  }
  self.fail(
    "SM-PARSE-007",
    "NEEDS SMITHY IDL 2",
    message,
    span,
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
```

- [ ] **Step 4: Implement shapes.mbt**

```moonbit
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
  Some({ ids: ids[:], span: kw.span.join(close.span) })
}

///|
/// `ForResource = SP "for" SP ShapeId`.
fn Parser::parse_for_resource(self : Parser) -> @ast.Node[@ast.ShapeId]? raise ParseError {
  guard self.at_keyword("for") else { return None }
  let kw = self.expect_kind(Identifier, "`for`")
  self.require_v2("for", kw.span)
  Some(self.parse_shape_id())
}

///|
/// The identifier after a shape keyword. It must be a plain identifier:
/// the reference reports `string com.foo#Bam` at the dot.
fn Parser::parse_shape_name(self : Parser, keyword : String) -> @ast.Node[String] raise ParseError {
  guard self.peek() is Some(t) && t.kind == Identifier else {
    self.fail(
      "SM-PARSE-001",
      "MISSING SHAPE NAME",
      "I was expecting a shape name after `\{keyword}` but found \{self.found()}",
      self.here(),
      example="\{keyword} MyShape",
    )
  }
  let name = self.expect_identifier("a shape name")
  if (self.at_kind(Dot) || self.at_kind(Pound) || self.at_kind(Dollar)) && self.adjacent() {
    // Read the rest of the ID to show it whole.
    let start = name.span.start
    let mut end = name.span.end()
    while (self.at_kind(Dot) || self.at_kind(Pound) || self.at_kind(Dollar) || self.at_kind(Identifier)) && self.adjacent() {
      match self.advance() {
        Some(t) => end = t.span.end()
        None => ()
      }
    }
    let whole = self.tokens[self.pos - 1].lexeme
    ignore(whole)
    let shown = self.text_between(start, end)
    let reason = if shown.contains("#") { "has a namespace" } else if shown.contains("$") { "names a member" } else { "has a dot" }
    self.fail(
      "SM-PARSE-005",
      "INVALID SHAPE NAME",
      "a shape name is a plain identifier, but `\{shown}` \{reason}",
      start.to(end),
      notes=["A shape is defined in the file's namespace, so its name carries no namespace, and members are declared inside the shape."],
      hint="Write `\{keyword} \{name.value}`.",
    )
  }
  name
}

///|
/// The source text between two offsets (from the tokens' lexemes).
fn Parser::text_between(self : Parser, start : @span.Offset, end : @span.Offset) -> String {
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
/// Skip to the next member start or the closing brace after an error in a
/// member, so one bad member does not drop the shape.
fn Parser::recover_member(self : Parser) -> Unit {
  while !self.at_end() && !self.at_kind(RBrace) {
    if self.first_on_line(self.pos) && self.at_member_start() {
      return
    }
    ignore(self.advance())
  }
}

///|
/// `ShapeMembers = "{" [WS] *(ShapeMember [WS]) "}"`, each
/// `ShapeMember = TraitStatements (ExplicitShapeMember / ElidedShapeMember) [ValueAssignment]`.
fn Parser::parse_members(self : Parser, owner : String) -> Array[@ast.Member] raise ParseError {
  let open = self.expect_kind(LBrace, "`{` to start the members of \{owner}")
  self.enter()
  let members : Array[@ast.Member] = []
  while !self.at_kind(RBrace) {
    if self.at_end() {
      self.fail(
        "SM-PARSE-002",
        "UNFINISHED SHAPE",
        "I reached the end of the file while reading the members of \{owner}",
        self.here(),
        hint="Add the closing `}`.",
      )
    }
    let outcome = try {
      Ok(self.parse_member())
    } catch {
      e => Err(e)
    } noraise {
      v => v
    }
    match outcome {
      Ok(m) => {
        members.push(m)
        if !self.at_kind(RBrace) {
          self.expect_br()
        }
      }
      Err(e) => {
        self.diagnostics.push(e.diagnostic())
        self.recover_member()
      }
    }
  }
  self.detach_docs_before(self.here().start)
  ignore(self.expect_kind(RBrace, "`}`"))
  self.leave()
  ignore(open)
  members
}

///|
fn Parser::parse_member(self : Parser) -> @ast.Member raise ParseError {
  guard self.peek() is Some(first) else {
    self.fail("SM-PARSE-002", "UNEXPECTED END OF FILE", "I was expecting a member", self.here())
  }
  let docs = self.take_docs_before(first.span.start)
  let traits = self.parse_traits()
  // Docs between traits and the name still attach.
  docs.append(self.take_docs_before(self.here().start))
  let (name, target) : (@ast.Node[String], @ast.MemberTarget) = if self.at_kind(Dollar) {
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
        notes=["A member looks like `name: Target`, with optional traits before it and an optional `= default` after it."],
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
    end = v.span().end
    Some(v)
  } else {
    None
  }
  let start = if traits.length() > 0 { traits[0].span.start } else { name.span.start }
  { docs: docs[:], traits: traits[:], name, target, default, span: start.to(end) }
}

///|
/// `EnumShapeMembers = "{" [WS] 1*(EnumShapeMember [WS]) "}"`.
fn Parser::parse_enum_members(self : Parser, owner : String) -> Array[@ast.EnumMember] raise ParseError {
  ignore(self.expect_kind(LBrace, "`{` to start the members of \{owner}"))
  self.enter()
  let members : Array[@ast.EnumMember] = []
  while !self.at_kind(RBrace) {
    if self.at_end() {
      self.fail(
        "SM-PARSE-002",
        "UNFINISHED ENUM",
        "I reached the end of the file while reading the members of \{owner}",
        self.here(),
        hint="Add the closing `}`.",
      )
    }
    let outcome = try {
      Ok(self.parse_enum_member())
    } catch {
      e => Err(e)
    } noraise {
      v => v
    }
    match outcome {
      Ok(m) => {
        members.push(m)
        if !self.at_kind(RBrace) {
          self.expect_br()
        }
      }
      Err(e) => {
        self.diagnostics.push(e.diagnostic())
        self.recover_member()
      }
    }
  }
  self.detach_docs_before(self.here().start)
  ignore(self.expect_kind(RBrace, "`}`"))
  self.leave()
  members
}

///|
fn Parser::parse_enum_member(self : Parser) -> @ast.EnumMember raise ParseError {
  guard self.peek() is Some(first) else {
    self.fail("SM-PARSE-002", "UNEXPECTED END OF FILE", "I was expecting an enum member", self.here())
  }
  let docs = self.take_docs_before(first.span.start)
  let traits = self.parse_traits()
  docs.append(self.take_docs_before(self.here().start))
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
    end = v.span().end
    Some(v)
  } else {
    None
  }
  let start = if traits.length() > 0 { traits[0].span.start } else { name.span.start }
  { docs: docs[:], traits: traits[:], name, value, span: start.to(end) }
}

///|
/// `InlineAggregateShape = ":=" [WS] TraitStatements [ForResource] [Mixins] [WS] ShapeMembers`.
fn Parser::parse_inline_shape(self : Parser, walrus : @scanner.Token) -> @ast.InlineShape raise ParseError {
  self.require_v2("inline", walrus.span)
  let docs = self.take_docs_before(walrus.span.start)
  let traits = self.parse_traits()
  let for_resource = self.parse_for_resource()
  let mixins = self.parse_mixins()
  self.push_context("an inline shape", walrus.span)
  let members = self.parse_members("the inline shape")
  self.pop_context()
  let end = self.tokens[self.pos - 1].span.end()
  { docs: docs[:], traits: traits[:], for_resource, mixins, members: members[:], span: walrus.span.start.to(end) }
}

///|
/// `OperationBody = "{" [WS] *(OperationProperty [WS]) "}"`.
fn Parser::parse_operation_body(self : Parser, owner : String) -> Array[@ast.OperationProperty] raise ParseError {
  ignore(self.expect_kind(LBrace, "`{` to start the body of \{owner}"))
  self.enter()
  let props : Array[@ast.OperationProperty] = []
  while !self.at_kind(RBrace) {
    if self.at_end() {
      self.fail(
        "SM-PARSE-002",
        "UNFINISHED OPERATION",
        "I reached the end of the file while reading \{owner}",
        self.here(),
        hint="Add the closing `}`.",
      )
    }
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
        props.push(if key.lexeme == "input" { Input(target, span) } else { Output(target, span) })
      }
      "errors" => {
        self.detach_docs_before(key.span.start)
        ignore(self.advance())
        ignore(self.expect_kind(Colon, "`:` after `errors`"))
        ignore(self.expect_kind(LBracket, "`[` to start the error list"))
        let ids : Array[@ast.Node[@ast.ShapeId]] = []
        while !self.at_kind(RBracket) {
          if self.at_end() {
            self.fail("SM-PARSE-002", "UNFINISHED ERROR LIST", "I reached the end of the file inside the error list", self.here(), hint="Add the closing `]`.")
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
          notes=["An operation body holds `input`, `output` and `errors`, each at most once."],
          hint=if other == "inputs" { "Did you mean `input`?" } else if other == "outputs" { "Did you mean `output`?" } else if other == "error" { "Did you mean `errors`?" } else { "Remove it, or move it into a trait." },
        )
    }
    if !self.at_kind(RBrace) {
      self.expect_br()
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
  guard self.peek() is Some(kw) && kw.kind == Identifier && @ast.ShapeKind::of(kw.lexeme) is Some(kind) else {
    if traits.length() > 0 || docs.length() > 0 {
      self.fail(
        "SM-PARSE-004",
        "EXPECTED A SHAPE",
        "I was expecting a shape after the traits but found \{self.found()}",
        self.here(),
        notes=["Traits and documentation comments apply to the shape statement right after them."],
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
  let name = self.parse_shape_name(kw.lexeme)
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
      Aggregate(kind=t, name~, for_resource~, mixins~, members=self.parse_members(owner)[:])
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
  { docs: docs[:], traits: traits[:], shape, span: start.to(end) }
}

///|
/// `ApplyStatement = ApplyStatementSingular / ApplyStatementBlock`.
fn Parser::parse_apply(self : Parser, start : @span.Offset) -> @ast.ApplyStatement raise ParseError {
  let kw = self.expect_kind(Identifier, "`apply`")
  self.push_context("an apply statement", kw.span)
  let target = self.parse_shape_id()
  let (traits, block) : (Array[@ast.Trait], Bool) = if self.at_kind(LBrace) {
    ignore(self.advance())
    let ts = self.parse_traits()
    self.detach_docs_before(self.here().start)
    ignore(self.expect_kind(RBrace, "`}` to close the apply block"))
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
  { target, traits: traits[:], block, span: start.to(end) }
}

///|
/// `ShapeOrApplyStatement`, then `BR`.
fn Parser::parse_shape_or_apply(self : Parser) -> @ast.Statement raise ParseError {
  guard self.peek() is Some(first) else {
    self.fail("SM-PARSE-002", "UNEXPECTED END OF FILE", "I was expecting a statement", self.here())
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
        notes=["An `apply` statement adds traits to a shape defined elsewhere; documentation is written where the shape is defined, or applied as `@documentation(\"...\")`."],
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
```

Delete the `parse_shape_or_apply` stub in `file.mbt`.

- [ ] **Step 5: Run all parser tests on native and js**

Run: `moon test -p moonrockz/smithy-syntax/parser && moon test -p moonrockz/smithy-syntax/parser --target js`
Expected: all pass. Expect to iterate on exact message strings: the tests pin the wording, so change the code to match the test unless the test's wording breaks a Global Constraint.

- [ ] **Step 6: Format and commit**

```bash
mise run format
git add pkgs/smithy-syntax/src/parser
git commit -m "feat(syntax): parse shapes, traits, apply statements and doc comments with version gating"
```

---

### Task 12: Recovery tests and parser laws

**Files:**
- Create: `pkgs/smithy-syntax/src/parser/recovery_test.mbt`
- Create: `pkgs/smithy-syntax/src/parser/parser_law_test.mbt`
- Create: `pkgs/smithy-syntax/src/lawkit/edits.mbt`
- Create: `pkgs/smithy-syntax/src/parser/README.mbt.md`

**Interfaces:**
- Produces: `@lawkit.EditedModel` (quickcheck `Arbitrary`): the small model with one random edit (a character deleted, inserted or replaced), `text()`, `edit_offset()`.

- [ ] **Step 1: Write the recovery tests (Review Focus 5 lives here)**

`parser/recovery_test.mbt`:

```moonbit
///|
fn rmodel(body : String) -> @parser.ParseResult {
  @parser.parse_text(
    (
      $|$version: "2"
      $|namespace com.foo
      $|
      $|\{body}
    ),
  )
}

///|
test "a broken structure yields one error and the next shape survives" {
  let r = rmodel(
    (
      #|structure Bad {
      #|  a String
      #|}
      #|
      #|string Foo
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  let names = f.shapes().map(s => s.shape.name().value)
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(names).to_equal(["Bad", "Foo"])
    e.expect(r.cst.skipped().length()).to_equal(0)
  })
}

///|
test "an unclosed brace still lets the next statement parse" {
  let r = rmodel(
    (
      #|structure Bad {
      #|  a: String
      #|
      #|string Foo
      #|
      #|@deprecated
      #|string Bar
      #|
    ),
  )
  guard r.ast is Some(f) else { fail("no ast") }
  let names = f.shapes().map(s => s.shape.name().value)
  // `string Foo` is read as a bad member of Bad; recovery resumes at `@deprecated`.
  @expect.expect_all(e => {
    e.expect(r.errors().length()).to_equal(1)
    e.expect(names.contains("Bar")).to_be_true()
    e.expect(r.cst.skipped().length()).to_equal(1)
    e.expect(r.cst.to_source().length()).to_equal(r.cst.tokens.iter().map(t => t.to_source().length()).fold(init=0, (a, b) => a + b))
  })
}

///|
test "every statement form appears in the CST with its name" {
  let r = @parser.parse_text(@lawkit.small_model())
  inspect(r.has_errors(), content="false")
  let kinds = r.cst.statements.iter().map(s => "\{s.kind}=\{s.name.unwrap_or("")}").collect()
  @expect.expect(kinds[0]).to_equal("Control=version")
  @expect.expect(kinds[1]).to_equal("Metadata=foo")
  @expect.expect(kinds[2]).to_equal("Namespace=smithy.example")
  @expect.expect(kinds[3]).to_equal("Use=smithy.api#String")
  @expect.expect(kinds[4]).to_equal("Shape(Aggregate(Structure))=Foo")
  @expect.expect(kinds[kinds.length() - 1]).to_equal("Apply=Foo")
}

///|
test "the reference's error-recovery cases: resume at a doc comment, a dollar, an identifier and a trait" {
  let to_docs = (
    #|structure Bad {
    #|  a:
    #|
    #|/// docs
    #|string Foo
    #|
  )
  let to_dollar = (
    #|metadata x = [1,
    #|
    #|$version: "2"
    #|string Foo
    #|
  )
  let to_identifier = (
    #|structure Bad {
    #|  a:
    #|
    #|string Foo
    #|
  )
  let to_trait = (
    #|structure Bad {
    #|  a:
    #|
    #|@deprecated
    #|string Foo
    #|
  )
  for body in [to_docs, to_identifier, to_trait] {
    let r = rmodel(body)
    guard r.ast is Some(f) else { fail("no ast for \{body}") }
    @expect.expect(r.errors().length()).because(body).to_equal(1)
    @expect.expect(f.shapes().map(s => s.shape.name().value).contains("Foo")).because(body).to_be_true()
  }
  // The dollar case resumes at `$version`, which is itself a true error after
  // the namespace (a control statement out of order), so two errors at most.
  let r = rmodel(to_dollar)
  guard r.ast is Some(f) else { fail("no ast for the dollar case") }
  @expect.expect(r.errors().length() <= 2).to_be_true()
  @expect.expect(f.shapes().map(s => s.shape.name().value).contains("Foo")).to_be_true()
}
```

The string interpolation above uses the hand-written `Show` impls of `@cst.StatementKind` (Task 8) and `@ast.ShapeKind` (Task 7).

- [ ] **Step 2: Write the edit generator**

Add `"moonrockz/smithy-syntax/span"` to the imports of `lawkit/moon.pkg`.

`lawkit/edits.mbt`:

```moonbit
///|
/// The small model with one random edit: a code unit deleted, one
/// inserted (from the token pieces) or one replaced. For laws about
/// recovery: the parser must not crash, the CST stays lossless, and at
/// most a few diagnostics come out of a single edit.
pub(all) struct EditedModel {
  text : String
  edit_offset : @span.Offset
} derive(Debug)

///|
pub fn EditedModel::text(self : EditedModel) -> String {
  self.text
}

///|
pub impl @quickcheck.Arbitrary for EditedModel with fn arbitrary(_size, rs) {
  let m = small_model()
  let at = pick(rs, m.length())
  let piece = one_of(rs, token_pieces())
  let text = match pick(rs, 3) {
    0 => m.unsafe_substring(start=0, end=at) + m.unsafe_substring(start=at + 1, end=m.length())
    1 => m.unsafe_substring(start=0, end=at) + piece + m.unsafe_substring(start=at, end=m.length())
    _ => m.unsafe_substring(start=0, end=at) + piece + m.unsafe_substring(start=at + 1, end=m.length())
  }
  { text, edit_offset: @span.Offset::new(at).unwrap_or(@span.Offset::zero()) }
}

///|
pub impl @quickcheck.Shrink for EditedModel with fn shrink(_self) {
  Iter::empty()
}
```

- [ ] **Step 3: Write the parser laws**

`parser/parser_law_test.mbt`:

```moonbit
///|
test "law: the parser never panics and the CST is lossless for any text" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      @parser.parse_text(text).cst.to_source() == text
    },
    count=400,
    max_size=16,
    seed=3031,
  )
}

///|
test "law: CST statements tile the token array in order" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let r = @parser.parse_text(t.text())
      let mut at = 0
      let mut ok = true
      for s in r.cst.statements {
        ok = ok && s.tokens.length() > 0
        if s.tokens.length() > 0 {
          ok = ok && s.tokens[0] == r.cst.tokens[at]
          at += s.tokens.length()
        }
      }
      ok && at == r.cst.tokens.length()
    },
    count=400,
    max_size=16,
    seed=3032,
  )
}

///|
test "law: every AST statement span lies inside the file span and statements are in order" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let r = @parser.parse_text(t.text())
      guard r.ast is Some(f) else { return true }
      let mut last = @span.Offset::zero()
      let mut ok = true
      for s in f.statements {
        let sp = s.span()
        ok = ok && sp.start >= last && sp.end() <= f.span.end()
        last = sp.start
      }
      ok
    },
    count=400,
    max_size=16,
    seed=3033,
  )
}

///|
test "law: every diagnostic code is in the table and every span is inside the text" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let text = t.text()
      let r = @parser.parse_text(text)
      r.diagnostics.iter().all(d => @diagnostic.description(d.code) is Some(_) &&
        d.span.end().0 <= text.length())
    },
    count=400,
    max_size=16,
    seed=3034,
  )
}

///|
test "law: one edit to a valid model gives at most three diagnostics and keeps most shapes" {
  @quickcheck.check(
    (m : @lawkit.EditedModel) => {
      let r = @parser.parse_text(m.text())
      guard r.ast is Some(f) else { return r.diagnostics.length() <= 3 }
      // The small model has 8 shape statements and 1 apply.
      r.diagnostics.length() <= 3 && f.shapes().length() >= 5
    },
    count=300,
    max_size=16,
    seed=3035,
  )
}

///|
test "law: a valid model parses the same from its CST source" {
  @quickcheck.check(
    (_u : Unit) => {
      let r1 = @parser.parse_text(@lawkit.small_model())
      let r2 = @parser.parse_text(r1.cst.to_source())
      r1.ast == r2.ast && r1.diagnostics.length() == 0
    },
    count=1,
    seed=3036,
  )
}
```

- [ ] **Step 4: Run the laws on two targets**

Run: `moon test -p moonrockz/smithy-syntax/parser && moon test -p moonrockz/smithy-syntax/parser --target wasm-gc`
Expected: all pass. A counterexample from the edit law usually means recovery produced a cascade: fix the recovery (one diagnostic per skipped run), not the law.

- [ ] **Step 5: README and commit**

`parser/README.mbt.md`:

````markdown
# parser

`parse_text` parses Smithy IDL into a `ParseResult`: the AST (`ast`), the
CST (`cst`, lossless), the declared `version` and the `diagnostics`. An
error inside a statement is reported once and the parser resumes at the
next statement.

```mbt check
test {
  let r = @parser.parse_text("$version: \"2\"\nnamespace com.foo\n\nstring Name\n")
  inspect(r.has_errors(), content="false")
  guard r.ast is Some(f) else { fail("no ast") }
  inspect(f.shapes()[0].shape.name().value, content="Name")
}
```
````

```bash
mise run format
git add pkgs/smithy-syntax/src/parser pkgs/smithy-syntax/src/lawkit pkgs/smithy-syntax/src/cst pkgs/smithy-syntax/src/ast
git commit -m "test(syntax): add recovery tests and the parser laws"
```

---

### Task 13: `report` package

**Files:**
- Create: `pkgs/smithy-syntax/src/report/moon.pkg`
- Create: `pkgs/smithy-syntax/src/report/render.mbt`
- Create: `pkgs/smithy-syntax/src/report/render_test.mbt`
- Create: `pkgs/smithy-syntax/src/report/render_law_test.mbt`
- Create: `pkgs/smithy-syntax/src/report/README.mbt.md`

**Interfaces:**
- Consumes: `@diagnostic.Diagnostic`, `@span.SourceText`.
- Produces: `render_terminal_to(d, source, logger : &Logger, color? : Bool) -> Unit` (the one renderer: writes into any core `Logger`, so a `StringBuilder`, a `@buffer.Buffer` or a caller's own sink); `render_terminal(d, source, color? : Bool) -> String` (default `true`) and `render_plain(d, source) -> String`, both thin wrappers over a `StringBuilder`; `render_short(d, source) -> String`; `render_all_to(ds, source, logger, color?)` and `render_all(ds : ArrayView[Diagnostic], source, color? : Bool) -> String` (every diagnostic, blank line between, then a summary line `N errors, M warnings`). The async `@io.Writer` is not used here; the CLI writes the returned strings to it.

- [ ] **Step 1: Write the failing snapshot tests**

`report/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax/span",
  "moonrockz/smithy-syntax/diagnostic",
}

import {
  "moonrockz/smithy-syntax/report",
  "moonrockz/smithy-syntax/span",
  "moonrockz/smithy-syntax/diagnostic",
  "moonrockz/smithy-syntax/parser",
  "moonrockz/smithy-syntax/lawkit",
  "moonrockz/expect",
  "moonbitlang/core/quickcheck",
  "moonbitlang/core/buffer",
} for "test"
```

`report/render_test.mbt`:

```moonbit
///|
fn first_error(text : String) -> (@diagnostic.Diagnostic, @span.SourceText) raise {
  let source = @span.SourceText::new(text, name="model.smithy")
  let r = @parser.parse(source)
  guard r.diagnostics.length() > 0 else { fail("no diagnostics") }
  (r.diagnostics[0], source)
}

///|
test "render_short is one line" {
  let (d, source) = first_error(
    (
      #|namespace a use b#C
      #|
    ),
  )
  inspect(
    @report.render_short(d, source),
    content="model.smithy:1:13: error[SM-PARSE-003]: I was expecting a line break here but found `use`",
  )
}

///|
test "render_plain shows the excerpt, labels, notes and hint" {
  let (d, source) = first_error(
    (
      #|$version: "2"
      #|namespace com.foo
      #|
      #|structure S {
      #|    a String
      #|}
      #|
    ),
  )
  inspect(
    @report.render_plain(d, source),
    content=(
      #|error[SM-PARSE-001]: UNEXPECTED TOKEN
      #|  --> model.smithy:5:7
      #|   |
      #| 4 | structure S {
      #|   | --------- the structure `S` started here
      #| 5 |     a String
      #|   |       ^^^^^^ I was expecting `:` after the member name `a` but found `String`
      #|   |
      #|   = I was parsing the structure `S` when I got stuck.
      #|   = example:
      #|       a: String
      #|
    ),
  )
}

///|
test "a warning renders with the warning header" {
  let (d, source) = first_error(
    (
      #|namespace a
      #|/// lost
      #|
    ),
  )
  let out = @report.render_plain(d, source)
  inspect(out.has_prefix(
    (
      #|warning[SM-PARSE-009]: DETACHED DOC COMMENT
      #|
    ),
  ), content="true")
  inspect(out.contains("= hint: Move it right before"), content="true")
}

///|
test "render_terminal adds colors and render_plain does not" {
  let (d, source) = first_error(
    (
      #|namespace a use b#C
      #|
    ),
  )
  inspect(@report.render_terminal(d, source).contains("\u{1b}["), content="true")
  inspect(@report.render_terminal(d, source, color=false) == @report.render_plain(d, source), content="true")
  inspect(@report.render_plain(d, source).contains("\u{1b}["), content="false")
}

///|
test "a span at the end of the file renders a caret after the last character" {
  let (d, source) = first_error(
    (
      #|namespace a
      #|string
      #|
    ),
  )
  let out = @report.render_plain(d, source)
  inspect(out.contains(
    (
      #| 2 | string
      #|   |       ^ 
    ),
  ), content="true")
}

///|
test "render_terminal_to writes into any Logger" {
  let (d, source) = first_error(
    (
      #|namespace a use b#C
      #|
    ),
  )
  let sb = StringBuilder()
  @report.render_terminal_to(d, source, sb, color=false)
  let buf = @buffer.Buffer()
  @report.render_terminal_to(d, source, buf, color=false)
  inspect(sb.to_string() == @report.render_plain(d, source), content="true")
  inspect(buf.to_string() == @report.render_plain(d, source), content="true")
}

///|
test "render_all ends with a summary" {
  let source = @span.SourceText::new(
    (
      #|namespace a
      #|use Foo
      #|/// x
      #|
    ),
    name="m.smithy",
  )
  let r = @parser.parse(source)
  let out = @report.render_all(r.diagnostics, source, color=false)
  inspect(out.has_suffix(
    (
      #|1 error, 1 warning
      #|
    ),
  ), content="true")
}

///|
test "long notes reflow at 80 columns" {
  let source = @span.SourceText::new(
    (
      #|namespace a
      #|metadata x = "y"
      #|
    ),
    name="m.smithy",
  )
  let r = @parser.parse(source)
  let out = @report.render_plain(r.diagnostics[0], source)
  for line in out.split(
    (
      #|
      #|
    ),
  ) {
    @expect.expect(line.length() <= 80).because(line.to_string()).to_be_true()
  }
}
```

- [ ] **Step 2: Implement render.mbt**

```moonbit
///|
/// The sink of a render: any core `Logger` (a `StringBuilder`, a
/// `@buffer.Buffer`, or the caller's own), plus the color switch.
priv struct Out {
  logger : &Logger
  color : Bool
  severity : @diagnostic.Severity
}

///|
fn Out::write(self : Out, s : String) -> Unit {
  self.logger.write_string(s)
}

///|
fn Out::code(self : Out, code : String) -> Unit {
  if self.color {
    self.logger.write_string("\u{1b}[\{code}m")
  }
}

///|
fn Out::header(self : Out) -> Unit {
  self.code(if self.severity is Error { "1;91" } else { "1;93" })
}

///|
fn Out::bold(self : Out) -> Unit {
  self.code("1")
}

///|
fn Out::border(self : Out) -> Unit {
  self.code("1;34")
}

///|
fn Out::primary(self : Out) -> Unit {
  self.code(if self.severity is Error { "1;91" } else { "1;93" })
}

///|
fn Out::secondary(self : Out) -> Unit {
  self.code("1;34")
}

///|
fn Out::reset(self : Out) -> Unit {
  self.code("0")
}

///|
let width : Int = 80

///|
/// Reflow `text` into lines of at most `max` columns, breaking at spaces.
fn reflow(text : String, max : Int) -> Array[String] {
  let lines : Array[String] = []
  let mut current = ""
  for word in text.split(" ") {
    let w = word.to_string()
    if current.length() == 0 {
      current = w
    } else if current.length() + 1 + w.length() <= max {
      current = current + " " + w
    } else {
      lines.push(current)
      current = w
    }
  }
  if current.length() > 0 || lines.is_empty() {
    lines.push(current)
  }
  lines
}

///|
/// A label on one line of the excerpt.
priv struct LineLabel {
  line : @span.Line
  start_col : @span.Column
  end_col : @span.Column
  text : String
  primary : Bool
}

///|
fn label_for(source : @span.SourceText, span : @span.Span, text : String, primary : Bool) -> LineLabel {
  let start = source.position(span.start)
  let line_span = source.line_span(start.line).unwrap_or(@span.Offset::zero().to(@span.Offset::zero()))
  let end_offset = if span.end() > line_span.end() { line_span.end() } else { span.end() }
  let end_col = @span.Column::new(end_offset.0 - line_span.start.0 + 1).unwrap_or(@span.Column::first())
  let end_col = if end_col <= start.column { start.column.next() } else { end_col }
  { line: start.line, start_col: start.column, end_col, text, primary }
}

///|
/// `file:line:col: severity[code]: message`.
pub fn render_short(d : @diagnostic.Diagnostic, source : @span.SourceText) -> String {
  let p = source.position(d.span.start)
  let sev = if d.severity is Error { "error" } else { "warning" }
  "\{source.name().unwrap_or("<input>")}:\{p.line.0}:\{p.column.0}: \{sev}[\{d.code}]: \{d.message}"
}

///|
/// The Rust and codespan layout: header, location, excerpt with labels,
/// notes, hint and example, written into `logger`.
pub fn render_terminal_to(
  d : @diagnostic.Diagnostic,
  source : @span.SourceText,
  logger : &Logger,
  color? : Bool = true,
) -> Unit {
  let out = { logger, color, severity: d.severity }
  let sev = if d.severity is Error { "error" } else { "warning" }
  out.header()
  out.write("\{sev}[\{d.code}]")
  out.reset()
  out.bold()
  out.write(
    (
      $|: \{d.title}
      $|
    ),
  )
  out.reset()
  let labels = [label_for(source, d.span, d.message, true)]
  for l in d.labels {
    labels.push(label_for(source, l.span, l.text, false))
  }
  labels.sort_by(fn(a, b) { a.line.compare(b.line) })
  let max_line = labels.iter().map(l => l.line.0).fold(init=1, (a, b) => if a > b { a } else { b })
  let gutter = max_line.to_string().length()
  let pad = " ".repeat(gutter)
  let p = source.position(d.span.start)
  out.border()
  out.write("\{pad} --> ")
  out.reset()
  out.write("\{source.name().unwrap_or("<input>")}:\{p.line.0}:\{p.column.0}\n")
  out.border()
  out.write(
    (
      $|\{pad}  |
      $|
    ),
  )
  out.reset()
  let mut last_line : @span.Line? = None
  for l in labels {
    if last_line != Some(l.line) {
      if last_line is Some(prev) && l.line.0 > prev.0 + 1 {
        out.border()
        out.write(
          (
            $|\{pad} ...
            $|
          ),
        )
        out.reset()
      }
      let number = l.line.0.to_string()
      let num_pad = " ".repeat(gutter - number.length())
      out.border()
      out.write("\{num_pad}\{number} | ")
      out.reset()
      out.write(source.line_text(l.line).unwrap_or(""))
      out.write(
        (
          #|
          #|
        ),
      )
      last_line = Some(l.line)
    }
    out.border()
    out.write("\{pad}  | ")
    out.reset()
    out.write(" ".repeat(l.start_col.0 - 1))
    if l.primary {
      out.primary()
    } else {
      out.secondary()
    }
    out.write((if l.primary { "^" } else { "-" }).repeat(l.end_col.0 - l.start_col.0))
    out.write(" \{l.text}")
    out.reset()
    out.write(
      (
        #|
        #|
      ),
    )
  }
  out.border()
  out.write(
    (
      $|\{pad}  |
      $|
    ),
  )
  out.reset()
  let body_width = width - gutter - 6
  for note in d.notes {
    for i, line in reflow(note, body_width) {
      out.border()
      out.write(if i == 0 { "\{pad}  = " } else { "\{pad}    " })
      out.reset()
      out.write(
        (
          $|\{line}
          $|
        ),
      )
    }
  }
  match d.hint {
    Some(h) =>
      for i, line in reflow(h, body_width - 6) {
        out.border()
        out.write(if i == 0 { "\{pad}  = " } else { "\{pad}    " })
        out.reset()
        if i == 0 {
          out.bold()
          out.write("hint: ")
          out.reset()
        } else {
          out.write("      ")
        }
        out.write(
          (
            $|\{line}
            $|
          ),
        )
      }
    None => ()
  }
  match d.example {
    Some(ex) => {
      out.border()
      out.write("\{pad}  = ")
      out.reset()
      out.bold()
      out.write(
        (
          #|example:
          #|
        ),
      )
      out.reset()
      for line in ex.split(
        (
          #|
          #|
        ),
      ) {
        out.write(
          (
            $|\{pad}      \{line}
            $|
          ),
        )
      }
    }
    None => ()
  }
}

///|
/// `render_terminal_to` into a fresh string.
pub fn render_terminal(
  d : @diagnostic.Diagnostic,
  source : @span.SourceText,
  color? : Bool = true,
) -> String {
  let sb = StringBuilder()
  render_terminal_to(d, source, sb, color~)
  sb.to_string()
}

///|
/// `render_terminal` without colors.
pub fn render_plain(d : @diagnostic.Diagnostic, source : @span.SourceText) -> String {
  render_terminal(d, source, color=false)
}

///|
/// Every diagnostic, a blank line between them, then a summary line,
/// written into `logger`.
pub fn render_all_to(
  ds : ArrayView[@diagnostic.Diagnostic],
  source : @span.SourceText,
  logger : &Logger,
  color? : Bool = true,
) -> Unit {
  let mut errors = 0
  let mut warnings = 0
  for d in ds {
    render_terminal_to(d, source, logger, color~)
    logger.write_string(
      (
        #|
        #|
      ),
    )
    if d.is_error() {
      errors += 1
    } else {
      warnings += 1
    }
  }
  let plural = (n : Int, word : String) => if n == 1 { "1 \{word}" } else { "\{n} \{word}s" }
  logger.write_string("\{plural(errors, "error")}, \{plural(warnings, "warning")}\n")
}

///|
/// `render_all_to` into a fresh string.
pub fn render_all(
  ds : ArrayView[@diagnostic.Diagnostic],
  source : @span.SourceText,
  color? : Bool = true,
) -> String {
  let sb = StringBuilder()
  render_all_to(ds, source, sb, color~)
  sb.to_string()
}
```

- [ ] **Step 3: Write the caret law**

`report/render_law_test.mbt`:

```moonbit
///|
test "law: every caret line fits its source line and the render never panics" {
  @quickcheck.check(
    (t : @lawkit.SmithyText) => {
      let source = @span.SourceText::new(t.text(), name="x.smithy")
      let r = @parser.parse(source)
      let mut ok = true
      for d in r.diagnostics {
        let out = @report.render_plain(d, source)
        ok = ok && out.length() > 0 && !out.contains("\u{1b}[")
        let lines : Array[String] = out.split(
          (
            #|
            #|
          ),
        ).map(x => x.to_string()).collect()
        for i, line in lines {
          // A caret line follows a numbered source line.
          guard line.contains("| ") && (line.contains("^") || line.contains("-")) && i > 0 else { continue }
          let prev = lines[i - 1]
          guard prev.contains(" | ") && !prev.contains("  | ") else { continue }
          let bar = prev.find(" | ").unwrap_or(0)
          let src_len = prev.length() - (bar + 3)
          let cbar = line.find("| ").unwrap_or(0)
          let caret_start = line.length() - line.unsafe_substring(start=cbar + 2, end=line.length()).trim_start(chars=" ").length() - (cbar + 2)
          ok = ok && caret_start <= src_len + 1
        }
      }
      ok
    },
    count=200,
    max_size=12,
    seed=4031,
  )
}
```

- [ ] **Step 4: Run the tests and adjust snapshots to the real layout after checking them by eye**

Run: `moon test -p moonrockz/smithy-syntax/report`
Expected: all pass. The multi-line snapshot in Step 1 is the target layout; if the first run differs in spacing only, confirm the layout reads well, then update the expected text.

- [ ] **Step 5: README and commit**

`report/README.mbt.md`:

````markdown
# report

Renders a `Diagnostic` with its source excerpt: `render_terminal` (ANSI
colors), `render_plain` (no colors), `render_short` (one line) and
`render_all` (a list with a summary).

```mbt check
test {
  let source = @span.SourceText::new("namespace a use b#C\n", name="m.smithy")
  let r = @parser.parse(source)
  inspect(@report.render_short(r.diagnostics[0], source).has_prefix("m.smithy:1:13: error[SM-PARSE-003]"), content="true")
}
```
````

```bash
mise run format
git add pkgs/smithy-syntax/src/report
git commit -m "feat(syntax): render diagnostics in the Rust and codespan layout"
```

---

### Task 14: Root facade, cookbook and documentation

**Files:**
- Modify: `pkgs/smithy-syntax/src/lib.mbt`
- Modify: `pkgs/smithy-syntax/src/moon.pkg`
- Modify: `pkgs/smithy-syntax/README.mbt.md`
- Create: `docs/cookbook/moon.mod`, `docs/cookbook/moon.pkg`, `docs/cookbook/README.md`
- Create: `docs/cookbook/parsing.mbt.md`
- Create: `docs/cookbook/diagnostics.mbt.md`
- Modify: `moon.work` (add `./docs/cookbook`)
- Modify: `README.md` (Tasks section: cookbook)

**Interfaces:**
- Produces: `@syntax.parse_idl(text : String, name? : String) -> ParseResult`, `@syntax.parse(SourceText)`, `@syntax.tokenize(SourceText)`, `@syntax.render_plain`, `@syntax.render_terminal`, `@syntax.render_short`, `@syntax.render_all`, and `pub using` re-exports of every public type of `span`, `diagnostic`, `scanner`, `ast`, `cst` and `parser`.

- [ ] **Step 1: Write the facade**

`src/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax/span",
  "moonrockz/smithy-syntax/diagnostic",
  "moonrockz/smithy-syntax/scanner",
  "moonrockz/smithy-syntax/ast",
  "moonrockz/smithy-syntax/cst",
  "moonrockz/smithy-syntax/parser",
  "moonrockz/smithy-syntax/report",
}

import {
  "moonrockz/smithy-syntax" @syntax,
  "moonrockz/expect",
} for "test"
```

`src/lib.mbt` (replace the file):

```moonbit
///|
/// The version of smithy-syntax, the same as `version` in `moon.mod`.
pub fn version() -> String {
  "0.1.0"
}

///|
/// Spans (UTF-16 unit offsets), positions and source text.
pub using @span {type Span, type Offset, type Length, type Line, type Column, type Position, type SourceText}

///|
/// Diagnostics: severity, labels and the problem record.
pub using @diagnostic {type Severity, type Label, type Diagnostic}

///|
/// The one-line description of a diagnostic code, or `None`.
pub fn diagnostic_description(code : String) -> String? {
  @diagnostic.description(code)
}

///|
/// The scanner: tokens, trivia and lexical errors.
pub using @scanner {
  type TokenStream,
  type Token,
  type TokenKind,
  type Trivia,
  type Comment,
  type CommentKind,
}

///|
/// Scan `source` into tokens with trivia. Lossless: `to_source()` is the text.
pub fn tokenize(source : SourceText) -> TokenStream {
  @scanner.tokenize(source)
}

///|
/// The AST.
pub using @ast {
  type IdlFile,
  type ControlStatement,
  type MetadataStatement,
  type NamespaceStatement,
  type UseStatement,
  type Statement,
  type ShapeStatement,
  type ApplyStatement,
  type Shape,
  type ShapeKind,
  type SimpleType,
  type EnumType,
  type AggregateType,
  type EntityType,
  type Mixins,
  type Trait,
  type TraitBody,
  type Member,
  type MemberTarget,
  type EnumMember,
  type InlineShape,
  type OperationTarget,
  type OperationProperty,
  type NodeValue,
  type NodeKvp,
  type NumberLiteral,
  type NumberValue,
  type Keyword,
  type ShapeId,
  type DocComment,
  type Node,
}

///|
/// The CST: every token grouped per statement.
pub using @cst {type IdlCst, type StatementCst, type StatementKind}

///|
/// The parser's result, version and error.
pub using @parser {type ParseResult, type ParseError, type Version}

///|
/// Parse a source text with recovery per statement.
pub fn parse(source : SourceText) -> ParseResult {
  @parser.parse(source)
}

///|
/// Parse Smithy IDL text. `name` is shown in rendered diagnostics.
///
/// ```mbt check
/// test {
///   let r = @syntax.parse_idl(
  (
    #|$version: "2"
    #|namespace com.foo
    #|
    #|string Name
    #|
  ),
  name="a.smithy",
)
///   inspect(r.has_errors(), content="false")
/// }
/// ```
pub fn parse_idl(text : String, name? : String) -> ParseResult {
  @parser.parse(@span.SourceText::new(text, name?))
}

///|
pub fn render_short(d : Diagnostic, source : SourceText) -> String {
  @report.render_short(d, source)
}

///|
pub fn render_plain(d : Diagnostic, source : SourceText) -> String {
  @report.render_plain(d, source)
}

///|
pub fn render_terminal(d : Diagnostic, source : SourceText, color? : Bool = true) -> String {
  @report.render_terminal(d, source, color~)
}

///|
/// Render into any core `Logger`, for callers with their own sink.
pub fn render_terminal_to(d : Diagnostic, source : SourceText, logger : &Logger, color? : Bool = true) -> Unit {
  @report.render_terminal_to(d, source, logger, color~)
}

///|
pub fn render_all(ds : ArrayView[Diagnostic], source : SourceText, color? : Bool = true) -> String {
  @report.render_all(ds, source, color~)
}
```

Run: `moon check` then `moon test -p moonrockz/smithy-syntax`
Expected: clean; if `pub using` rejects a name, it is a typo against Task 7's type names.

- [ ] **Step 2: Write the cookbook as a workspace member**

`docs/cookbook/moon.mod`:

```toml
name = "moonrockz/smithy_cookbook"

version = "0.1.0"

description = "Cookbook for moonrockz/smithy-syntax: task articles whose code is tested; not published"

repository = "https://github.com/moonrockz/smithy"

license = "Apache-2.0"

source = "."

import {
  "moonrockz/smithy-syntax@0.1.0",
  "moonrockz/expect@0.6.1",
}
```

`docs/cookbook/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax" @syntax,
  "moonrockz/expect",
} for "test"
```

`docs/cookbook/README.md`:

```markdown
# Cookbook

Task articles for `moonrockz/smithy-syntax`. Every code block is a test
that `moon test` runs.

- [Parse a model](parsing.mbt.md): the AST, the CST and the version.
- [Report problems](diagnostics.mbt.md): render diagnostics for people and for editors.
```

`docs/cookbook/parsing.mbt.md`:

````markdown
# Parse a model

`parse_idl` reads Smithy IDL text and gives back the AST, the CST and the
diagnostics. Nothing is resolved: shape IDs are as written.

```mbt check
test "read the shapes of a model" {
  let r = @syntax.parse_idl(
    (
      #|$version: "2"
      #|namespace com.example
      #|
      #|/// A person.
      #|structure Person {
      #|    @required
      #|    name: String
      #|    age: Integer = 0
      #|}
      #|
    ),
    name="person.smithy",
  )
  inspect(r.has_errors(), content="false")
  inspect(r.version, content="Some(V2)")
  guard r.ast is Some(file) else { fail("no ast") }
  let person = file.shapes()[0]
  inspect(person.docs[0].text, content=" A person.")
  guard person.shape is Aggregate(kind=Structure, members~, ..) else { fail("not a structure") }
  inspect(members.map(m => m.name.value), content="[\"name\", \"age\"]")
  inspect(members[1].default.bind(d => d.as_string()), content="None")
}
```

The CST keeps every token with its whitespace and comments, so a tool can
print the file back unchanged, also when a statement did not parse:

```mbt check
test "the CST is lossless" {
  let text = "namespace a\nstring Good\nstring 42\nstring AlsoGood\n"
  let r = @syntax.parse_idl(text)
  inspect(r.cst.to_source() == text, content="true")
  inspect(r.errors().length(), content="1")
  inspect(r.cst.skipped()[0].to_source(), content="string 42\n")
  guard r.ast is Some(file) else { fail("no ast") }
  inspect(file.shapes().map(s => s.shape.name().value), content="[\"Good\", \"AlsoGood\"]")
}
```
````

`docs/cookbook/diagnostics.mbt.md`:

````markdown
# Report problems

Each diagnostic has a code, a title, a message under its span, labels,
notes and a hint. Render them for a terminal, for a log, or as one line
for an editor.

```mbt check
test "render for a terminal and for an editor" {
  let source = @syntax.SourceText::new("namespace a\nstructure S {\n    a String\n}\n", name="s.smithy")
  let r = @syntax.parse(source)
  let d = r.diagnostics[0]
  inspect(d.code, content="SM-PARSE-001")
  inspect(d.title, content="UNEXPECTED TOKEN")
  inspect(@syntax.render_short(d, source), content="s.smithy:3:7: error[SM-PARSE-001]: I was expecting `:` after the member name `a` but found `String`")
  let plain = @syntax.render_plain(d, source)
  inspect(plain.contains("the structure `S` started here"), content="true")
  inspect(@syntax.render_all(r.diagnostics, source, color=false).has_suffix("1 error, 0 warnings\n"), content="true")
}
```
````

Add `"./docs/cookbook"` to `moon.work`. In the root `README.md`, add a line under Tasks: "The cookbook in `docs/cookbook` is a workspace member; `moon test` runs its articles."

- [ ] **Step 3: Update the module README**

Replace the body of `pkgs/smithy-syntax/README.mbt.md` with a status list (scanner, AST, CST, parser, diagnostics done; traversal and JSON AST planned), the `parse_idl` example from Step 1, installation (`moon add moonrockz/smithy-syntax`) and the package table from the spec.

- [ ] **Step 4: Run everything and commit**

Run: `mise run format && mise run lint && mise run validate && moon test`
Expected: green on every target: `mise run test` runs wasm, wasm-gc, js and native.

```bash
git add moon.work README.md docs/cookbook pkgs/smithy-syntax
git commit -m "docs(syntax): add the root facade, the cookbook and the package README"
```

---

### Task 15: Vendor the reference corpus as the compatibility kit (TCK)

**Files:**
- Create: `scripts/vendor-tck.mbtx`
- Modify: `.config/mise/config.toml` (task `tck:vendor`)
- Create: `tests/moon.mod`, `tests/README.md`, `tests/NOTICE` (the tests module; Task 16 adds its `bdd` package)
- Create: `tests/tck/moon.pkg`, `tests/tck/types.mbt`
- Create: `tests/tck/cases/...` (vendored `.smithy` files)
- Create: `tests/tck/cases.mbt` (generated)
- Create: `tests/tck/tck_test.mbt`
- Modify: `moon.work` (add `./tests`)
- Modify: `scripts/test.mbtx` (the tests module runs on js and native only; see Step 2)

Beads: this is task `smithy-2qe.1.3`; claim it, and record skipped cases in its notes.

**Interfaces:**
- Produces: `@tck.cases() -> Array[Case]` with `Case { path : String, kind : CaseKind, text : String }` and `CaseKind = Valid | Invalid(line~ : Int, column~ : Int, message~ : String) | Recovery`.

- [ ] **Step 1: Write the vendoring script**

`scripts/vendor-tck.mbtx`:

```moonbit
///|
/// Vendor the IDL cases of the Java reference's loader tests into
/// `tests/tck/cases/` and generate `tests/tck/cases.mbt`, so the
/// parity tests need no network and no file system on any target.
///
/// Usage: `mise run tck:vendor [-- <git ref>]` (default `main`). Needs `curl`.
/// Source: https://github.com/smithy-lang/smithy, Apache-2.0; the NOTICE is kept.
import {
  "moonbitlang/async@0.22.5",
  "moonbitlang/async@0.22.5/fs",
  "moonbitlang/async@0.22.5/process",
  "moonbitlang/core/env",
  "moonbitlang/core/json",
  "moonbitlang/x@0.5.5/sys",
}

///|
let base : String = "smithy-model/src/test/resources/software/amazon/smithy/model/loader"

///|
/// The directories to vendor and the kind of each.
let groups : Array[(String, String)] = [
  ("valid", "valid"),
  ("invalid", "invalid"),
  ("error-recovery", "recovery"),
]

///|
async fn fetch(url : String) -> String {
  let (out, code) = @process.collect_output("curl", ["-fsSL", url])
  if code != 0 {
    println("❌ curl failed for \{url}")
    @sys.exit(1)
  }
  out
}

///|
/// Every `.smithy` file path under `dir` (recursive), via the GitHub API.
async fn list_smithy(ref_ : String, dir : String) -> Array[String] {
  let listing = fetch("https://api.github.com/repos/smithy-lang/smithy/contents/\{dir}?ref=\{ref_}")
  let found : Array[String] = []
  guard @json.parse(listing) is Array(entries) else {
    println("❌ unexpected listing for \{dir}")
    @sys.exit(1)
    return found
  }
  for e in entries {
    guard e is Object(o) && o.get("type") is Some(String(t)) && o.get("path") is Some(String(p)) else { continue }
    if t == "dir" {
      found.append(list_smithy(ref_, p))
    } else if p.has_suffix(".smithy") {
      found.push(p)
    }
  }
  found
}

///|
/// MoonBit string literal syntax for `s` (multi-line `#|` form).
fn literal(s : String) -> String {
  let sb = StringBuilder()
  sb.write_string(
    (
      #|(
      #|
    ),
  )
  for line in s.split(
    (
      #|
      #|
    ),
  ) {
    sb.write_string("      #|")
    sb.write_string(line.to_string().trim_end(chars="\r").to_string())
    sb.write_string(
      (
        #|
        #|
      ),
    )
  }
  sb.write_string("    )")
  sb.to_string()
}

///|
async fn main {
  let args = @env.args()[1:]
  let ref_ = if args.length() > 0 { args[0] } else { "main" }
  let sha = fetch("https://api.github.com/repos/smithy-lang/smithy/commits/\{ref_}")
  let sha = match @json.parse(sha) {
    Object(o) => match o.get("sha") { Some(String(s)) => s; _ => ref_ }
    _ => ref_
  }
  println("📥 Vendoring the loader corpus at \{sha}")
  let gen = StringBuilder()
  gen.write_string(
    (
      $|// Generated by scripts/vendor-tck.mbtx from smithy-lang/smithy at \{sha}. Do not edit.
      $|
      $|
    ),
  )
  gen.write_string(
    (
      #|///|
      #|pub fn cases() -> Array[Case] {
      #|  [
      #|
    ),
  )
  let mut count = 0
  for g in groups {
    let (dir, kind) = g
    for path in list_smithy(ref_, "\{base}/\{dir}") {
      let text = fetch("https://raw.githubusercontent.com/smithy-lang/smithy/\{sha}/\{path}")
      let rel = path.substring(start=base.length() + 1)
      let local = "tests/tck/cases/\{rel}"
      let parent = local.substring(start=0, end=local.rev_find("/").unwrap_or(0))
      @fs.create_dir(parent, recursive=true)
      @fs.write_file(local, text)
      let kind_expr = match kind {
        "valid" => "Valid"
        "recovery" => "Recovery"
        _ => {
          // `// Syntax error at line L, column C: message` or `// Parse error at line L, column C near ...: message`.
          let first = text.split(
            (
              #|
              #|
            ),
          ).next().map(l => l.to_string()).unwrap_or("")
          match parse_header(first) {
            Some((line, column, message)) =>
              "Invalid(line=\{line}, column=\{column}, message=\{@json.stringify(String(message))})"
            None => "Invalid(line=0, column=0, message=\"\")"
          }
        }
      }
      gen.write_string(
        (
          $|    { path: "\{rel}", kind: \{kind_expr}, text: \{literal(text)} },
          $|
        ),
      )
      count += 1
    }
  }
  gen.write_string(
    (
      #|  ]
      #|}
      #|
    ),
  )
  @fs.write_file("tests/tck/cases.mbt", gen.to_string())
  @fs.write_file("tests/tck/TCK_SHA", sha + "\n")
  println("✅ Vendored \{count} cases")
}

///|
/// The line, column and message from an invalid case's first line.
fn parse_header(line : String) -> (Int, Int, String)? {
  guard line.has_prefix("//") else { return None }
  guard line.find("at line ") is Some(i) else { return None }
  let rest = line.substring(start=i + 8)
  guard rest.find(", column ") is Some(j) else { return None }
  let line_no = @strconv.parse_int(rest.substring(start=0, end=j)) catch { _ => return None }
  let rest2 = rest.substring(start=j + 9)
  let mut k = 0
  while k < rest2.length() && rest2.code_unit_at(k).to_int() >= '0'.to_int() && rest2.code_unit_at(k).to_int() <= '9'.to_int() {
    k += 1
  }
  let col = @strconv.parse_int(rest2.substring(start=0, end=k)) catch { _ => return None }
  let after = rest2.substring(start=k)
  let message = match after.find(": ") {
    Some(m) => after.substring(start=m + 2)
    None => after
  }
  Some((line_no, col, message.to_string()))
}
```

Add `"moonbitlang/core/strconv"` to the script's imports. In `.config/mise/config.toml`:

```toml
[tasks."tck:vendor"]
description = "Vendor the Java reference's loader test corpus into tests/tck, the compatibility kit (args: git ref)"
run = "moonx scripts/vendor-tck.mbtx"
```

- [ ] **Step 2: Create the tests module and run the vendoring**

`tests/moon.mod`:

```toml
name = "moonrockz/smithy_tests"

version = "0.1.0"

description = "Test module for moonrockz/smithy-syntax: reference corpus parity and moonspec acceptance features; not published"

repository = "https://github.com/moonrockz/smithy"

license = "Apache-2.0"

source = "."

warnings = "-implicit_impl_as_method"

import {
  "moonrockz/smithy-syntax@0.1.0",
  "moonrockz/expect@0.6.1",
  "moonrockz/moonspec@0.11.0",
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.5",
}
```

`tests/tck/moon.pkg`:

```
import {
}

import {
  "moonrockz/smithy_tests/tck" @tck,
  "moonrockz/smithy-syntax" @syntax,
  "moonrockz/expect",
} for "test"
```

In `scripts/test.mbtx`, run the tests module only where `moonbitlang/async` builds. Replace the single `moon test --target <t>` call per target with: for every target, `moon test pkgs/smithy pkgs/smithy-syntax apps/smithy docs/cookbook --target <t>` (one call per path if `moon test` takes a single path on this toolchain), and for `js` and `native` also `moon test tests --target <t>`. Keep the exit-code handling. Update the script's doc comment and the README task table line for `test` to say the tests module runs on js and native.

`tests/tck/types.mbt`:

```moonbit
///|
pub(all) enum CaseKind {
  Valid
  Invalid(line~ : Int, column~ : Int, message~ : String)
  Recovery
} derive(Eq, Debug)

///|
pub(all) struct Case {
  path : String
  kind : CaseKind
  text : String
} derive(Debug)
```

`tests/NOTICE`: copy the `NOTICE` file from the smithy-lang/smithy repository root verbatim, with a first line "The files under corpus/cases/ are copied from https://github.com/smithy-lang/smithy (Apache-2.0)."

`tests/README.md`: three lines naming the two packages (`tck`: the compatibility kit, parity over the vendored reference corpus; `bdd`: moonspec acceptance features from `tests/features`) and that the module is not published.

Add `"./tests"` to `moon.work`.

Run: `mise run tck:vendor`
Expected: `✅ Vendored N cases` with N around 150, `tests/tck/cases.mbt` and `tests/tck/TCK_SHA` written. Then `moon check` must be clean; if a vendored text contains a sequence the `#|` literal cannot hold, the generator must switch that case to a regular escaped literal (`@json.stringify(String(text))`).

- [ ] **Step 3: Write the parity tests**

`tests/tck/tck_test.mbt`:

```moonbit
///|
/// Cases known not to match yet, with the reason. Shrink this list; never
/// grow it without a note on beads task smithy-2qe.1.3.
let skipped : Array[(String, String)] = []

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
    guard c.kind is Invalid(line~, column~, message~) && !is_skipped(c.path) else { continue }
    let source = @syntax.SourceText::new(c.text, name=c.path)
    let r = @syntax.parse(source)
    let errs = r.errors()
    if errs.length() == 0 {
      failures.push("\{c.path}: expected an error at \{line}:\{column} (\{message}) but parsed clean")
      continue
    }
    // Semantic cases (line 0) only need some error; syntax cases must match the line.
    if line > 0 {
      let p = source.position(errs[0].span.start)
      if p.line.0 != line {
        failures.push("\{c.path}: expected line \{line} (\{message}) but got \{@syntax.render_short(errs[0], source)}")
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
      failures.push("\{c.path}: errors=\{r.errors().length()} shapes=\{f.shapes().length()}")
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
```

Many `invalid/` cases are semantic (duplicate shapes, bad trait values) and the reference reports them from the loader, not the parser; their header is not a syntax error and `parse_header` yields `line=0`, so they are skipped by the line check. For the ones that are syntax errors and do not match, add the path and reason to `skipped` and to the beads task notes.

- [ ] **Step 4: Run, fix, record**

Run: `moon test tests --target js` then `mise run test`
Expected: green. Each failure is either a parser bug (fix it in `pkgs/smithy-syntax`, with a unit test that pins it) or a case outside sub-project 1's scope (add to `skipped` with the reason). Then:

```bash
bd update smithy-2qe.1.3 --append-notes "Vendored <N> cases at <sha>. Skipped: <list with reasons>."
mise run format
git add scripts/vendor-tck.mbtx scripts/test.mbtx .config/mise/config.toml moon.work README.md tests
git commit -m "test(syntax): vendor the reference loader corpus and check parity"
bd close smithy-2qe.1.3 --reason "Corpus vendored and parity tests green"
```

---

### Task 16: Acceptance features with moonspec

**Files:**
- Create: `tests/features/parsing.feature`
- Create: `tests/features/diagnostics.feature`
- Create: `tests/features/recovery.feature`
- Create: `tests/bdd/moon.pkg`
- Create: `tests/bdd/syntax_world_wbtest.mbt`
- Modify: `.config/mise/config.toml` (task `test:bdd`)
- Modify: `README.md` (task table)

**Interfaces:**
- Consumes: `@syntax.parse_idl`, `@syntax.render_plain`, `@syntax.render_short`, the AST accessors of Task 7, `@moonspec.World`, `@moonspec.run_or_fail`, `@moonspec.RunOptions::new`, `@moonspec.FeatureSource::File`, `@moonspec.DocString`.
- Produces: one `SyntaxWorld` with the steps below, reused by all three features. Scenarios are the acceptance contract for sub-project 1; a behavior change must change a scenario.

- [ ] **Step 1: Write the features**

`tests/features/parsing.feature`:

```gherkin
Feature: Parsing Smithy IDL
  The parser reads Smithy IDL 2.0 text into a typed AST with spans and a
  lossless CST. These scenarios are the acceptance contract for the shapes,
  members, traits and node values the grammar defines.

  Scenario: Every statement form parses clean
    Given the Smithy model:
      """smithy
      $version: "2"
      metadata foo = ["bar"]
      namespace smithy.example
      use smithy.api#String

      /// Docs.
      @deprecated(message: "old")
      structure Foo with [Mix] {
          @required
          bar: String = "x"
          $baz
      }

      @mixin
      structure Mix {
          baz: Integer
      }

      enum Color {
          RED = "red"
          BLUE
      }

      operation GetFoo {
          input := {
              id: String
          }
          output: Foo
          errors: [NotFound]
      }

      @error("client")
      structure NotFound {}

      apply Foo @since("1.0")
      """
    When I parse the model
    Then there are no diagnostics
    And the version is "2"
    And the namespace is "smithy.example"
    And the shapes are "Foo, Mix, Color, GetFoo, NotFound"
    And the shape "Foo" has docs " Docs."
    And the shape "Foo" has the traits "deprecated"
    And the member "Foo$bar" targets "String" with default "x"
    And the member "Foo$baz" is elided
    And the CST prints the model back unchanged

  Scenario: Shape IDs are read as written, not resolved
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace a.b

      structure S {
          x: c.d#E$f
          y: Local
      }
      """
    When I parse the model
    Then there are no diagnostics
    And the member "S$x" targets "c.d#E$f"
    And the member "S$y" targets "Local"

  Scenario: Text blocks decode per the specification
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace a

      @documentation("""
          Hello,
            world.
          """)
      string S
      """
    When I parse the model
    Then there are no diagnostics
    And the trait "documentation" on "S" has the string value:
      """
      Hello,
        world.

      """

  Scenario: A 1.0 model may not use mixins
    Given the Smithy model:
      """smithy
      $version: "1.0"
      namespace a

      string S with [M]
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-007"
    And the first message is "Mixins can only be used with Smithy version 2 or later"
```

`tests/features/diagnostics.feature`:

```gherkin
Feature: Diagnostics
  Every problem is reported with a code, a title, a message under the span,
  context labels, notes in the first person and a hint, and rendered in the
  Rust and codespan layout.

  Scenario: A missing colon in a member names the member and the construct
    Given the Smithy model "model.smithy":
      """smithy
      $version: "2"
      namespace com.foo

      structure S {
          a String
      }
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-001"
    And the first diagnostic renders as:
      """
      error[SM-PARSE-001]: UNEXPECTED TOKEN
        --> model.smithy:5:7
         |
       4 | structure S {
         | --------- the structure `S` started here
       5 |     a String
         |       ^^^^^^ I was expecting `:` after the member name `a` but found `String`
         |
         = I was parsing the structure `S` when I got stuck.
         = example:
             a: String

      """
    And the short form is "model.smithy:5:7: error[SM-PARSE-001]: I was expecting `:` after the member name `a` but found `String`"

  Scenario: Two statements on one line
    Given the Smithy model "m.smithy":
      """smithy
      namespace a use b#C
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-003"
    And the first title is "MISSING LINE BREAK"
    And the first hint is "Put `use` on its own line."

  Scenario: A detached doc comment is a warning, not an error
    Given the Smithy model "m.smithy":
      """smithy
      namespace a

      string S
      /// nothing follows
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-009"
    And there are no errors
```

`tests/features/recovery.feature`:

```gherkin
Feature: Recovery per statement
  An error inside a statement is reported once; the parser resumes at the
  next statement and the CST keeps every token.

  Scenario: A broken shape does not take the next one with it
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace com.foo

      structure Bad {
          a String
      }

      string Foo
      """
    When I parse the model
    Then the diagnostics are "SM-PARSE-001"
    And the shapes are "Bad, Foo"
    And the CST prints the model back unchanged

  Scenario: An unclosed brace resumes at the next statement start
    Given the Smithy model:
      """smithy
      $version: "2"
      namespace com.foo

      structure Bad {
          a: String

      @deprecated
      string Bar
      """
    When I parse the model
    Then there is 1 error
    And the shapes include "Bar"
    And the CST has 1 skipped statement
    And the CST prints the model back unchanged
```

- [ ] **Step 2: Write the world**

`tests/bdd/moon.pkg`:

```
import {
  "moonrockz/smithy-syntax" @syntax,
  "moonrockz/moonspec",
  "moonrockz/expect",
  "moonbitlang/async",
} for "wbtest"
```

`tests/bdd/syntax_world_wbtest.mbt`:

```moonbit
///|
/// Scenario state shared by the three features.
struct SyntaxWorld {
  mut source : @syntax.SourceText
  mut result : @syntax.ParseResult?
}

///|
fn SyntaxWorld::new() -> SyntaxWorld {
  { source: @syntax.SourceText::new(""), result: None }
}

///|
fn SyntaxWorld::parsed(self : SyntaxWorld) -> @syntax.ParseResult raise {
  guard self.result is Some(r) else { fail("the model was not parsed yet") }
  r
}

///|
fn SyntaxWorld::file(self : SyntaxWorld) -> @syntax.IdlFile raise {
  guard self.parsed().ast is Some(f) else { fail("no AST") }
  f
}

///|
fn SyntaxWorld::shape(self : SyntaxWorld, name : String) -> @syntax.ShapeStatement raise {
  for s in self.file().shapes() {
    if s.shape.name().value == name {
      return s
    }
  }
  fail("no shape named \{name}")
}

///|
/// `Shape$member`.
fn SyntaxWorld::member(self : SyntaxWorld, id : String) -> @syntax.Member raise {
  guard id.find("$") is Some(i) else { fail("member id needs a $: \{id}") }
  let shape = self.shape(id.unsafe_substring(start=0, end=i))
  let member_name = id.unsafe_substring(start=i + 1, end=id.length())
  guard shape.shape is Aggregate(members~, ..) else { fail("\{id}: not an aggregate shape") }
  for m in members {
    if m.name.value == member_name {
      return m
    }
  }
  fail("no member \{id}")
}

///|
fn SyntaxWorld::first(self : SyntaxWorld) -> @syntax.Diagnostic raise {
  guard self.parsed().diagnostics.length() > 0 else { fail("no diagnostics") }
  self.parsed().diagnostics[0]
}

///|
fn trait_name(t : @syntax.Trait) -> String {
  t.id.value.name
}

///|
impl @moonspec.World for SyntaxWorld with fn configure(self, setup) {
  setup.given1("the Smithy model:", fn(doc : @moonspec.DocString) {
    self.source = @syntax.SourceText::new(doc.content)
  })
  setup.given2("the Smithy model {string}:", fn(name : String, doc : @moonspec.DocString) {
    self.source = @syntax.SourceText::new(doc.content, name~)
  })
  setup.when0("I parse the model", fn() { self.result = Some(@syntax.parse(self.source)) })
  setup.then0("there are no diagnostics", fn() raise {
    @expect.expect(self.parsed().diagnostics.map(d => d.code)).to_equal([])
  })
  setup.then0("there are no errors", fn() raise {
    @expect.expect(self.parsed().has_errors()).to_be_false()
  })
  setup.then1("there is {int} error", fn(n : Int) raise {
    @expect.expect(self.parsed().errors().length()).to_equal(n)
  })
  setup.then1("the diagnostics are {string}", fn(codes : String) raise {
    let expected = codes.split(", ").map(s => s.to_string()).collect()
    @expect.expect(self.parsed().diagnostics.map(d => d.code)).to_equal(expected)
  })
  setup.then1("the version is {string}", fn(v : String) raise {
    let expected = if v == "2" { Some(@syntax.Version::V2) } else { Some(@syntax.Version::V1) }
    @expect.expect(self.parsed().version).to_equal(expected)
  })
  setup.then1("the namespace is {string}", fn(ns : String) raise {
    @expect.expect(self.file().namespace.map(n => n.namespace.value)).to_equal(Some(ns))
  })
  setup.then1("the shapes are {string}", fn(names : String) raise {
    let expected = names.split(", ").map(s => s.to_string()).collect()
    @expect.expect(self.file().shapes().map(s => s.shape.name().value)).to_equal(expected)
  })
  setup.then1("the shapes include {string}", fn(name : String) raise {
    @expect.expect(self.file().shapes().map(s => s.shape.name().value).contains(name)).to_be_true()
  })
  setup.then2("the shape {string} has docs {string}", fn(name : String, docs : String) raise {
    @expect.expect(self.shape(name).docs.map(d => d.text).join("\n")).to_equal(docs)
  })
  setup.then2("the shape {string} has the traits {string}", fn(name : String, traits : String) raise {
    let expected = traits.split(", ").map(s => s.to_string()).collect()
    @expect.expect(self.shape(name).traits.map(trait_name)).to_equal(expected)
  })
  setup.then2("the member {string} targets {string}", fn(id : String, target : String) raise {
    guard self.member(id).target is Explicit(t) else { fail("\{id} is elided") }
    @expect.expect(t.value.to_string()).to_equal(target)
  })
  setup.then3("the member {string} targets {string} with default {string}", fn(id : String, target : String, default : String) raise {
    let m = self.member(id)
    guard m.target is Explicit(t) else { fail("\{id} is elided") }
    @expect.expect(t.value.to_string()).to_equal(target)
    @expect.expect(m.default.bind(v => v.as_string())).to_equal(Some(default))
  })
  setup.then1("the member {string} is elided", fn(id : String) raise {
    @expect.expect(self.member(id).target is Elided).to_be_true()
  })
  setup.then3("the trait {string} on {string} has the string value:", fn(trait_ : String, shape : String, doc : @moonspec.DocString) raise {
    for t in self.shape(shape).traits {
      if trait_name(t) == trait_ {
        guard t.body is Some(Node(v)) else { fail("trait \{trait_} has no node value") }
        @expect.expect(v.as_string()).to_equal(Some(doc.content))
        return
      }
    }
    fail("no trait \{trait_} on \{shape}")
  })
  setup.then0("the CST prints the model back unchanged", fn() raise {
    @expect.expect(self.parsed().cst.to_source()).to_equal(self.source.text())
  })
  setup.then1("the CST has {int} skipped statement", fn(n : Int) raise {
    @expect.expect(self.parsed().cst.skipped().length()).to_equal(n)
  })
  setup.then1("the first message is {string}", fn(m : String) raise {
    @expect.expect(self.first().message).to_equal(m)
  })
  setup.then1("the first title is {string}", fn(m : String) raise {
    @expect.expect(self.first().title).to_equal(m)
  })
  setup.then1("the first hint is {string}", fn(m : String) raise {
    @expect.expect(self.first().hint).to_equal(Some(m))
  })
  setup.then1("the first diagnostic renders as:", fn(doc : @moonspec.DocString) raise {
    @expect.expect(@syntax.render_plain(self.first(), self.source)).to_equal(doc.content)
  })
  setup.then1("the short form is {string}", fn(line : String) raise {
    @expect.expect(@syntax.render_short(self.first(), self.source)).to_equal(line)
  })
}

///|
async test "parsing feature" {
  @moonspec.run_or_fail(
    SyntaxWorld::new,
    @moonspec.RunOptions::new([@moonspec.FeatureSource::File("../features/parsing.feature")]),
  )
  |> ignore
}

///|
async test "diagnostics feature" {
  @moonspec.run_or_fail(
    SyntaxWorld::new,
    @moonspec.RunOptions::new([@moonspec.FeatureSource::File("../features/diagnostics.feature")]),
  )
  |> ignore
}

///|
async test "recovery feature" {
  @moonspec.run_or_fail(
    SyntaxWorld::new,
    @moonspec.RunOptions::new([@moonspec.FeatureSource::File("../features/recovery.feature")]),
  )
  |> ignore
}
```

If moonspec's `DocString` exposes the content under another field name on 0.11.0, or `then3` with a `DocString` last argument needs the `_ctx` form, adjust to the API in `moon info`'s `pkg.generated.mbti` of `moonrockz/moonspec`; the scenarios stay as written.

- [ ] **Step 3: Wire the task and run**

In `.config/mise/config.toml`:

```toml
[tasks."test:bdd"]
description = "Run the moonspec acceptance features (tests/bdd, js target)"
run = "moon test tests/bdd --target js"
```

Add the row to the README task table. Run: `mise run test:bdd` then `mise run test`.
Expected: every scenario passes. A scenario that fails on wording is a real difference between the plan's messages and the implementation: fix whichever is wrong against the Global Constraints, and keep the feature as the record.

- [ ] **Step 4: Format and commit**

```bash
mise run format
git add tests/features tests/bdd .config/mise/config.toml README.md
git commit -m "test(syntax): add moonspec acceptance features for parsing, diagnostics and recovery"
```

---

### Task 17: Wrap up the sub-project

**Files:**
- Modify: `AGENTS.md` (an "Architecture" note for `pkgs/smithy-syntax` and the diagnostics table pointer)
- Modify: `README.md` (status)
- Modify: `.github/workflows/ci.yml` only if a new mise task must run in CI (none expected: `mise run test` runs the library on every target, and the tests module and cookbook on js and native)

- [ ] **Step 1: Document the module for agents**

Add to `AGENTS.md`, after "Working rules":

```markdown
## Syntax module

`pkgs/smithy-syntax` is the IDL syntax layer. Its design is
`docs/superpowers/specs/2026-10-15-idl-syntax-design.md`; keep it current when
the API changes. Rules that tests enforce:

- The scanner and the CST are lossless: `to_source()` is the input text.
- Every diagnostic code is in `src/diagnostic/codes.mbt`; messages are in the
  first person and name the construct and the token found.
- The parser never panics and never raises out of `parse`; laws in
  `*_law_test.mbt` check this with quickcheck.
- `tests/tck` holds the vendored reference corpus; refresh it with
  `mise run tck:vendor`, and record skipped cases on the beads task.
- `tests/features/*.feature` are the acceptance contract, run by moonspec from
  `tests/bdd` (`mise run test:bdd`). Change the scenario when you change the
  behavior.
```

- [ ] **Step 2: Full check, beads, push**

Run: `mise run check`
Expected: lint, validate, test and build all green.

```bash
git add AGENTS.md README.md
git commit -m "docs: describe the syntax module for agents"
bd update smithy-2qe.1.2 --append-notes "Plan executed through Task 17."
bd close smithy-2qe.1.2 --reason "Implementation plan written and executed"
bd sync -y
```

Open a pull request from this branch to `main` with the beads epic ID in the description, then invoke the finishing-a-development-branch skill.

---


## Self-review notes

- Spec coverage: module and packages (Tasks 1, 14), positions (2), scanner (4, 5, 6), AST (7), CST (8), parser and recovery (9, 10, 11, 12), diagnostics (3, 11), report (13), testing and the compatibility kit (6, 12, 15), acceptance features (16), documentation (14, 17), out of scope untouched.
- Functional style: the scanner is `scan_at` (pure) unfolded by `scan_pieces` and grouped by `attach_trivia`, composed with `|>` in `tokenize`; diagnostics travel inside `Step` values. The parser's only mutable state is the private `Parser` cursor inside one `parse` call; `order_diagnostics` and the CST grouping are pure functions of their inputs; `parse` and `parse_text` are pipelines.
- Typed units: `Offset`, `Length`, `Line`, `Column` (Task 2) and `Depth` (Task 9) replace raw ints for positions, counts and nesting; `Span` is start plus length so its end never precedes its start. Raw `Int` remains only for array indexes (`pos`, `doc_head`, loop counters) and display widths. Each unit type has quickcheck laws (`span_law_test.mbt`, `depth_law_test.mbt`).
- Output sink: `report` renders into core's `&Logger` (`render_terminal_to`, `render_all_to`); the string-returning functions wrap a `StringBuilder`. The async `@io.Writer` is left to the CLI.
- Review Focus coverage: CRLF (Task 4 test "CRLF is one newline trivia", Task 9 test "two statements on one line"), text blocks (Task 5 decode tests, including the closing delimiter's own line counting toward the prefix as the spec says), adjacent shape IDs (Task 11 "spaces inside a shape id" and "a shape name must be an identifier"), deep nesting on wasm (Task 10 "150 nested arrays"), recovery keeps the next statement (Task 12 recovery tests).
- Type names used across tasks: `Offset`, `Length`, `Line`, `Column`, `Span`, `Position`, `SourceText`, `Diagnostic`, `Label`, `TokenKind`, `Trivia`, `Token`, `TokenStream`, `Piece`, `Step`, `Node`, `ShapeId`, `DocComment`, `NodeValue`, `NodeKvp`, `NumberLiteral`, `NumberValue`, `Shape`, `ShapeKind`, `Member`, `MemberTarget`, `EnumMember`, `InlineShape`, `OperationTarget`, `OperationProperty`, `Trait`, `TraitBody`, `Mixins`, `IdlFile`, `Statement`, `ShapeStatement`, `ApplyStatement`, `StatementCst`, `StatementKind`, `IdlCst`, `ParseResult`, `ParseError`, `Version`, `Depth`. `Show` is hand-written for `ShapeKind` (Task 7), `StatementKind` (Task 8) and `ShapeId` (Task 7); `derive(Show)` is not used.
