# Smithy IDL syntax layer: design

Date: 2026-10-15. Beads: epic `smithy-2qe.1` (sub-project 1 of `smithy-2qe`).

## Purpose

Parse Smithy IDL 2.0 text into a typed AST with spans, a lossless CST, and rich diagnostics, in a new
module `moonrockz/smithy-syntax`. The AST feeds the traversal package (sub-project 2) and the semantic
model loader (sub-project 4). The CST feeds a formatter and editor tooling later. Nothing in this layer
resolves names, applies traits or validates a model.

The design follows the sibling moonrockz parsers. krueger (Elm) defines the traversal and syntax-tree
conventions, gleam-parser (Gleam) the package layout, the lossless scanner, the statement-level CST and
the compiler-shaped diagnostics. Where this document says "as in gleam-parser", read that repository's
`AGENTS.md` and `src/` for the pattern.

## Decisions already taken

| Decision | Choice |
|---|---|
| Module | `pkgs/smithy-syntax`, `moonrockz/smithy-syntax`, version 0.1.0 in lockstep with the workspace |
| Grammar | Smithy IDL 2.0 ABNF from the specification; 1.0 files parse with the reference's version gating |
| Parser | Recursive descent over a lossless token stream, two-token lookahead |
| CST | Token stream grouped per statement, `to_source` byte for byte |
| Recovery | Per statement, and per member inside a member block; one diagnostic per recovery |
| Oracle | The Java reference implementation; its loader test corpus is vendored into the `tests` module as a compatibility kit (`tests/tck`) |
| Numbers | Exact: `BigInt` for integers, `moonbitlang/x/decimal` for decimals, raw text kept |
| Diagnostics | Elm and Rust style: title, primary and secondary labels, notes, hint, example |

## Module and packages

Add `./pkgs/smithy-syntax`, `./docs/cookbook` and `./tests` to `moon.work`. The module has `source = "src"` and
depends on `moonbitlang/x` (decimal), `moonbitlang/core` (bigint, quickcheck) and `moonrockz/expect`
(tests only).

| Package | Import path | Holds |
|---|---|---|
| `span` | `moonrockz/smithy-syntax/span` | `Span`, `Position`, `SourceText` |
| `diagnostic` | `.../diagnostic` | `Severity`, `Label`, `Diagnostic`, `codes()` |
| `scanner` | `.../scanner` | `TokenKind`, `Token`, `Trivia`, `Comment`, `TokenStream`, `tokenize`, `unescape`, `text_block_value` |
| `ast` | `.../ast` | the typed IDL tree |
| `cst` | `.../cst` | `IdlCst`, `StatementCst`, `StatementKind` |
| `parser` | `.../parser` | `parse`, `parse_tokens`, `ParseResult`, `Version`, `max_nesting` |
| `traversal` | `.../traversal` | `NodeRef`, the traversal styles, `Tree`, `TreeCursor` (sub-project 2) |
| `report` | `.../report` | `render_terminal`, `render_plain`, `render_short` |
| root | `moonrockz/smithy-syntax` | `parse_idl`, re-exports of every public type |

Dependencies point one way: `span` ← `diagnostic` ← `scanner` ← `ast` ← `cst` ← `parser` ← `traversal` and `report` ← root (`traversal` and `report` do not import each other).
Each package has a `README.mbt.md` with checked examples. `pkgs/smithy` and `apps/smithy` do not change
in this sub-project.

## Positions

- Offsets count UTF-16 code units, which MoonBit strings index and which the Java reference counts for
  its columns. `Span { start, length }` is half open; its end is `start.advance(length)`, so it never precedes its start. Offsets, lengths, lines and columns are newtypes (`Offset`, `Length`, `Line`, `Column`) with validating constructors.
- `Position { line, column }` is 1-based; the column counts UTF-16 units, so positions match the
  reference's `SourceLocation`.
- A line break is LF or CRLF. A lone CR is not a line break, as the specification's `NL` rule says.
- `SourceText::new(text, name?)` builds a line table once; `position(offset)` is a binary search;
  `line(n)` returns the text of a line for excerpts.

## Scanner

`tokenize(SourceText) -> TokenStream` never fails. A bad lexeme becomes an `Error` token and a diagnostic;
scanning continues after it.

Token kinds mirror the reference's `IdlToken`: `Identifier`, `Number`, `String`, `TextBlock`, `At`,
`Colon`, `Walrus`, `Equal`, `Dot`, `Pound`, `Dollar`, `LBrace`, `RBrace`, `LBracket`, `RBracket`,
`LParen`, `RParen`, `Error`. There is no end-of-file token. Keywords are identifiers; the parser
recognizes them by position, because Smithy keywords are contextual.

Shape IDs are assembled by the parser: `smithy.api#String$member` scans as `Identifier Dot Identifier
Pound Identifier Dollar Identifier`, and the parser accepts the sequence only when no trivia separates
the pieces.

