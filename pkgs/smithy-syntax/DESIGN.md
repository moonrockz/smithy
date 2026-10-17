# Syntax package design

This is the maintained design for `moonrockz/smithy-syntax`. It describes the
implemented contracts. Working specs and plans stay local under `.dev/`.

## Responsibilities

The IDL scanner and parser produce a typed AST with source spans, a lossless
CST, and diagnostics. The traversal package provides a common node model,
walks, event streams, cursors and indexed tree queries over that AST. The
JSON AST codec is a separate representation with typed records and exact
numeric spellings.

Name resolution, prelude loading, mixin application, trait application and
model validation belong to `pkgs/smithy`. Shape IDs in the syntax AST remain
as written. The CST supports future formatting and editor tooling.

## Packages and facade

| Package | Contract |
|---|---|
| `span` | UTF-16 offsets, lengths, lines, columns, spans, positions and `SourceText` |
| `diagnostic` | Diagnostic records, severity, labels, `codes()` and descriptions |
| `scanner` | Tokens, trivia, `TokenStream`, `tokenize`, decoding and the scanner pipeline |
| `ast` | Typed IDL file, statements, shapes, traits, members and node values |
| `cst` | Every token grouped into statement runs, including skipped syntax |
| `parser` | `parse`, `parse_tokens`, `ParseResult`, `Version` and bounded nesting |
| `traversal` | `NodeRef`, walk/fold/reduce, visitors, pull/push events, paths, trees and cursors |
| `report` | Short, plain and terminal diagnostics, with string and logger outputs |
| `json_ast` | Typed Smithy JSON AST records, exact decoding and encoding |
| root | The curated public model types and parsing, traversal and rendering functions |
| `internal/lawkit` | Shared property-test generators, outside the public API |

The facade exports `parse`, `parse_idl`, `parse_tokens`, `tokenize`, `codes`,
`diagnostic_description`, the JSON AST codec functions, traversal functions
and diagnostic rendering functions, including `render_all_to`.

The facade does not re-export scanner pipeline records `Piece` and `Step`,
or parser implementation types `Depth` and `ParseError`. Callers that need
those types import their defining packages. Shared generators live at
`src/internal/lawkit`, imported as `moonrockz/smithy-syntax/internal/lawkit`.

Library dependencies follow the parsing stages. `traversal` and `report`
consume parser results without depending on each other. Tests can depend on
later stages to check cross-package contracts.

The module shares the workspace version in the root `moon.mod`.
`scripts/versions.mbtx set` updates module versions, sibling imports and
runtime version literals. `validate:versions` checks that they agree.

## Source positions and scanning

Offsets and lengths count UTF-16 code units. Lines and columns are 1-based.
`Span` is half open; its end is never before its start. Validating
constructors prevent negative offsets and lengths or zero lines and columns.

`SourceText` builds its line table once. Position lookup uses binary search;
`line_span` and `line_text` omit LF or CRLF line endings. A lone CR is source
whitespace rather than a line break. Slicing clamps spans to the text.

The scanner never fails. A bad lexical unit becomes an `Error` token and a
diagnostic. Keywords are contextual identifiers, and there is no EOF token.
The parser assembles shape IDs from adjacent identifier and punctuation
tokens. A comma is trivia and counts as whitespace.

Trivia after a token through the first newline belongs to `trivia_after`;
the remaining trivia belongs to the next token's `trivia_before`. Text with
no tokens keeps its trivia on the stream. Tokens and streams rebuild the
input exactly through `to_source()`.

Lexemes retain their original spelling. Scanner diagnostics validate
strings and text blocks; `unescape` and `text_block_value` produce decoded
values. Text blocks apply incidental-whitespace removal and escapes.

## AST and CST

The IDL AST uses source spans and read-only `ArrayView` collections. Nodes
and parser results support `Eq` and `Debug`. `ShapeKind::keyword()` and its
`Show` implementation return IDL keywords. Aggregate keywords use the same
spelling as their grammar productions.

Number literals retain their raw text and exact `BigInt` or decimal value.
`as_int64` succeeds only for an integer that fits. `as_double` is lossy and
returns signed infinity on overflow. Decimal parsing bounds exponent
magnitude at 4096 and scale at 28 to limit work and preserve exactness.

