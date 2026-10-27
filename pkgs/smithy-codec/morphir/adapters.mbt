// The Morphir scalar adapters. A host registers them explicitly with `registry()`; general codecs never import
// this package. Each adapter charges work in proportion to the size of the value it reads or writes and fails
// with a message and a relative path instead of producing a partial value.

///|
pub let v3_name_id : String = "morphir.v3.name"

///|
pub let v3_path_id : String = "morphir.v3.path"

///|
pub let v3_fqname_id : String = "morphir.v3.fqname"

///|
pub let v4_name_id : String = "morphir.v4.name"

///|
pub let v4_path_id : String = "morphir.v4.path"

///|
pub let v4_fqname_id : String = "morphir.v4.fqname"

///|
pub let format_version_id : String = "morphir.format-version"

///|
/// Guard adapter: a JSON number whose token is a plain integer (`42`, `-7`, no point or exponent).
pub let v4_integer_token_id : String = "morphir.v4.integer-token"

///|
/// Guard adapter: a JSON number whose token has a fraction or an exponent (`4.0`, `1e3`). Decision D18 of the
/// wire reference: an exponent makes a bare number a FloatLiteral.
pub let v4_float_token_id : String = "morphir.v4.float-token"

///|
/// The support table of the Morphir bundles in examples/morphir-codecs, in the canonical interval notation of
/// the format-version contract.
pub let support_table : String = "[3.0.0,3.2.0),[4.0.0,4.1.0)"

///|
fn failure(error : NameError) -> @codec.AdapterFailure {
  let mut path = @validation.InstancePath::root()
  for i in error.at {
    path = path.index(i) catch { _ => path }
  }
  @codec.AdapterFailure::new(error.message, path~)
}

///|
fn exhausted() -> @codec.AdapterFailure {
  @codec.AdapterFailure::new("I have no work left for this value.")
}

///|
/// The number of JSON nodes and string units in `value`, the basis of an adapter's work charge.
fn json_size(value : Json) -> Int32 {
  let stack = [value]
  let mut size = 0
  while stack.pop() is Some(v) {
    size += 1
    match v {
      String(s) => size += s.length() / 16
      Array(items) =>
        for item in items {
          stack.push(item)
        }
      Object(fields) =>
        for _, item in fields {
          stack.push(item)
        }
      _ => ()
    }
  }
  size
}

///|
fn text_reader(
  read : (Json) -> Result[String, NameError],
) -> (Json, @codec.AdapterContext) -> Result[
  @codec.ScalarValue,
  @codec.AdapterFailure,
] {
  fn(value, context) {
    if !context.charge(json_size(value)) {
      return Err(exhausted())
    }
    match read(value) {
      Ok(text) => Ok(Text(text))
      Err(e) => Err(failure(e))
    }
  }
}

///|
fn text_writer(
  write : (String) -> Result[Json, NameError],
) -> (@codec.ScalarValue, @codec.AdapterContext) -> Result[
  Json,
  @codec.AdapterFailure,
] {
  fn(value, context) {
    guard value is Text(text) else {
      return Err(@codec.AdapterFailure::new("I expected a text value."))
    }
    if !context.charge(1 + text.length() / 16) {
      return Err(exhausted())
    }
    match write(text) {
      Ok(json) => Ok(json)
      Err(e) => Err(failure(e))
    }
  }
}

///|
fn adapter_id(text : String) -> @contract.AdapterId {
  @contract.AdapterId::parse(text) catch {
    _ => abort("invalid built-in adapter identifier " + text)
  }
}

///|
fn number_token(value : Json) -> String? {
  match value {
    Number(_, repr=Some(text)) => Some(text)
    Number(_, repr=None) => @codec.json_number(value).map(n => n.to_string())
    _ => None
  }
}

///|
fn integer_token(token : String) -> Bool {
  let digits = if token.has_prefix("-") { token[1:].to_owned() } else { token }
  plain_digits(digits)
}

