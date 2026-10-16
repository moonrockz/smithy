///|
/// The version of this tool. `scripts/versions.mbtx` keeps it equal to `version` in `moon.mod`.
pub let version : String = "0.1.0"

///|
pub fn version_text() -> String {
  "zig-cross \{version}"
}
