///|
/// The version of this tool. `scripts/versions.mbtx` keeps it equal to `version` in `moon.mod`.
pub let version : String = "0.0.1"

///|
pub fn version_text() -> String {
  "zig-cross \{version}"
}
