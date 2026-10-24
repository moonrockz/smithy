// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Modified for moonrockz/smithy-validation: only compilation and a metered
// boolean match remain of `@string.Regex`.

///|
/// A compiled regular expression with the syntax of `@string.Regex`.
pub struct Regex {
  priv source : String
  priv re : @re.Regex
}

///|
/// The pattern text.
pub impl @debug.Debug for Regex with fn to_repr(self) {
  @debug.Repr(self.source)
}

///|
/// Raised when a pattern has a capturing group.
pub suberror CapturingGroup

///|
/// Compile `pattern` as `@string.Regex(pattern)` does, then lower it to UTF-16.
/// A capturing group raises `CapturingGroup`: the work of one visit is constant
/// only when the automaton tracks no group but the whole match.
pub fn Regex::compile(pattern : StringView) -> Regex raise {
  let pat = @regex_parser.parse(
    profile=re_profile_unicode,
    pattern,
    mode=String,
  )
  if has_capture(pat) {
    raise CapturingGroup
  }
  {
    source: pattern.to_owned(),
    re: @re.compile(profile=re_profile_utf16, re_lower_to_utf16(pat)),
  }
}

///|
/// Search `input` as `@string.Regex::execute` does, spending at most `work`
/// units. Returns whether the search matched and the units it spent, or `None`
/// when it needs more than `work` units.
pub fn Regex::matches(
  self : Regex,
  input : StringView,
  work~ : Int32,
) -> (Bool, Int32)? {
  self.re.matches(input, work~)
}

///|
/// Whether `pattern` has a capturing group. The parser bounds the nesting.
fn has_capture(pattern : @re.Pattern) -> Bool {
  match pattern.desc {
    Capture(_, ..) => true
    Char(_) | Assertion(_) => false
    Sequence(items) | Alternation(items) => items.iter().any(has_capture)
    Quantifier(_, item) | Preference(_, item) => has_capture(item)
  }
}
