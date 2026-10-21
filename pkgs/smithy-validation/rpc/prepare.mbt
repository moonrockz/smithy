///|
priv struct PreparedMethod {
  operation : @smithy.ShapeId
  input : @smithy.ShapeId
  positional : Array[@smithy.ShapeId]
  validator : @validation.PreparedValidator
  mode : ParameterMode
  order : Array[String]
  result : ResultSelection
  result_validator : @validation.PreparedValidator?
  errors : Array[PreparedError]
}

///|
priv struct PreparedError {
  shape : @smithy.ShapeId
  code : ErrorCode
  data_validator : @validation.PreparedValidator?
  data_target : @smithy.ShapeId
  data_required : Bool
}

///|
pub struct PreparedService {
  priv service : @smithy.ShapeId
  priv version : ProtocolVersion
  priv methods : Map[MethodName, PreparedMethod]
  priv document : @validation.PreparedValidator
  priv finding_limit : Int32
}

///|
fn fields(value : @smithy.NodeValue?) -> Map[String, @smithy.NodeValue] {
  match value {
    Some(Object(fields)) => fields
    _ => Map([])
  }
}

///|
fn text(value : @smithy.NodeValue?) -> String? {
  match value {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
fn invalid(
  id : @smithy.ShapeId,
  message : String,
) -> Unit raise PreparationError {
  raise InvalidContract(id, message)
}

///|
/// Snapshot a selected service. Parameter validators retain no mutable model state.
pub fn PreparedService::prepare(
  model : @smithy.Model,
  service : @smithy.ShapeId,
  version : ProtocolVersion,
  config~ : @validation.Config = @validation.Config::new(),
) -> PreparedService raise {
  guard model.shapes.get(service) is Some(root) && root.body is Service(..) else {
    raise InvalidContract(service, "I expected an existing service shape.")
  }
  let profile = fields(root.trait_value("smithy.rpc#jsonRpc"))
  guard profile.get("versions") is Some(Array(versions)) && !versions.is_empty() else {
    raise InvalidContract(
      service, "I expected jsonRpc with explicit supported versions.",
    )
  }
  let declared : Set[ProtocolVersion] = Set([])
  for value in versions {
    guard value is String(name) && ProtocolVersion::parse(name) is Some(v) else {
      raise InvalidContract(
        service, "I expected only JSON-RPC versions 1.0 and 2.0.",
      )
    }
    if declared.contains(v) {
      invalid(service, "I expected each protocol version once.")
    }
    declared.add(v)
  }
  if !declared.contains(version) {
    invalid(
      service, "I expected the selected protocol version to be declared by the service.",
    )
  }
  let service_errors = match root.body {
    Service(errors~, ..) => errors
    _ => []
  }
  let methods : Map[MethodName, PreparedMethod] = Map([])
  let pending = [service]
  let visited : Set[@smithy.ShapeId] = Set([])
  while pending.pop() is Some(id) {
    if visited.contains(id) {
      continue
    }
    if visited.length() >= config.limits.work {
      invalid(service, "I reached the service preparation work limit.")
    }
    visited.add(id)
    guard model.shapes.get(id) is Some(shape) else {
      raise InvalidContract(id, "I expected a reachable service shape.")
    }
    match shape.body {
      Service(operations~, resources~, ..) => {
        pending.append(operations)
        pending.append(resources)
      }
      Resource(
        create~,
        put~,
        read~,
        update~,
        delete~,
        list~,
        operations~,
        collectionOperations~,
        resources~,
        ..
      ) => {
        for target in [create, put, read, update, delete, list] {
          if target is Some(target) {
            pending.push(target)
          }
        }
        pending.append(operations)
        pending.append(collectionOperations)
        pending.append(resources)
      }
      Operation(input~, output~, errors~) => {
        let contract = fields(shape.trait_value("smithy.rpc#method"))
        guard text(contract.get("name")) is Some(raw_name) &&
          MethodName::parse(raw_name) is Some(name) else {
          raise InvalidContract(
            id, "I expected a nonempty method name outside the reserved rpc. namespace.",
          )
        }
        if methods.contains(name) {
          invalid(id, "I expected a unique wire method name.")
        }
        let mode = match text(contract.get("params")) {
          Some("named") => Named
          Some("positional") => Positional
          Some("either") => Either
          _ =>
            raise InvalidContract(
              id, "I expected named, positional or either parameter mode.",
            )
        }
        if declared.contains(V1_0) && mode == Named {
          invalid(
            id, "I expected positional support for a service declaring version 1.0.",
          )
        }
        guard model.shapes.get(input) is Some(input_shape) &&
          input_shape.body is Structure(members) else {
          raise InvalidContract(id, "I expected a structure input.")
        }
        let names : Map[String, String] = Map([])
        for member_id in members {
          guard model.shapes.get(member_id) is Some(member_) &&
            member_id.member_name() is Some(smithy_name) else {
            raise InvalidContract(id, "I expected declared input members.")
          }
          let wire_name = if config.member_names == @validation.JsonName {
            text(member_.trait_value("smithy.api#jsonName")).unwrap_or(
              smithy_name,
            )
          } else {
            smithy_name
          }
          names[smithy_name] = wire_name
        }
        let order = []
        let positional = []
        let seen : Set[String] = Set([])
        match contract.get("positional") {
          Some(Array(values)) =>
            for value in values {
              guard value is String(member_name) &&
                names.get(member_name) is Some(wire_name) &&
                !seen.contains(member_name) else {
                raise InvalidContract(
                  id, "I expected distinct declared input member names in positional order.",
                )
              }
              seen.add(member_name)
              order.push(wire_name)
              positional.push(input.with_member(member_name).unwrap())
            }
          None => ()
          _ => invalid(id, "I expected a positional member-name array.")
        }
        if mode != Named &&
          (
            contract.get("positional") is None ||
            order.length() != members.length()
          ) {
          invalid(
            id, "I expected an explicit complete positional member order.",
          )
        }
        if mode == Named && contract.contains("positional") {
          invalid(
            id, "I expected positional order only for a positional-capable method.",
          )
        }
        if contract.get("resultMember") is Some(value) && !(value is String(_)) {
          invalid(id, "I expected a string result member selector.")
        }
        let result = match
          (contract.get("nullResult"), text(contract.get("resultMember"))) {
          (Some(Boolean(true)), None) => NullResult
          (Some(Boolean(true)), Some(_)) =>
            raise InvalidContract(id, "I expected one result selector.")
          (None | Some(Boolean(false)), Some(member_name)) => {
            guard output.with_member(member_name) is Some(member_id) &&
              model.shapes.get(output) is Some(out) &&
              out.body is Structure(out_members) &&
              out_members.contains(member_id) else {
              raise InvalidContract(
                id, "I expected a declared output member for resultMember.",
              )
            }
            OutputMember(member_id)
          }
          (None | Some(Boolean(false)), None) => OutputStructure(output)
          _ =>
            raise InvalidContract(
              id, "I expected a boolean nullResult selector.",
            )
        }
        let result_validator = match result {
          OutputStructure(target) | OutputMember(target) =>
            Some(@validation.PreparedValidator::prepare(model, target, config~))
          NullResult => None
        }
        let prepared_errors : Array[PreparedError] = []
        let seen_errors : Set[@smithy.ShapeId] = Set([])
        for error_id in service_errors + errors {
          if seen_errors.contains(error_id) {
            continue
          }
          if seen_errors.length() >= config.limits.work {
            invalid(id, "I reached the error mapping preparation work limit.")
          }
          seen_errors.add(error_id)
          guard model.shapes.get(error_id) is Some(error_shape) &&
            error_shape.body is Structure(error_members) &&
            error_shape.trait_value("smithy.api#error") is Some(_) else {
            raise InvalidContract(
              error_id, "I expected a modeled error structure.",
            )
          }
          let mapping = fields(error_shape.trait_value("smithy.rpc#rpcError"))
          guard mapping.get("code") is Some(Number(number)) &&
            ErrorCode::from_number(number) is Some(code) else {
            raise InvalidContract(
              error_id, "I expected an integer rpcError application code.",
            )
          }
          if code.is_reserved() ||
            prepared_errors.iter().any(e => e.code == code) {
            invalid(
              error_id, "I expected a unique nonreserved application error code within the operation.",
            )
          }
          let data_target = match
            (mapping.get("absentData"), mapping.get("dataMember")) {
            (Some(Boolean(true)), None) => None
            (Some(Boolean(true)), Some(_)) =>
              raise InvalidContract(
                error_id, "I expected one error data selector.",
              )
            (None | Some(Boolean(false)), Some(String(name))) => {
              guard error_id.with_member(name) is Some(member_id) &&
                error_members.contains(member_id) else {
                raise InvalidContract(
                  error_id, "I expected a declared error data member.",
                )
              }
              Some(member_id)
            }
            (None | Some(Boolean(false)), None) => Some(error_id)
            _ =>
              raise InvalidContract(
                error_id, "I expected valid error data selectors.",
              )
          }
          let data_required = match data_target {
            Some(target) if target.member_name() is Some(_) =>
              model.shapes
              .get(target)
              .map(s => s.trait_value("smithy.api#required") is Some(_))
              .unwrap_or(false)
            Some(_) => true
            None => false
          }
          prepared_errors.push({
            shape: error_id,
            code,
            data_target: data_target.unwrap_or(error_id),
            data_required,
            data_validator: match data_target {
              Some(target) =>
                Some(
                  @validation.PreparedValidator::prepare(model, target, config~),
                )
              None => None
            },
          })
        }
        methods[name] = {
          operation: id,
          input,
          positional,
          validator: @validation.PreparedValidator::prepare(
            model,
            input,
            config~,
          ),
          mode,
          order,
          result,
          result_validator,
          errors: prepared_errors,
        }
      }
      _ =>
        invalid(
          id, "I expected a service, resource or operation in the service closure.",
        )
    }
  }
  {
    service,
    version,
    methods,
    finding_limit: config.limits.findings,
    document: @validation.PreparedValidator::prepare(
      model,
      @smithy.ShapeId::parse("smithy.api#Document").unwrap(),
      config~,
    ),
  }
}

///|
pub fn PreparedService::operation(
  self : PreparedService,
  name : MethodName,
) -> @smithy.ShapeId? {
  self.methods.get(name).map(method_ => method_.operation)
}

///|
pub fn PreparedService::result_selection(
  self : PreparedService,
  name : MethodName,
) -> ResultSelection? {
  self.methods.get(name).map(method_ => method_.result)
}
