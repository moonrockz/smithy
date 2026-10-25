$version: "2"

namespace morphir.ir.v4

/// A name: segments joined by "-". A segment is all lowercase (a word) or
/// all uppercase (an initialism). NameString in morphir-ir-v4.yaml.
@pattern("^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$")
string Name

/// "package:module#name", such as "morphir/SDK:basics#int".
/// FQNameString in morphir-ir-v4.yaml.
@pattern("^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*:([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*#([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*$")
string FQName

/// Names joined by "/", such as "morphir/SDK". PathString in morphir-ir-v4.yaml.
@pattern("^([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*(/([a-z0-9]+|[A-Z0-9]+)(-([a-z0-9]+|[A-Z0-9]+))*)*$")
string Path
