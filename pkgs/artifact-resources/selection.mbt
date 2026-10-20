///|
pub(all) enum ResourceRoot {
  ContainerRoot
  Subtree(EntryPath)
} derive(Eq, Debug)

///|
pub fn ResourceRoot::parse(text : String) -> ResourceRoot? {
  if text == "." {
    Some(ContainerRoot)
  } else {
    EntryPath::parse(text).map(path => Subtree(path))
  }
}

///|
pub fn ResourceRoot::to_string(self : ResourceRoot) -> String {
  match self {
    ContainerRoot => "."
    Subtree(path) => path.to_string()
  }
}

///|
priv enum GlobToken {
  Literal(Char)
  Star
  Any
} derive(Eq, Debug)

///|
priv enum GlobPart {
  Recursive
  Component(Array[GlobToken])
} derive(Eq, Debug)

///|
pub struct GlobPattern {
  priv text : String
  priv parts : Array[GlobPart]
} derive(Eq, Debug)

///|
/// *, ? and whole-component **. No escaping, classes or brace expansion.
pub fn GlobPattern::parse(text : String) -> GlobPattern? {
  if text.is_empty() ||
    text.length() > 1024 ||
    text.contains("[") ||
    text.contains("]") ||
    text.contains("{") ||
    text.contains("}") {
    return None
  }
  let literal = text.replace_all(old="*", new="x").replace_all(old="?", new="x")
  if !valid_path(literal) {
    return None
  }
  let parts = []
  for part in text.split("/") {
    if part == "**" {
      parts.push(Recursive)
    } else {
      if part.contains("**") {
        return None
      }
      let tokens = part
        .iter()
        .map(c => {
          if c == '*' {
            Star
          } else if c == '?' {
            Any
          } else {
            Literal(c)
          }
        })
        .to_array()
      parts.push(Component(tokens))
    }
  }
  Some({ text, parts, })
}

///|
pub fn GlobPattern::to_string(self : GlobPattern) -> String {
  self.text
}

///|
fn component_matches(tokens : Array[GlobToken], text : String) -> Bool {
  let chars = text.iter().to_array()
  let mut previous = Array::make(chars.length() + 1, false)
  previous[0] = true
  for token in tokens {
    let next = Array::make(chars.length() + 1, false)
    if token is Star {
      next[0] = previous[0]
    }
    for j in 1..<(chars.length() + 1) {
      next[j] = match token {
        Star => previous[j] || next[j - 1]
        Any => previous[j - 1]
        Literal(c) => previous[j - 1] && chars[j - 1] == c
      }
    }
    previous = next
  }
  previous[chars.length()]
}

///|
pub fn GlobPattern::matches(self : GlobPattern, path : EntryPath) -> Bool {
  let components = path.to_string().split("/").map(p => p.to_owned()).to_array()
  let mut previous = Array::make(components.length() + 1, false)
  previous[0] = true
  for part in self.parts {
    let next = Array::make(components.length() + 1, false)
    if part is Recursive {
      next[0] = previous[0]
    }
    for j in 1..<(components.length() + 1) {
      next[j] = match part {
        Recursive => previous[j] || next[j - 1]
        Component(tokens) =>
          previous[j - 1] && component_matches(tokens, components[j - 1])
      }
    }
    previous = next
  }
  previous[components.length()]
}

///|
pub(all) enum ResourceSelector {
  Exact(EntryPath)
  Named(EntryPath, ResourceName)
  Matching(GlobPattern)
} derive(Eq, Debug)

///|
pub struct Selection {
  root : ResourceRoot
  priv terms : Array[ResourceSelector]
} derive(Eq, Debug)

///|
pub fn Selection::new(
  root : ResourceRoot,
  selectors : Array[ResourceSelector],
) -> Selection? {
  if selectors.is_empty() || selectors.length() > 256 {
    None
  } else {
    Some({ root, terms: selectors.copy(), })
  }
}

///|
pub fn Selection::selectors(self : Selection) -> Array[ResourceSelector] {
  self.terms.copy()
}

///|
/// Match without reading content, then sort declarations by logical name.
/// Identical logical/physical pairs deduplicate; conflicting names fail.
pub fn EntryTree::select(
  self : EntryTree,
  selection : Selection,
) -> Array[Declaration] raise ResourceError {
  let candidates : Map[EntryPath, EntryPath] = Map([])
  for physical in self.paths {
    let relative = match selection.root {
      ContainerRoot => Some(physical)
      Subtree(root) => physical.relative_to(root)
    }
    if relative is Some(relative) {
      candidates[relative] = physical
    }
  }
  if selection.root is Subtree(root) &&
    candidates.is_empty() &&
    !self.members.iter().any(path => path.has_prefix(root.to_string() + "/")) {
    raise ResourceError(
      MissingRoot,
      self.provenance,
      "Missing resource root `" + root.to_string() + "`",
    )
  }
  let selected : Map[ResourceName, EntryPath] = Map([])
  let relative_paths = candidates.keys().to_array()
  relative_paths.sort()
  let mut work = self.limits.max_match_steps
  for selector in selection.terms {
    let matches : Array[Declaration] = []
    match selector {
      Exact(path) | Named(path, _) =>
        if candidates.get(path) is Some(physical) {
          let name = match selector {
            Named(_, alias_) => alias_
            _ => path.resource_name()
          }
          matches.push({ name, path: physical, })
        }
      Matching(pattern) =>
        for path in relative_paths {
          let width = path.to_string().length()
          if width > 0 && pattern.text.length() > work / width {
            raise ResourceError(
              ResourceLimit,
              self.provenance,
              "Resource glob matching exceeds work limit",
            )
          }
          work -= width * pattern.text.length()
          if pattern.matches(path) {
            matches.push({ name: path.resource_name(), path: candidates[path], })
          }
        }
    }
    if matches.is_empty() {
      let expression = match selector {
        Exact(path) | Named(path, _) => path.to_string()
        Matching(pattern) => pattern.to_string()
      }
      raise ResourceError(
        MissingSelection,
        self.provenance,
        "Resource selector `" +
        expression +
        "` matched no files under `" +
        selection.root.to_string() +
        "`",
      )
    }
    for declaration in matches {
      if selected.get(declaration.name) is Some(existing) &&
        existing != declaration.path {
        raise ResourceError(
          DuplicateResource,
          self.provenance,
          "Logical resource `" +
          declaration.name.to_string() +
          "` selects both `" +
          existing.to_string() +
          "` and `" +
          declaration.path.to_string() +
          "`",
        )
      }
      selected[declaration.name] = declaration.path
    }
  }
  let declarations = selected
    .iter()
    .map(pair => { name: pair.0, path: pair.1, })
    .to_array()
  declarations.sort_by((a, b) => Compare::compare(a.name, b.name))
  declarations
}

///|
pub fn select_resources(
  tree : EntryTree,
  selection : Selection,
) -> Array[Resource] raise ResourceError {
  load_resources(tree, tree.select(selection))
}
