$version: "2"

/// The Morphir IR document bundle: one version field and the root and profiles of each supported release.
///
/// The support table is [3.0.0,3.2.0),[4.0.0,4.1.0) (finos/morphir docs/spec/ir/format-version.md). v3.0 and v3.1
/// have separate roots, because only v3.1 has the Specs distribution. v1 and v2 are not supported. Selecting a
/// release never migrates a document to another release's root.
namespace morphir.ir

use smithy.serialization#jsonBundle
use smithy.serialization#jsonEncoding

@jsonBundle(
    id: "morphir"
    version: { field: "formatVersion", adapter: "morphir.format-version" }
    releases: [
        { since: "3.0.0", until: "3.1.0", root: "morphir.ir.v3#IRFile30", profiles: ["morphir-v3"] }
        { since: "3.1.0", until: "3.2.0", root: "morphir.ir.v3#IRFile31", profiles: ["morphir-v3"] }
        {
            since: "4.0.0"
            until: "4.1.0"
            root: "morphir.ir.v4#IRFile"
            profiles: ["morphir-v4", "morphir-v4-expanded"]
        }
    ]
)
structure MorphirIR {}

/// A formatVersion that the bundle supports, as a standalone node: the format-version corpus and the MCK
/// FormatVersion cases check it. The adapter refuses invalid spellings; the pattern refuses releases outside
/// the support table.
@jsonEncoding(base: { adapter: "morphir.format-version" })
@pattern("^(3\\.[01]|4\\.0)\\.(0|[1-9][0-9]*)$")
string SupportedFormatVersion
