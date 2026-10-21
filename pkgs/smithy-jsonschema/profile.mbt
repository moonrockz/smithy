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
  if config.value_contracts && config.settings.support_non_numeric_floats {
    raise InvalidConfiguration(
      "Value schemas require support_non_numeric_floats=false; nonnumeric alternatives cannot retain numeric bounds",
    )
  }
  if config.value_contracts && config.settings.map_strategy != "propertyNames" {
    raise InvalidConfiguration(
      "Value schemas require map_strategy=propertyNames to retain map key and sparse value contracts",
    )
  }
  if config.value_contracts && config.settings.union_strategy != "oneOf" {
    raise InvalidConfiguration(
      "Value schemas require union_strategy=oneOf to retain union member contracts",
    )
  }
}
