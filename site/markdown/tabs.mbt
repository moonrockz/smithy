///|
/// The Markdown fence that `parse` turns into `Tabs`: the tabs as one line of JSON.
pub fn tabs_fence(tabs : Array[Tab]) -> String {
  "```tabs\n" + Json(tabs).stringify() + "\n```"
}
