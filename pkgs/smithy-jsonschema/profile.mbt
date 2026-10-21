///|
/// Private operation settings keep the public Config record source-compatible.
priv struct ConversionConfig {
  settings : Config
  value_contracts : Bool
}

///|
fn validate_value_config(
  config : ConversionConfig,
) -> Unit raise JsonSchemaError {
  if config.value_contracts && config.settings.union_strategy != "oneOf" {
    raise InvalidConfiguration(
      "Value schemas require union_strategy=oneOf to retain union member contracts",
    )
  }
}
