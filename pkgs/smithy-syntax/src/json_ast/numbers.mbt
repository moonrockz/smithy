///|
priv enum ValueFrame {
  Object(Map[String, Json], mut key~ : String?)
  Array(Array[Json])
}

///|
/// Core JSON validates the grammar, Unicode and nesting first. This second,
/// iterative token pass rebuilds values with every number's original spelling.
/// Core currently retains large integers but rounds ordinary decimal tokens.
/// Rebuilding containers also preserves last-key-wins behavior for duplicate
/// keys, including duplicates whose earlier values have different structures.
fn parse_exact(text : String) -> Json raise @json.ParseError {
  @json.parse(text) |> ignore
  let stack : Array[ValueFrame] = []
  let mut root = Json::null()
  fn attach(value : Json) -> Unit {
    match stack.last() {
      Some(Object(fields, key~)) => if key is Some(key) { fields[key] = value }
      Some(Array(values)) => values.push(value)
      None => root = value
    }
    if stack.last() is Some(Object(_, ..) as frame) {
      frame.key = None
    }
  }
  let mut at = 0
  while at < text.length() {
    let start = at
    match text.code_unit_at(at).to_int().unsafe_to_char() {
      '{' => {
        let fields : Map[String, Json] = Map([])
        attach(Json::object(fields))
        stack.push(Object(fields, key=None))
        at += 1
      }
      '[' => {
        let values : Array[Json] = []
        attach(Json::array(values))
        stack.push(Array(values))
        at += 1
      }
      '}' | ']' => {
        stack.pop() |> ignore
        at += 1
      }
      '"' => {
        at += 1
        while at < text.length() {
          let c = text.code_unit_at(at).to_int().unsafe_to_char()
          at += 1
          if c == '"' {
            break
          }
          if c == '\\' {
            at += 1
          }
        }
        let value = @json.parse(text.unsafe_substring(start~, end=at))
        match (stack.last(), value) {
          (Some(Object(_, key=None) as frame), String(key)) =>
            frame.key = Some(key)
          _ => attach(value)
        }
      }
      '-' | '0'..<='9' => {
        at += 1
        while at < text.length() {
          let c = text.code_unit_at(at).to_int().unsafe_to_char()
          if (c >= '0' && c <= '9') ||
            c == '.' ||
            c == 'e' ||
            c == 'E' ||
            c == '-' ||
            c == '+' {
            at += 1
          } else {
            break
          }
        }
        let repr = text.unsafe_substring(start~, end=at)
        // The whole document is valid, so this token is necessarily a number.
        if @json.parse(repr) is Number(number, ..) {
          attach(Json::number(number, repr~))
        }
      }
      't' => {
        attach(Json::boolean(true))
        at += 4
      }
      'f' => {
        attach(Json::boolean(false))
        at += 5
      }
      'n' => {
        attach(Json::null())
        at += 4
      }
      _ => at += 1 // Validated whitespace, colon or comma.
    }
  }
  root
}
