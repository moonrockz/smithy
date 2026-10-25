///|
fn service_config(
  shape : @smithy.Shape,
  config : @validation.Config,
) -> @validation.Config raise PreparationError {
  match shape.trait_value("smithy.rpc#unknownMembers") {
    None => config
    Some(String("ignore")) => config.with_unknown_members(@validation.Ignore)
    Some(String("reject")) => config.with_unknown_members(@validation.Reject)
    _ =>
      raise InvalidContract(
        shape.id,
        "I expected unknownMembers to be reject or ignore on the service.",
      )
  }
}
