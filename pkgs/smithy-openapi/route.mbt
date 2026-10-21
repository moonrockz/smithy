///|
priv enum HttpMethod {
  Get
  Put
  Post
  Delete
  Options
  Head
  Patch
  Trace
}

///|
fn HttpMethod::parse(text : String) -> HttpMethod? {
  match text.to_lower() {
    "get" => Some(Get)
    "put" => Some(Put)
    "post" => Some(Post)
    "delete" => Some(Delete)
    "options" => Some(Options)
    "head" => Some(Head)
    "patch" => Some(Patch)
    "trace" => Some(Trace)
    _ => None
  }
}

///|
fn HttpMethod::key(self : HttpMethod) -> String {
  match self {
    Get => "get"
    Put => "put"
    Post => "post"
    Delete => "delete"
    Options => "options"
    Head => "head"
    Patch => "patch"
    Trace => "trace"
  }
}

///|
priv struct UriLabel {
  name : String
  greedy : Bool
}

///|
priv enum UriSegment {
  Literal(String)
  Label(UriLabel)
}

///|
priv struct UriTemplate {
  segments : Array[UriSegment]
}

///|
fn UriTemplate::parse(text : String) -> UriTemplate? {
  guard text.has_prefix("/") else { return None }
  let segments : Array[UriSegment] = []
  for component in text.split("/") {
    if component.has_prefix("{") && component.has_suffix("}") {
      let label = component[1:component.length() - 1].to_owned()
      let greedy = label.has_suffix("+")
      let name = if greedy {
        label[:label.length() - 1].to_owned()
      } else {
        label
      }
      guard @smithy.ShapeId::parse("smithy.openapi.internal#Uri")
        .unwrap()
        .with_member(name)
        is Some(_) else {
        return None
      }
      segments.push(Label({ name, greedy, }))
    } else {
      guard !component.contains("{") && !component.contains("}") else {
        return None
      }
      segments.push(Literal(component.to_owned()))
    }
  }
  Some({ segments, })
}

///|
fn UriTemplate::path(self : UriTemplate) -> String {
  self.segments
  .map(segment => {
    match segment {
      Literal(text) => text
      Label(label) =>
        "{" + label.name + (if label.greedy { "+" } else { "" }) + "}"
    }
  })
  .join("/")
}

///|
fn UriTemplate::label(self : UriTemplate, name : String) -> UriLabel? {
  for segment in self.segments {
    if segment is Label(label) && label.name == name {
      return Some(label)
    }
  }
  None
}

///|
fn UriTemplate::has_greedy_label(self : UriTemplate) -> Bool {
  self.segments.any(segment => {
    match segment {
      Label(label) => label.greedy
      Literal(_) => false
    }
  })
}
