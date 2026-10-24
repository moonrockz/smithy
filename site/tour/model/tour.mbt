///|
/// One file of a lesson: the editor tab name and the text.
pub(all) struct LessonFile {
  name : String
  text : String
}

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
