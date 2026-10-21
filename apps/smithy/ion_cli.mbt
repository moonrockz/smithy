///|
priv suberror IonInputError {
  IonInputError(String, String, Int32?)
} derive(Debug)

///|
fn parse_ion_input(
  bytes : Bytes,
  format : ValueInputFormat,
  index : Int32?,
) -> @ion.Ion raise IonInputError {
  if bytes.length() > 16 * 1024 * 1024 {
    raise IonInputError(
      "IonInputLimit",
      "I expected an Ion input of at most 16 MiB.",
      None,
    )
  }
  let values = try {
    let fuel = @ion.Limited(@ion.Budget(128))
    match format {
      IonTextInput =>
        @ion_text.read_ion_datagram(@ion_text.decode_ion_text(bytes), fuel~)
      IonBinaryInput => @ion_binary.read_binary(bytes, fuel~)
      JsonInput =>
        raise @ion.Unsupported("I expected an explicit Ion input format.")
    }
  } catch {
    @ion.FuelExhausted(location~, ..) as error => {
      let offset = match location {
        TextOffset(n) | BinaryOffset(n) | CharacterOffset(n) => Some(n)
        _ => None
      }
      raise IonInputError("IonInputLimit", error.message(), offset)
    }
    error => raise IonInputError("InvalidIon", error.message(), None)
  }
  match index {
    Some(index) => {
      guard index >= 0 && values.get(index) is Some(value) else {
        raise IonInputError(
          "IonSelection",
          "I expected --ion-index to select an existing user value in the Ion datagram.",
          None,
        )
      }
      value
    }
    None => {
      guard values is [value] else {
        raise IonInputError(
          "IonSelection",
          "I expected exactly one Ion user value; use --ion-index to select from a datagram.",
          None,
        )
      }
      value
    }
  }
}

///|
fn run_ion_validation(opts : ValueOptions, model : @smithy.Model) -> Int32 {
  let prepared = @ion_validation.PreparedValidator::prepare(
    model,
    opts.target,
    config=opts.config,
  ) catch {
    @validation.InvalidTarget(id, message) =>
      return value_problem(
        opts,
        "InvalidTarget",
        id.to_string() + ": " + message,
        2,
        source=Some("--shape"),
      )
    @validation.InvalidConfiguration(message) =>
      return value_problem(opts, "InvalidConfiguration", message, 2)
    @validation.InvalidModel(id, message) =>
      return value_problem(
        opts,
        "InvalidModel",
        id.to_string() + ": " + message,
        1,
        source=model.shapes.get(id).map(s => s.source.file),
      )
    @validation.UnsupportedConstraint(id, message) =>
      return value_problem(
        opts,
        "UnsupportedConstraint",
        id.to_string() + ": " + message,
        2,
        source=model.shapes.get(id).map(s => s.source.file),
      )
  }
  let bytes = read_ion_bytes(opts.file) catch {
    IonInputError(code, message, offset) =>
      return value_problem(opts, code, message, 1, offset~)
    _ =>
      return value_problem(
        opts, "InputRead", "I could not read the Ion value input.", 1,
      )
  }
  let value = parse_ion_input(bytes, opts.input_format, opts.ion_index) catch {
    IonInputError(code, message, offset) =>
      return value_problem(opts, code, message, 1, offset~)
  }
  let result = prepared.validate(value)
  if opts.diagnostics == JsonFindings {
    println(@json.to_json(result).stringify())
  } else {
    for finding in result.findings {
      eprintln(
        "\{opts.file}\{finding.path.pointer()}: error[\{finding.code.to_string()}] \{finding.shape}: \{finding.message}",
      )
    }
  }
  if result.is_valid() {
    0
  } else {
    1
  }
}
