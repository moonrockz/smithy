# Vendored regex engine

The `@pattern` matcher of smithy-validation. It is a copy of the regex engine of MoonBit core, with
work-budget hooks, so that a match counts the work it does and stops when the validation call has no
work left. The cost model is in the package README (`../../README.mbt.md`, after "Preparation limits
patterns").

## Source

- Repository: https://github.com/moonbitlang/core (Apache-2.0, see `NOTICE`).
- Commit: `d3c49d103fbe7bcfe86a2299250bdfe52654e70d`, the core bundled with moonc
  `0.10.15+943464bfa`. Licence: `LICENSE`; attribution and statement of changes: `NOTICE`.

The copy is pinned to this core commit, not to the core of the pinned toolchain. MoonBit 0.10.18
replaced the core regex engine: `internal/regex_engine/automata` is gone, and
`string/internal/regex_engine` has a DFA and an NFA in place of `compile`, `states` and `translate`.
The budget hooks need a new cost model for that engine, so a toolchain bump deliberately does not
re-vendor this copy until bead `smithy-2qe.60` is done. The copy compiles and passes its tests with
the pinned toolchain.

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

`NOTICE` has the statement of changes. In short:

- All copied files: import paths, and the syntax that `moon fmt` writes (`Int32`, `UInt32`, `..<=`,
  `~` optional arguments). The repository's checks require that format. No behavior change.
- Budget hooks, in `automata/context.mbt`, `automata/delta.mbt`, `automata/slot_book.mbt`,
  `automata/thread_set.mbt`, `regex_engine/execute.mbt`, `regex_engine/regex.mbt` and
  `regex_engine/states.mbt`:
  - the meter, and one unit per expression node and thread that a derivative visits, five per thread
    that duplicate removal visits, and one per step;
  - the cost of each transition, remembered in a table and charged the first time a search takes
    it, with a stamp table, so that a search charges the same for the same input;
  - a share of table growth per transition, a cap on the states that the tables keep between
    searches, and `reset`;
  - the scratch set and the slot book are reset in time proportional to what they hold.
- Added: `automata/meter.mbt` (`Meter`, `Exhausted`), `regex_engine/meter.mbt` (`Regex::matches`),
  `regex.mbt` (the front: `Regex::compile`, which rejects capturing groups, and `Regex::matches`, in
  place of core's `string/regex.mbt`), `regex_law_test.mbt`, `LICENSE`, `NOTICE` and this file.

The default meter is unlimited, so the upstream tests see the upstream behavior.

## Check

`mise run regex:vendor:check` (part of `mise run validate`) fetches core at the commit above (a
shallow git fetch into `_build/regex-vendor-core`; the commit is `core_commit` in
`scripts/regex-vendor-check.mbtx`, and the check fails when this README or `NOTICE` names another
commit), copies the core packages into `_build/`, points their imports here, formats them with `moon fmt`, removes the
"Modified for" comments of this copy and compares the files. It fails when a file without budget
hooks differs, when a file is missing, or when a file is neither copied nor listed as added. Add
`-- --diff` to print the hooks.

## Update

1. Copy the paths in the table from the new core commit, with the tests and `moon.pkg` files.
2. Point the imports in each `moon.pkg` to `moonrockz/smithy-validation/internal/regex/...`.
3. Apply the hooks again; the list of changed files above is complete.
4. Update the commit and version here, in `NOTICE` and in `core_commit` of
   `scripts/regex-vendor-check.mbtx`.
5. Run `mise run format`, `mise run regex:vendor:check -- --diff`, then `moon test` in
   `pkgs/smithy-validation`. The law tests compare this copy with `@string.Regex` of the installed
   toolchain.
