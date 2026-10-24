///|
/// One file of a lesson: the editor tab name and the text.
pub(all) struct LessonFile {
  name : String
  text : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend LessonFile with Eq::{equal, not_equal}

///|
pub extend LessonFile with @debug.Debug::{to_repr}

///|
pub extend LessonFile with ToJson::{to_json}

///|
pub extend LessonFile with FromJson::{from_json}

///|
/// What a case must show. `events` use the key of `event_key`; each string of
/// `output_contains` must be a substring of the output text.
pub(all) struct Expectation {
  events : Array[String]
  output_contains : Array[String]
}

///|
/// A named edit of the starting files, and the result that it must give.
pub(all) struct Case {
  name : String
  files : Array[LessonFile]
  expect : Expectation
}

///|
pub(all) struct Lesson {
  dir : String
  number : Int32
  slug : String
  title : String
  section : String
  output : @samples.Output?
  selector : String?
  spec : String
  text : String
  files : Array[LessonFile]
  cases : Array[Case]
}

///|
/// The lessons, sorted by number.
pub(all) struct Tour {
  lessons : Array[Lesson]
}

///|
/// The contents: consecutive lessons with the same section form one section.
pub fn Tour::sections(self : Tour) -> Array[(String, Array[Lesson])] {
  let result : Array[(String, Array[Lesson])] = []
  for lesson in self.lessons {
    let last = result.length() - 1
    if last >= 0 && result[last].0 == lesson.section {
      result[last].1.push(lesson)
    } else {
      result.push((lesson.section, [lesson]))
    }
  }
  result
}

///|
pub fn Tour::find(self : Tour, slug : String) -> Lesson? {
  self.lessons.search_by(l => l.slug == slug).map(i => self.lessons[i])
}

///|
/// The previous and the next lesson.
pub fn Tour::neighbours(self : Tour, lesson : Lesson) -> (Lesson?, Lesson?) {
  match self.lessons.search_by(l => l.number == lesson.number) {
    None => (None, None)
    Some(i) =>
      (
        if i > 0 {
          Some(self.lessons[i - 1])
        } else {
          None
        },
        if i + 1 < self.lessons.length() {
          Some(self.lessons[i + 1])
        } else {
          None
        },
      )
  }
}

///|
/// The starting files, replaced or added by name, sorted by name.
pub fn Lesson::case_files(self : Lesson, case : Case) -> Array[LessonFile] {
  let merged : Array[LessonFile] = []
  for file in self.files {
    merged.push(file)
  }
  for file in case.files {
    match merged.search_by(f => f.name == file.name) {
      Some(i) => merged[i] = file
      None => merged.push(file)
    }
  }
  merged.sort_by(fn(a, b) { compare_code_units(a.name, b.name) })
  merged
}

///|
/// SHA-256 as lower-case hex, over the files sorted by name, of
/// `name + "\u0000" + text + "\u0000"` in UTF-8.
pub fn digest(files : Array[LessonFile]) -> String {
  let sorted = files.copy()
  sorted.sort_by(fn(a, b) { compare_code_units(a.name, b.name) })
  let buf = StringBuilder()
  for file in sorted {
    buf.write_string(file.name)
    buf.write_char('\u0000')
    buf.write_string(file.text)
    buf.write_char('\u0000')
  }
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(buf.to_string())))
}

///|
/// `id|SEVERITY|shape`, with `-` for an event without a shape.
pub fn event_key(id : String, severity : String, shape : String?) -> String {
  id + "|" + severity + "|" + shape.unwrap_or("-")
}

///|
/// Only these severities are compared with the reference.
pub fn is_compared(severity : String) -> Bool {
  severity == "WARNING" || severity == "DANGER" || severity == "ERROR"
}

///|
/// Order by UTF-16 code unit, then by length. `String::compare` orders by
/// length first, so the digest and the file order cannot use it.
pub fn compare_code_units(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  a.length().compare(b.length())
}

///|
/// The folder of a lesson: its number in two digits, `-`, and its slug.
pub fn lesson_dir(number : Int32, slug : String) -> String {
  let digits = if number < 10 { "0\{number}" } else { "\{number}" }
  "\{digits}-\{slug}"
}

///|
/// The repository path of the lessons folder.
pub let lessons_root : String = "site/tour/lessons"

///|
/// The repository path of the text of a lesson.
pub fn lesson_source(number : Int32, slug : String) -> String {
  "\{lessons_root}/\{lesson_dir(number, slug)}/lesson.md"
}

///|
/// The slug of the lesson whose text is at the repository path `path`, or
/// `None` when `path` is not the text of a lesson.
pub fn slug_of_source(path : String) -> String? {
  let prefix = lessons_root + "/"
  let suffix = "/lesson.md"
  guard path.length() > prefix.length() + suffix.length() &&
    path.has_prefix(prefix) &&
    path.has_suffix(suffix) else {
    return None
  }
  let dir = path[prefix.length():path.length() - suffix.length()].to_owned()
  let chars = dir.to_array()
  if chars.length() < 4 ||
    !(chars[0].is_ascii_digit() && chars[1].is_ascii_digit()) ||
    chars[2] != '-' ||
    dir.contains("/") {
    return None
  }
  Some(dir[3:].to_owned())
}

///|
/// A link to a lesson.
pub(all) struct LessonLink {
  slug : String
  title : String
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend LessonLink with Eq::{equal, not_equal}

///|
pub extend LessonLink with @debug.Debug::{to_repr}

///|
pub extend LessonLink with ToJson::{to_json}

///|
pub extend LessonLink with FromJson::{from_json}

///|
/// What the page of one lesson needs: the pre-render writes it in the site
/// data, and the lesson component starts from it.
pub(all) struct LessonPage {
  slug : String
  title : String
  section : String
  /// The place of the lesson in the tour, from 1, and the number of lessons.
  number : Int32
  total : Int32
  output : @samples.Output?
  selector : String?
  /// The smithy.io section that the lesson teaches.
  spec : String
  /// The starting files.
  files : Array[LessonFile]
  /// The `digest` of the starting files. Stored edits of other files are stale.
  digest : String
  previous : LessonLink?
  next : LessonLink?
  /// The versioned URL of the playground Worker.
  worker : String
  /// The localStorage key of the edits: `smithy-tour:<channel>:<slug>`. The
  /// channels share an origin, so the key holds the channel.
  storage_key : String
  /// The href of the playground page; `None` when the lesson has more than
  /// one file, because the playground holds one model.
  playground : String?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend LessonPage with Eq::{equal, not_equal}

///|
pub extend LessonPage with @debug.Debug::{to_repr}

///|
pub extend LessonPage with ToJson::{to_json}

///|
pub extend LessonPage with FromJson::{from_json}

///|
/// The contents: the sections in order, each with its lessons in order.
pub(all) struct TourContents {
  sections : Array[(String, Array[LessonLink])]
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend TourContents with Eq::{equal, not_equal}

///|
pub extend TourContents with @debug.Debug::{to_repr}

///|
pub extend TourContents with ToJson::{to_json}

///|
pub extend TourContents with FromJson::{from_json}

///|
/// The data of a tour page: the contents, or one lesson.
pub(all) enum TourPage {
  Contents(TourContents)
  Page(LessonPage)
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend TourPage with Eq::{equal, not_equal}

///|
pub extend TourPage with @debug.Debug::{to_repr}

///|
pub extend TourPage with ToJson::{to_json}

///|
pub extend TourPage with FromJson::{from_json}
