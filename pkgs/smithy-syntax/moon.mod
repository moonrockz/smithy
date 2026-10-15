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
