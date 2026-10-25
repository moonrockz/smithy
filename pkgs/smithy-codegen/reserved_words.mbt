///|
/// A set of words that a target language reserves, with the way to escape them.
pub struct ReservedWords {
  words : Set[String]
  case_sensitive : Bool
  escape_with : (String) -> String
}

///|
pub fn ReservedWords::new(
  words : Array[String],
  case_sensitive~ : Bool = true,
  escape~ : (String) -> String = w => w + "_",
) -> ReservedWords {
  let set : Set[String] = Set([])
  for word in words {
    set.add(if case_sensitive { word } else { word.to_lower() })
  }
  { words: set, case_sensitive, escape_with: escape, }
}

///|
pub fn ReservedWords::is_reserved(self : ReservedWords, word : String) -> Bool {
  self.words.contains(if self.case_sensitive { word } else { word.to_lower() })
}

///|
/// The escaped word, or the word itself when it is not reserved.
pub fn ReservedWords::escape(self : ReservedWords, word : String) -> String {
  if self.is_reserved(word) {
    (self.escape_with)(word)
  } else {
    word
  }
}
