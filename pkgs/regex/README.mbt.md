# moonrockz/regex

Runtime Boolean regular-expression search with bounded compilation and deterministic
work limits. This module depends only on MoonBit core. It does not implement ECMA-262;
Smithy translates its portable pattern profile in smithy-validation.

## Compilation

Patterns use MoonBit core's runtime regex dialect. Literals, classes, POSIX classes,
alternation, grouping, repetitions and anchors are supported. Dot includes newlines.
Digit/word/space shorthand escapes, lookaround, backreferences and Unicode properties
are unsupported. Capturing groups are accepted as grouping; this API returns no captures.
Matching searches unless the pattern supplies anchors.

POSIX classes and scoped `(?i:...)` case folding are ASCII-based. Literal class
dashes must be escaped as `\-`. Anchors refer to the whole input; `$` does not
also match before a final newline. String patterns support Unicode escapes,
not `\xHH` byte escapes. These are core regex semantics, not JavaScript semantics.

Defaults are 4,096 UTF-16 source units, 32 group levels and 1,024 expanded expression
units. Configurable maxima are 1,048,576 source units, 64 levels and 65,536 expanded units.
Work limits are 0 through 10,000,000 units. Zero represents a spent caller allowance.
Compilation-limit errors differ from syntax and unsupported-pattern errors.
The structural estimate counts BMP class intervals once and intervals reaching
astral characters twelve times to cover UTF-16 lowering. Sequence/alternation
adds one plus its children's sizes. Repetition multiplies by its upper bound,
or `max(1, min)` when unbounded, then adds two. Assertions count once; capture
annotations add nothing. Children must fit even under a zero-copy repetition.

```mbt check
///|
test {
  let pattern = "(a|b)+"
  let regex = @regex.Regex::compile(pattern)
  match regex.matches("!abba!", work=@regex.WorkLimit::new(10000)) {
    Complete(matched, used) => {
      assert_true(matched)
      assert_true(used > 0)
    }
    Exhausted(_) => fail("Expected enough work")
  }
  assert_eq(regex.matches("abba", work=@regex.WorkLimit::new(0)), Exhausted(0))
}
```

`MatchOutcome::Complete` carries a Boolean and used units. `Exhausted` carries
used units and proves neither a match nor a non-match. Used units never exceed
the supplied allowance. An exhausted call leaves the compiled program reusable.
`CompileLimits::new` and `WorkLimit::new` reject invalid configuration.
`CompileError` distinguishes `CompilationLimit`, `InvalidPattern` and
`UnsupportedPattern`. Compilation caps are independent of match allowances.

## Work model

The public Boolean executor uses core's NFA program and builds a DFA lazily.
Capture tags are epsilon transitions. Registers and capture-priority replay are
unnecessary for existence testing. Every call starts with fresh execution state,
so earlier successes or exhaustion cannot change its result or count. The full
upstream tagged executor remains private and retains its tests as a reference.

| Operation | Charge before work |
|---|---|
| Input scan | UTF-16 length plus one end marker, even for an early match |
| Initial scratch | Two cells per NFA node |
| Closure | One per popped node, plus one per stack push/pop and output append |
| Class membership | Interval count plus one, an upper bound on the tree walk |
| Key construction | One per allocated key cell and copied node |
| State indexing | One per hashed word, probe and equality word examined |
| Index growth | New slot cells, then one per existing entry and rehash probe |
| Transition table | One per symbol/end cell, plus two state record fields |
| Growable buffers | New fixed capacity plus copied live cells, then one per store |
| Buffer clearing | One per live cell cleared |

Growable buffers use explicit fixed arrays, with capacities starting at four and
doubling. The state index starts at eight slots and grows at half occupancy. Its
32-bit FNV-1a word hash and linear probe order are deterministic across targets;
collisions consume work. No variable-cost general hash-map operation runs on the
public matching path. A call stops before an unaffordable charge, including inside
closure, lookup or growth. No per-call state cache survives a call, so no flush,
register renaming or cross-call charge replay is needed.

Each logical array cell allocated during matching is prepaid, and key/table/record
storage is charged too. Thus live and total allocated matcher storage are O(work),
in addition to the immutable program. Conservatively, at most eight logical
machine words per used unit plus 64 fixed words cover cell payloads, optional
values and record/array headers: every nonempty array and state record has a
charged cell or creation charge. This bounds matcher data, not allocator metadata,
garbage-collector retention, runtime startup or process RSS. One unit covers a
constant amount of primitive work; counts are not CPU instructions or a deadline.
The input/end precharge covers the constant-time symbol and transition lookups.
Units are reproducible within this implementation, not across engine versions.

