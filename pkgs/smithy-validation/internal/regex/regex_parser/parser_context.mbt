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
// Modified for moonrockz/smithy-validation: syntax that `moon fmt` writes
// (Int32 and UInt32 for Int and UInt, `..<=` for `..=`, `~` for optional
// arguments with a default). No behavior change.

///|
/// Type `Mode` used by this package APIs.
pub(all) enum Mode {
  Bytes
  String
}

///|
priv struct ParserContext {
  profile : @re.Profile
  base : Int32
  ignore_case : Bool
  mode : Mode
}

///|
fn ParserContext::new(
  profile~ : @re.Profile,
  base~ : Int32,
  mode~ : Mode,
) -> ParserContext {
  { profile, base, ignore_case: false, mode, }
}

///|
fn ParserContext::error_at(
  self : ParserContext,
  view : StringView,
  hint : String,
  offset~ : Int32 = 0,
) -> ParserError {
  ParserError(at=view.start_offset() - self.base + offset, hint~)
}