///|
fn token_guard(
  id : String,
  accept : (String) -> Bool,
  what : String,
) -> @codec.ScalarAdapter raise @contract.IdentityError {
  @codec.ScalarAdapter::new(
    adapter_id(id),
    inputs=[NumberKind],
    output=NumberKind,
    read=fn(value, context) {
      if !context.charge(1) {
        return Err(exhausted())
      }
      match (number_token(value), @codec.json_number(value)) {
        (Some(token), Some(n)) if accept(token) => Ok(Numeric(n))
        _ => Err(@codec.AdapterFailure::new("I expected \{what}."))
      }
    },
    write=fn(value, context) {
      if !context.charge(1) {
        return Err(exhausted())
      }
      match value {
        Numeric(n) if accept(n.to_string()) => Ok(@codec.number_json(n))
        _ =>
          Err(
            @codec.AdapterFailure::new("I cannot write this value as \{what}."),
          )
      }
    },
  )
}

///|
/// Every Morphir adapter, in identifier order.
pub fn adapters() -> Array[@codec.ScalarAdapter] {
  [
    @codec.ScalarAdapter::new(
      adapter_id(format_version_id),
      inputs=[NumberKind, StringKind],
      output=StringKind,
      read=fn(value, context) {
        if !context.charge(json_size(value)) {
          return Err(exhausted())
        }
        match format_version_read(value) {
          Ok(text) => Ok(Text(text))
          Err(message) => Err(@codec.AdapterFailure::new(message))
        }
      },
      write=fn(value, context) {
        if !context.charge(1) {
          return Err(exhausted())
        }
        match value {
          Text(text) =>
            match format_version_json(text) {
              Ok(json) => Ok(json)
              Err(message) => Err(@codec.AdapterFailure::new(message))
            }
          _ => Err(@codec.AdapterFailure::new("I expected a release text."))
        }
      },
    ),
    @codec.ScalarAdapter::new(
      adapter_id(v3_fqname_id),
      inputs=[ArrayKind],
      output=StringKind,
      read=text_reader(v3_fqname_read),
      write=text_writer(v3_fqname_json),
    ),
    @codec.ScalarAdapter::new(
      adapter_id(v3_name_id),
      inputs=[ArrayKind],
      output=StringKind,
      read=text_reader(fn(v) { v3_name_read(v, []) }),
      write=text_writer(v3_name_json),
      compare=Some(v3_name_compare),
    ),
    @codec.ScalarAdapter::new(
      adapter_id(v3_path_id),
      inputs=[ArrayKind],
      output=StringKind,
      read=text_reader(fn(v) { v3_path_read(v, []) }),
      write=text_writer(v3_path_json),
      compare=Some(v3_path_compare),
    ),
    @codec.ScalarAdapter::new(
      adapter_id(v4_fqname_id),
      inputs=[StringKind, ArrayKind],
      output=StringKind,
      read=text_reader(v4_fqname_read),
      write=text_writer(fn(text) { Ok(Json::string(text)) }),
    ),
    token_guard(
      v4_float_token_id,
      token => !integer_token(token),
      "a number with a fraction or an exponent",
    ),
    token_guard(v4_integer_token_id, integer_token, "an integer number token"),
    @codec.ScalarAdapter::new(
      adapter_id(v4_name_id),
      inputs=[StringKind, ArrayKind],
      output=StringKind,
      read=text_reader(fn(v) { v4_name_read(v, []) }),
      write=text_writer(fn(text) { Ok(Json::string(text)) }),
    ),
    @codec.ScalarAdapter::new(
      adapter_id(v4_path_id),
      inputs=[StringKind, ArrayKind],
      output=StringKind,
      read=text_reader(fn(v) { v4_path_read(v, []) }),
      write=text_writer(fn(text) { Ok(Json::string(text)) }),
    ),
  ] catch {
    _ => abort("invalid built-in Morphir adapter signature")
  }
}

///|
/// A registry with every Morphir adapter. A host adds its own adapters with `AdapterRegistry::register`.
pub fn registry() -> @codec.AdapterRegistry {
  let mut registry = @codec.AdapterRegistry::new()
  for adapter in adapters() {
    registry = registry.register(adapter) catch {
      _ => abort("duplicate built-in Morphir adapter")
    }
  }
  registry
}