Documentation comments attach to shapes, members, enum members and inline
shapes. Unattached documentation remains available through traversal of the
file's comments. Traversal spans widen over attached documentation so every
child remains inside its parent.

Partial ASTs preserve duplicate members after `SM-PARSE-014`. Member names
are unique only when `ParseResult::has_errors()` is false. AST construct
spans end at the last consumed non-Error token; scanner holes must not widen
the preceding shape, apply statement or operation property.

The CST groups all tokens into statement runs in order. Each run records
its statement kind, optional name and span. A recovery run is `Skipped`.
Scanner holes remain in the runs, including holes at recovery boundaries.
Both statement and whole-file `to_source()` preserve the original text.

## Parsing and recovery

`parse(SourceText)` and `parse_tokens(TokenStream)` return a `ParseResult`
without raising. It contains the AST, CST, declared version and diagnostics.
An empty or comment-only file has an empty AST. The AST is absent only when
there are tokens and every statement fails.

Statements follow control, metadata, namespace, use and shape sections.
Statements need a line break or comment before the next statement. Member
and object-entry separators follow their own whitespace rules. Object and
trait entries require whitespace between pairs, including a space, comma,
comment or newline. Their separator diagnostics name the object or trait
body and the offending token. Value assignments require a line break.

A missing namespace is reported once while later shapes can still parse.
A late `use` is reported even when the namespace is missing. `$version`
accepts `1`, `1.0`, `2` and `2.0`. An absent declaration implies 1.0 for
syntax checks but remains `None` in the result. Version-specific constructs
report the first mismatch. Recovery before the namespace can leave the
version unknown and suppress unsupported assumptions about its value.

The parser bounds nesting at 100 for node values, member blocks and trait
bodies. Unfinished or excessive nesting produces diagnostics rather than a
panic. A failed statement recovers at an eligible column-1 statement start.
Member recovery keeps later members or resumes at the next shape. The
parser restores its context and depth after failed nested constructs.

## Diagnostics and rendering

Every diagnostic code is registered in `src/diagnostic/codes.mbt`. Messages
use the first person and identify the construct and token found. Diagnostics
include a primary span, secondary labels, notes, and optional hints and
examples. Documentation before `apply` or detached documentation is a warning.

Equal-position diagnostics preserve scanner then parser emission order.
Equal-line labels preserve the primary label followed by caller order.
Terminal rendering keeps source columns when replacing a lone CR with a
space, and uses the full 80-column budget for notes and hints.

`render_short` produces one editor-oriented line. `render_plain` and
`render_terminal` produce excerpts with labels, notes, hints and examples.
Logger variants support caller-owned sinks. `render_all` and `render_all_to`
add an error/warning summary.

## Traversal contracts

The kind table in `src/traversal/README.mbt.md` defines category, kind and
field names. Names follow the Smithy JSON AST or the IDL grammar. Walks,
folds, reductions, readers, trees and cursors keep explicit stacks.

Given the same `Control` decisions, traversal styles agree on enter and
leave order. `SkipChildren` still produces the node's leave event. `Stop`
ends the run without further reads or callbacks. Push handlers receive the
exact event records read from the source, one event at a time.

Tree identity refers to the underlying AST object, rather than structural
equality with a node from another parse. Returned mutable query arrays are
independent; their node and token records remain read-only. The kind table
also returns independent field arrays.

## Verification

`mise run check` runs lint, workspace/version validation, tests and builds.
Library laws run on wasm, wasm-gc, JavaScript and native. The acceptance and
reference modules use JavaScript and native. Task-script tests run through
`mise run test:scripts`.

Scanner and parser laws check losslessness, token tiling, span containment,
bounded recovery and absence of panics on generated input. Traversal laws
cover ordering, identity, source/handler interaction, array independence and
visitor dispatch for every kind-table row, with stops across the full tree.

The vendored Java corpus checks valid cases' declared versions and ordered
shape names. Invalid cases must produce errors and match available reference
lines, columns and message facts, with explicit reporting-convention
exceptions. Beads `smithy-2qe.1.20` records the comparison exceptions. Message
snapshots cover every emitted diagnostic title in the corpus and targeted
fixtures. Cases without an AST are accounted for explicitly.

`tests/features` is the acceptance contract. `tests/bdd` checks it with
moonspec, and the cookbook supplies checked examples for callers.