Trivia: `Whitespace(text, span)`, `Newline(text, span)` (LF or CRLF, one trivia each), `Comma(span)`
(the specification treats a comma as whitespace), `Comment(Comment { kind: Line | Doc, text, span })`.
Each token carries `trivia_before` and `trivia_after`. Trivia after a token up to and including the
first newline belongs to that token's `trivia_after`; the rest goes to the next token's
`trivia_before`. A text with no tokens keeps its trivia on the stream. `Token::to_source` and
`TokenStream::to_source` rebuild the input byte for byte.

Lexemes stay raw. `unescape(lexeme)` decodes a quoted string; `text_block_value(lexeme)` applies the
specification's incidental-whitespace algorithm, then the escapes. Both return a value or a diagnostic
position, never panic.

Identifiers follow `IdentifierStart`: a letter, or one or more underscores followed by a letter or a
digit. Numbers follow the specification's JSON-like rule: no leading zeros, a fraction needs digits,
an exponent needs digits.

Scanner diagnostics, `SM-SCAN-001` onward: unexpected character, unterminated string, unterminated text
block, text block not starting with a newline, invalid escape, invalid unicode escape, invalid number.

## AST

Every node has a `span`. Every list is a read-only `ArrayView`. All types derive `Eq` and `Debug`.
`Node[T] { value, span }` wraps a leaf. Names follow the specification's productions.

File and statements:

- `IdlFile { control, metadata, namespace?, uses, statements, span }`.
- `ControlStatement { key : Node[String], value : NodeValue, span }`; `MetadataStatement` the same.
- `NamespaceStatement { namespace : Node[String], span }`; `UseStatement { id : Node[ShapeId], span }`.
- `Statement = Shape(ShapeStatement) | Apply(ApplyStatement)`.
- `ShapeStatement { docs, traits, shape, span }`.
- `ApplyStatement { target : Node[ShapeId], traits, block : Bool, span }`.

Shapes, one enum:

- `Simple(kind : SimpleType, name, mixins?)`, `SimpleType` being the thirteen simple types.
- `Enum(kind : Enum | IntEnum, name, mixins?, members : ArrayView[EnumMember])`.
- `Aggregate(kind : List | Map | Union | Structure | Set, name, for_resource?, mixins?, members)`.
  `Set` is parsed for 1.0 files; its meaning is the loader's job.
- `Entity(kind : Service | Resource, name, mixins?, body : NodeObject)`.
- `Operation(name, mixins?, properties : ArrayView[OperationProperty])` with `Input(target)`,
  `Output(target)`, `Errors(ids)`, where `target = Reference(Node[ShapeId]) | Inline(InlineShape)`.
- `Mixins { ids : ArrayView[Node[ShapeId]], span }`.
- `Member { docs, traits, name, target : Explicit(Node[ShapeId]) | Elided, default : NodeValue?, span }`.
- `EnumMember { docs, traits, name, value : NodeValue?, span }`.
- `InlineShape { traits, for_resource?, mixins?, members, span }`.
- `Trait { id : Node[ShapeId], body : None | Structure(kvps) | Node(NodeValue), span }`.

Node values: `Array(values)`, `Object(kvps)`, `Number(NumberLiteral)`, `Keyword(True | False | Null)`,
`String(decoded)`, `TextBlock(decoded)`, `ShapeId(ShapeId)`, each with a span. `NodeKvp { key :
Node[String], value, span }`. `NumberLiteral { text, value }` with `NumberValue = Integer(BigInt) |
Decimal(@decimal.Decimal)`: integer when the lexeme has no fraction and no exponent, else decimal. Both
are exact. `as_int64()` and `as_double()` are conveniences.

`ShapeId { namespace : String?, name : String, member : String? }` is syntactic and unresolved.

`DocComment { text, span }`, the `///` stripped, one entry per line, attached to shape statements,
members, enum members and inline shapes.

No JSON encoding of the AST in this sub-project.

## CST

`IdlCst { tokens, trivia, statements : ArrayView[StatementCst] }`. The statements tile the token array
in order. `StatementCst { kind, name?, tokens : ArrayView[Token], span }`, the span from the first
token's start to the last token's end, trivia excluded. `StatementKind = Control | Metadata | Namespace
| Use | Shape(ShapeKind) | Apply | Skipped`. `name` is the control key, metadata key, namespace, used
shape ID, shape name or apply target; `None` for a skipped run.

`Skipped` is the run of tokens the parser gave up on after an error, up to the next statement start.
`StatementCst::to_source` and `IdlCst::to_source` rebuild the text. Members, traits and node values are
not CST nodes; the AST spans locate them in the token stream.

## Parser

`parse(SourceText) -> ParseResult` and `parse_tokens(TokenStream) -> ParseResult`. `ParseResult { ast :
IdlFile?, cst : IdlCst, version : Version?, diagnostics }`. The AST is `None` only when nothing could be
read; otherwise it is the partial tree.

