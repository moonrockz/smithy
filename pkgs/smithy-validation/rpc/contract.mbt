///|
/// A detached description of one validated application-error mapping.
pub(all) struct ErrorContract {
  shape : @smithy.ShapeId
  code : ErrorCode
  data : @smithy.ShapeId?
  data_required : Bool
} derive(Eq, Debug)

///|
/// A detached method mapping shared by validators and description exporters.
/// Positional entries are semantic member IDs, independent of wire naming.
pub(all) struct MethodContract {
  name : MethodName
  operation : @smithy.ShapeId
  input : @smithy.ShapeId
  mode : ParameterMode
  positional : Array[@smithy.ShapeId]
  result : ResultSelection
  errors : Array[ErrorContract]
} derive(Eq, Debug)

///|
/// Return contracts sorted by wire method name. Arrays are detached from the
/// prepared validators so callers cannot mutate subsequent validation behavior.
pub fn PreparedService::contracts(
  self : PreparedService,
) -> Array[MethodContract] {
  let names = self.methods.keys().to_array()
  names.sort_by((a, b) => a.to_string().lexical_compare(b.to_string()))
  names.map(name => {
    let method_ = self.methods[name]
    let errors = method_.errors.map(error => {
      shape: error.shape,
      code: error.code,
      data: if error.data_validator is Some(_) {
        Some(error.data_target)
      } else {
        None
      },
      data_required: error.data_required,
    })
    errors.sort_by((a, b) => {
      a.code.to_string().lexical_compare(b.code.to_string())
    })
    {
      name,
      operation: method_.operation,
      input: method_.input,
      mode: method_.mode,
      positional: method_.positional.copy(),
      result: method_.result,
      errors,
    }
  })
}
