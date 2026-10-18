name = "moonrockz/smithy-syntax"

version = "0.2.0"

description = "Smithy syntax for MoonBit: lossless IDL parser, traversal, diagnostics and typed JSON AST codec"

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