- Statement termination follows the grammar's `BR`: after a statement the parser requires a newline or a
  comment in the trivia before the next token, else "MISSING LINE BREAK".
- The parser never panics. `max_nesting = 100` on node values, member blocks and trait bodies raises a
  diagnostic instead of overflowing the wasm stack.
- `$version` accepts `1`, `1.0`, `2`, `2.0`; anything else is the reference's "Unsupported Smithy
  version number". A missing `$version` means 1.0, as in the reference. In a 1.0 file, mixins, target
  elision, resource properties and inline input or output are errors with the reference's facts.
- Doc comments are gathered from the trivia of the token that starts a shape, member, enum member or
  inline shape. A doc comment anywhere else stays in trivia and gets the warning "DETACHED DOC COMMENT".
  Docs before `apply` are a warning (`SM-PARSE-008`), as the reference's own corpus shows (`valid/doc-comments`).

Recovery: on an error inside a statement the parser records one diagnostic, then skips tokens until it
finds a token that is the first on its line and begins a statement: a shape type keyword, `apply`,
`use`, `metadata`, `namespace`, `@`, `$` or a doc comment. The skipped tokens form a `Skipped` statement.
Inside a member block, an error skips to the next member start or the closing brace. No cascades.

The parser keeps a stack of the constructs it is inside (shape, member block, trait body, node object,
node array, apply block). A failure takes its title and its "I was parsing ..." sentence from the
innermost one, and the construct's start becomes a secondary label.

## Diagnostics

`Diagnostic { code, severity, title, message, span, labels, notes, hint?, example? }`.

- `code`: `SM-SCAN-nnn` or `SM-PARSE-nnn`, listed in `codes()`; the TCK added `SM-PARSE-012` (duplicate operation property), `SM-PARSE-013` (duplicate control statement) and `SM-PARSE-014` (duplicate member name), all reported by the reference as syntax errors; a test checks the table against the
  codes the scanner and parser emit.
- `severity`: `Error | Warning`.
- `title`: short and in capitals, Elm style: `UNFINISHED SHAPE`, `MISSING LINE BREAK`, `UNKNOWN ESCAPE`.
- `message`: one line, shown under the primary caret.
- `labels`: secondary `Label { span, text }` entries, such as "the structure started here".
- `notes`: paragraphs after the excerpt in Elm's voice: first person, what I was parsing, what I saw,
  what I expected. `hint`: one actionable suggestion. `example`: an optional correct snippet.

Message rules: never "syntax error" alone; name the construct and the token found; when the fix is one
token, say it; where the reference has an error for the same case, keep its facts in our voice. Doc
comments, line breaks and the 1.0-versus-2.0 gating each get an explaining note.

## Report

- `render_terminal(diagnostic, source, color~)`: Rust and codespan layout. `error[SM-PARSE-012]:
  UNFINISHED SHAPE`, then `--> model.smithy:13:9`, a line-number gutter with the excerpt, `^` runs under
  the primary span with the message, `-` runs under secondary labels with their text, the notes, then
  `= hint:` and `= example:`. Text reflows to 80 columns.
- `render_plain`: the same without color. `render_short`: `file:line:col: severity[code]: message`.
- Every message has a snapshot test. A law checks that rendered carets fall inside the quoted line.

## Testing

All tests run on wasm, wasm-gc, js and native through `mise run test`.

- Unit and snapshot tests beside each package. Parser snapshots use the `Debug` form.
- Law tests with quickcheck in `*_law_test.mbt`: tokens and trivia rebuild the source; spans tile the
  text and are monotonic; `cst.to_source()` equals the input with and without errors; CST statements
  tile the token array; AST spans lie inside their parent's; the parser never panics on random text,
  random token sequences, or valid text with one random edit.
- Compatibility kit `tests/tck` in the `tests` module (`moonrockz/smithy_tests`, not published; it depends on `moonbitlang/async`, so it runs on js and native). `tests/bdd` runs the moonspec acceptance features in `tests/features`. It vendors the reference's
  loader tests (`smithy-model/src/test/resources/software/amazon/smithy/model/loader`, Apache-2.0, notice
  kept) and its idl-serialization cases. Valid files must parse clean, with shape names and `$version`
  checked. Invalid files must produce an error, compared on line and on the facts of the message. The
  beads task `smithy-2qe.1.3` records skipped cases and why.

## Documentation

`README.mbt.md` per package, `docs/cookbook/parsing.mbt.md` and `docs/cookbook/diagnostics.mbt.md` with
checked examples, and the root README package table updated with the module, the cookbook and the tests module. `src/lawkit` holds the quickcheck generators shared by the law tests.

## Out of scope

Traversal and `Tree` (sub-project 2), the JSON AST (3), name resolution, prelude, trait validation and
mixin application (4), CLI commands and JSON diagnostics (5), a printer or formatter, and the Smithy 1.0
`@box` and set semantics beyond parsing the syntax.
