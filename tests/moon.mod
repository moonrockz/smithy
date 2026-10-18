name = "moonrockz/smithy_tests"

version = "0.2.0"

description = "Test module for moonrockz/smithy-syntax: reference corpus parity and moonspec acceptance features; not published"

repository = "https://github.com/moonrockz/smithy"

license = "Apache-2.0"

source = "."

warnings = "-implicit_impl_as_method"

import {
  "moonrockz/smithy@0.2.0",
  "moonrockz/smithy-syntax@0.2.0",
  "moonrockz/expect@0.6.1",
  "moonrockz/moonspec@0.11.0",
  "moonbitlang/async@0.22.5",
  "moonbitlang/x@0.5.5",
}