Measured with release builds on an Apple M5 Max, MoonBit 0.10.18+6c83a7f62 and
Node 24.14.1, with a 100,000-unit allowance. Each entry is the median of three
fresh processes; clocks have millisecond resolution. Times cover matching after
compilation and input construction. RSS is whole-process peak over two calls,
including the runtime, program and already-constructed input, not matcher-only
allocation. Repeated calls returned identical counts.

| Pattern/input | Outcome/units | Native ms / MiB RSS | JS ms / MiB RSS |
|---|---|---:|---:|
| Morphir FQName, 20-unit name | Match / 801 | <1 / 2.0 | <1 / 49.4 |
| Morphir FQName, 97-unit name | Match / 2,012 | <1 / 2.0 | 1 / 49.5 |
| `^(?:a?){150}a{150}$`, ten `a` units | Non-match / 28,229 | <1 / 2.1 | 2 / 55.1 |
| `a(?:a\|b){20}c`, 90,000 pseudo-random `a`/`b` units | Exhausted / 100,000 | <1 / 2.7 | 1 / 60.4 |
| `^a+$`, 90,000 `a` units | Match / 90,119 | <1 / 2.3 | 2 / 60.5 |
| `^(?:a+)+$`, 90,000 `a` units then `!` | Non-match / 90,134 | <1 / 2.3 | 2 / 60.6 |
| `^(?:a\|aa)+$`, same input | Non-match / 90,169 | <1 / 2.3 | 2 / 61.0 |
| `^a+$`, ten million `a` units | Exhausted / 0 | <1 / 40.2 | <1 / 453.2 |

The DFA case uses xorshift32 with seed 12345, shifts 13/17/5 and the low bit.
The optional-chain case that cost 899,611 units in the old engine completes under
the default allowance here. The two useful FQName cases previously cost 920 and
2,295 old-engine units. Exact numbers across engines have different definitions;
the useful cases still fit the same shared validation allowance. The large-input
case rejects before allocating a runner; its RSS comes primarily from constructing
the input. For repeatable target checks, the test fixtures pin `^a+$` on `aaaa`
to 123 units and `\bfoo\b` on `!foo!` to 336 units.

## Source and maintenance

Vendored from moonbitlang/core commit `417988f6e19738a7f683ce19a6cf5aaf52c96965`,
bundled with MoonBit `0.10.18+6c83a7f62`. See LICENSE and NOTICE.

| Core path | Module path |
|---|---|
| internal/regex_engine/shared_types | internal/shared_types |
| internal/regex_engine/shared_types/rechar_set | internal/shared_types/rechar_set |
| string/internal/regex_engine | internal/regex_engine |
| string/internal/regex_engine/ast | internal/regex_engine/ast |
| string/internal/regex_engine/symbol_map | internal/regex_engine/symbol_map |
| string/internal/regex_parser | internal/regex_parser |
| string/regex_profile.mbt, string/regex_utf16.mbt | Same file names |

Upstream tests are retained. Only `internal/regex_parser/parser.mbt` and
`internal/regex_parser/parser_context.mbt` have hooks in copied code, providing a
configurable recursion bound. Imports are redirected and formatting is normalized.
The unchanged core `regex_utf16.mbt` lowers Unicode scalars to UTF-16 sequences.

Added files are `moon.mod`, `moon.pkg`, this README, LICENSE/NOTICE, `limits.mbt`,
`regex.mbt`, `compile_test.mbt`, `matches_test.mbt`; engine `program.mbt`,
`meter.mbt`, `state_index.mbt`, `bounded.mbt`, `bounded_wbtest.mbt`; and
`internal/shared_types/rechar_set/bounded.mbt`. The program wrapper shares only
immutable compiler output. Added code supplies the bounded Boolean specialization.

Run `mise run regex:vendor:check -- --diff` to compare against the exact source
commit. It rejects missing files and unlisted drift and prints the two parser
hooks. Git subprocesses run without inherited `GIT_*` configuration. Run
`mise run test:regex-consumer` for the independent packaged example; normal
`test:validation-consumer` includes that check. A toolchain bump does not silently
change the source pin. To re-vendor, update the pin/source map, review parser hooks
and the Boolean NFA assumptions, then run the source check and all target laws.
