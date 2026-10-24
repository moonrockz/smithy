# Vendored regex engine

The `@pattern` matcher of smithy-validation. It is a copy of the regex engine of MoonBit core, with
work-budget hooks, so that a match counts the work it does and stops when the validation call has no
work left. The cost model is in the package README (`../../README.mbt.md`, after "Preparation limits
patterns").

## Source

- Repository: https://github.com/moonbitlang/core (Apache-2.0, see `NOTICE`).
- Commit: `d3c49d103fbe7bcfe86a2299250bdfe52654e70d`. All 56 copied `.mbt` files are byte-identical
  to that commit and to the core bundled with moonc `0.10.15+943464bfa`.

| Core path | Here |
|---|---|
| `internal/regex_engine/automata` | `automata` |
| `internal/regex_engine/shared_types` | `shared_types` |
| `internal/regex_engine/shared_types/rechar_set` | `shared_types/rechar_set` |
| `string/internal/regex_engine` | `regex_engine` |
| `string/internal/regex_engine/ast` | `regex_engine/ast` |
| `string/internal/regex_engine/symbol_map` | `regex_engine/symbol_map` |
| `string/internal/regex_parser` | `regex_parser` |
| `string/regex_profile.mbt`, `string/regex_utf16.mbt` | same names |

The upstream tests are copied too and run with the package tests.

## Changes

Only budget hooks. Each changed file has a "Modified for moonrockz/smithy-validation" comment.

- Changed: `automata/context.mbt` (the meter field), `automata/delta.mbt` and
  `automata/thread_set.mbt` (spend per visit), `regex_engine/execute.mbt` (spend per step),
  `regex_engine/states.mbt` (spend per table growth). These functions can now raise `Exhausted`.
- Added: `automata/meter.mbt` (`Meter`, `Exhausted`), `regex_engine/meter.mbt` (`Regex::matches`),
  `regex.mbt` (the front: `Regex::compile` and `Regex::matches`, in place of core's `string/regex.mbt`,
  whose builder API and compiler intrinsics the validator does not use), `regex_law_test.mbt`.
- Import paths in `moon.pkg` point to these packages.
- `moon fmt`, which the repository's checks require, rewrites `Int` to `Int32`, `UInt` to `UInt32`
  and `..=` to `..<=`. This changes no behavior.

The default meter is unlimited, so the upstream tests see the upstream behavior.

## Update

1. Copy the paths in the table from the new core commit, with the tests and `moon.pkg` files.
2. Point the imports in each `moon.pkg` to `moonrockz/smithy-validation/internal/regex/...`.
3. Apply the hooks again; the list of changed files above is complete.
4. Run `mise run format`, then `moon test` in `pkgs/smithy-validation`. The law tests compare this
   copy with `@string.Regex` of the installed toolchain.
5. Update the commit in this file and in `NOTICE`.
