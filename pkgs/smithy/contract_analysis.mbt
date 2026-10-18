///|
priv struct ContractAnalysis {
  assembly : Assembly
  model : Model
  owner : Shape
  condition : String
  expression : String
  reported : Set[String]
}

///|
fn ContractAnalysis::problem(
  self : ContractAnalysis,
  span : @jmespath.Span,
  message : String,
  code~ : String = "SM-MODEL-016",
  severity~ : @syntax.Severity = Error,
) -> Unit {
  let key = "\{code}:\{span.start}:\{span.end}:\{message}"
  if self.reported.contains(key) {
    return
  }
  self.reported.add(key)
  let location : @jmespath.Diagnostic = { code: Syntax, message, span, }
  let (line, column) = location.line_column(self.expression)
  self.assembly.diagnostics.push({
    code,
    severity,
    message: "I found a problem in JMESPath condition \{Json::string(self.condition).stringify()} on \{self.owner.id} at expression \{line}:\{column} (UTF-16 offsets \{span.start}..\{span.end}): \{message}",
    source: {
      ..self.owner.source,
      path: self.owner.source.path +
      "/traits/smithy.contracts#conditions/" +
      pointer(self.condition) +
      "/expression",
    },
    shape: Some(self.owner.id),
  })
}

///|
fn ContractAnalysis::elements(
  self : ContractAnalysis,
  type_ : ContractType,
  node : @jmespath.Node,
  object~ : Bool = false,
) -> Array[ContractType] {
  match type_.resolve(self.model) {
    Unknown => [Unknown]
    Array(types, ..) if !object => types
    Object(fields, additional~, ..) if object => {
      let types = fields.values().to_array()
      if additional is Some(type_) {
        types.push(type_)
      }
      types
    }
    found => {
      self.problem(
        node.span,
        "I expected \{if object { "an object" } else { "an array" }} for this JMESPath operation, but found \{found.name(self.model)}.",
      )
      [Unknown]
    }
  }
}

///|
priv enum ContractTask {
  Analyze(@jmespath.Node, ContractType)
  Then(@jmespath.Node)
  Finish(@jmespath.Node, Int32, ContractType)
  Project(@jmespath.Node)
  ProjectionResult(Bool)
  CallbackResult(@jmespath.Node, String, ContractType)
}

///|
fn ContractAnalysis::function_result(
  self : ContractAnalysis,
  node : @jmespath.Node,
  name : String,
  args : Array[ContractType],
) -> ContractType {
  guard contract_signature(name) is Some(signature) else {
    self.problem(node.span, "I could not resolve JMESPath function \{name}.")
    return Unknown
  }
  let variadic = name == "merge" || name == "not_null"
  if args.length() < signature.length() ||
    (!variadic && args.length() != signature.length()) {
    self.problem(
      node.span,
      "I expected \{if variadic { "at least " } else { "" }}\{signature.length()} arguments for JMESPath function \{name}, but found \{args.length()}.",
    )
    return Unknown
  }
  guard node.kind is Function(_, nodes) else { return Unknown }
  for i, arg in args {
    let expected = signature[if variadic { 0 } else { i }]
    if !expected.accepts(arg, self.model) {
      self.problem(
        nodes[i].span,
        "I expected \{expected.description()} for argument \{i + 1} of JMESPath function \{name}, but found \{arg.name(self.model)}.",
      )
    }
  }
  let first = args[0].resolve(self.model)
  if name == "contains" && first is String && !Text.accepts(args[1], self.model) {
    self.problem(
      nodes[1].span,
      "I expected a string search value for JMESPath function contains, but found \{args[1].name(self.model)}.",
    )
  }
  match name {
    "contains" | "starts_with" | "ends_with" => Boolean
    "abs" | "ceil" | "floor" | "length" | "sum" | "to_number" => Number
    "avg" =>
      match first {
        Array(types, ..) if types.is_empty() => Null
        _ => Number
      }
    "join" | "to_string" | "type" => String
    "reverse" =>
      match first {
        Array(types, exact~) => Array(types.rev(), exact~)
        _ => first
      }
    "sort" | "sort_by" =>
      match first {
        Array(types, ..) => Array(types, exact=false)
        _ => first
      }
    "max" | "min" | "max_by" | "min_by" =>
      match first {
        Array(types, ..) =>
          if types.is_empty() {
            Null
          } else {
            contract_join(types, self.model)
          }
        _ => Unknown
      }
    "keys" => Array([String], exact=false)
    "values" => Array(self.elements(first, node, object=true), exact=false)
    "to_array" =>
      match first {
        Array(_, ..) => first
        Unknown => Array([Unknown], exact=false)
        _ => Array([first], exact=true)
      }
    "not_null" => {
      let types = args.filter(t => !(t.resolve(self.model) is Null))
      if types.is_empty() {
        Null
      } else if types[0].resolve(self.model) is Unknown {
        contract_join(types, self.model)
      } else {
        types[0]
      }
    }
    "merge" => {
      let fields : Map[String, ContractType] = Map([])
      let mut additional : ContractType? = None
      let mut truth : Bool? = Some(false)
      for arg in args {
        let arg_truth = arg.truth(self.model)
        if arg_truth == Some(true) {
          truth = Some(true)
        } else if arg_truth is None && truth != Some(true) {
          truth = None
        }
        match arg.resolve(self.model) {
          Object(entries, additional=rest, ..) => {
            if rest is Some(type_) {
              for key, old in fields {
                fields[key] = contract_join([old, type_], self.model)
              }
              additional = Some(
                match additional {
                  Some(old) => contract_join([old, type_], self.model)
                  None => type_
                },
              )
            }
            for key, value in entries {
              fields[key] = value
            }
          }
          Unknown => {
            fields.clear()
            additional = Some(Unknown)
          }
          _ => ()
        }
      }
      Object(fields, additional~, truth~)
    }
    "map" => Array([Unknown], exact=false)
    _ => Unknown
  }
}

///|
/// Interpret types with an explicit continuation stack. Both logical branches
/// and every function argument are checked, even if runtime data could skip them.
fn ContractAnalysis::analyze(
  self : ContractAnalysis,
  root : @jmespath.Node,
) -> ContractType {
  let tasks = [ContractTask::Analyze(root, Modeled(self.owner.id))]
  let values : Array[ContractType] = []
  while tasks.pop() is Some(task) {
    match task {
      Analyze(node, input) =>
        match node.kind {
          Identity => values.push(input)
          Literal(value) => values.push(Constant(value))
          Field(name) => {
            let type_ = match input.resolve(self.model) {
              Object(fields, additional~, ..) =>
                match fields.get(name) {
                  Some(type_) => type_
                  None =>
                    match additional {
                      Some(type_) => type_
                      None => {
                        self.problem(
                          node.span,
                          "I could not resolve member \{Json::string(name).stringify()} in the JMESPath object.",
                        )
                        Null
                      }
                    }
                }
              Unknown => Unknown
              found => {
                self.problem(
                  node.span,
                  "I expected an object when selecting JMESPath member \{Json::string(name).stringify()}, but found \{found.name(self.model)}.",
                )
                Unknown
              }
            }
            values.push(type_)
          }
          ExpressionRef(expression) => values.push(Reference(expression))
          Subexpression(left, right) | Binary(Pipe, left, right) => {
            tasks.push(Then(right))
            tasks.push(Analyze(left, input))
          }
          Projection(left, _)
          | ObjectProjection(left, _)
          | Filter(left, _, _) => {
            tasks.push(Project(node))
            tasks.push(Analyze(left, input))
          }
          Index(left, _) | Slice(left, _, _, _) | Flatten(left) | Not(left) => {
            tasks.push(Finish(node, 1, input))
            tasks.push(Analyze(left, input))
          }
          Binary(_, left, right) => {
            tasks.push(Finish(node, 2, input))
            tasks.push(Analyze(right, input))
            tasks.push(Analyze(left, input))
          }
          MultiList(nodes) | Function(_, nodes) => {
            tasks.push(Finish(node, nodes.length(), input))
            for child in nodes.rev_iter() {
              tasks.push(Analyze(child, input))
            }
          }
          MultiHash(entries) => {
            tasks.push(Finish(node, entries.length(), input))
            for entry in entries.rev_iter() {
              tasks.push(Analyze(entry.1, input))
            }
          }
        }
      Then(right) => {
        let input = values.pop().unwrap()
        if input is Reference(_) {
          self.problem(
            right.span,
            "I expected a JSON value before this JMESPath subexpression, but found an expression reference.",
          )
        }
        tasks.push(Analyze(right, input))
      }
      Project(node) => {
        let left = values.pop().unwrap()
        let object = node.kind is ObjectProjection(_, _)
        let input = contract_join(
          self.elements(left, node, object~),
          self.model,
        )
        match node.kind {
          Filter(_, predicate, right) => {
            tasks.push(ProjectionResult(true))
            tasks.push(Analyze(right, input))
            tasks.push(Analyze(predicate, input))
          }
          Projection(_, right) | ObjectProjection(_, right) => {
            tasks.push(ProjectionResult(false))
            tasks.push(Analyze(right, input))
          }
          _ => ()
        }
      }
      ProjectionResult(filter) => {
        let type_ = values.pop().unwrap()
        if filter {
          values.pop() |> ignore
        }
        values.push(Array([type_], exact=false))
      }
      CallbackResult(node, name, result) => {
        let type_ = values.pop().unwrap()
        if name == "map" {
          if type_ is Reference(_) {
            self.problem(
              node.span,
              "I expected a JSON value from the JMESPath map expression, but found an expression reference.",
            )
          }
          values.push(Array([type_], exact=false))
        } else {
          let kind = type_.name(self.model)
          if kind != "unknown" && kind != "number" && kind != "string" {
            self.problem(
              node.span,
              "I expected a number or string from the expression reference in JMESPath function \{name}, but found \{kind}.",
            )
          }
          values.push(result)
        }
      }
      Finish(node, count, input) => {
        let reversed = []
        for _ in 0..<count {
          reversed.push(values.pop().unwrap())
        }
        let args = reversed.rev_iter().to_array()
        if !(node.kind is Function(_, _)) &&
          args.iter().any(t => t is Reference(_)) {
          self.problem(
            node.span,
            "I expected JSON values for this JMESPath operation, but found an expression reference.",
          )
        }
        let result : ContractType = match node.kind {
          Not(_) => Boolean
          Binary(And | Or as op, _, _) =>
            match args[0].truth(self.model) {
              Some(truth) =>
                if truth == (op is And) {
                  args[1]
                } else {
                  args[0]
                }
              None => contract_join(args, self.model)
            }
          Binary(op, _, _) => {
            if args.iter().any(t => t is Reference(_)) {
              self.problem(
                node.span,
                "I expected JSON values for a JMESPath comparison, but found an expression reference.",
              )
            }
            if op is (Equal | NotEqual) {
              Boolean
            } else {
              let invalid = args
                .iter()
                .any(t => {
                  let kind = t.name(self.model)
                  kind != "unknown" && kind != "number"
                })
              if invalid {
                self.problem(
                  node.span,
                  "I expected numbers for an ordering comparison, but found \{args[0].name(self.model)} and \{args[1].name(self.model)}; the JMESPath result is null.",
                  severity=Warning,
                )
                Null
              } else {
                Boolean
              }
            }
          }
          Index(_, index) => {
            let elements = self.elements(args[0], node)
            match args[0].resolve(self.model) {
              Array(_, exact=true) => {
                let at = if index < 0 {
                  elements.length() + index
                } else {
                  index
                }
                if at >= 0 && at < elements.length() {
                  elements[at]
                } else {
                  Null
                }
              }
              _ => contract_join(elements, self.model)
            }
          }
          Slice(_, _, _, step) => {
            if step == Some(0) {
              self.problem(
                node.span,
                "I expected a non-zero JMESPath slice step, but found zero.",
              )
            }
            Array(self.elements(args[0], node), exact=false)
          }
          Flatten(_) => {
            let types = []
            for type_ in self.elements(args[0], node) {
              match type_.resolve(self.model) {
                Array(nested, ..) => types.append(nested)
                _ => types.push(type_)
              }
            }
            Array(types, exact=false)
          }
          MultiList(_) =>
            match input.resolve(self.model) {
              Null => Null
              Unknown => Array(args, exact=false)
              _ => Array(args, exact=true)
            }
          MultiHash(entries) => {
            let fields : Map[String, ContractType] = Map([])
            for i, entry in entries {
              fields[entry.0] = args[i]
            }
            match input.resolve(self.model) {
              Null => Null
              Unknown => Object(fields, additional=None, truth=None)
              _ =>
                Object(fields, additional=None, truth=Some(!entries.is_empty()))
            }
          }
          Function(name, _) => {
            let result = self.function_result(node, name, args)
            let callback = if name == "map" && args.length() == 2 {
              Some((args[0], args[1]))
            } else if ["sort_by", "min_by", "max_by"].contains(name) &&
              args.length() == 2 {
              Some((args[1], args[0]))
            } else {
              None
            }
            if callback is Some((Reference(body), array)) {
              let input = contract_join(self.elements(array, node), self.model)
              tasks.push(CallbackResult(node, name, result))
              tasks.push(Analyze(body, input))
              continue
            }
            result
          }
          _ => Unknown
        }
        values.push(result)
      }
    }
  }
  values.pop().unwrap_or(Unknown)
}

///|
fn Assembly::analyze_condition(
  self : Assembly,
  model : Model,
  owner : Shape,
  condition : String,
  expression : String,
) -> Unit {
  let analysis = ContractAnalysis::{
    assembly: self,
    model,
    owner,
    condition,
    expression,
    reported: Set([]),
  }
  let parsed = @jmespath.parse(expression) catch {
    @jmespath.JmespathError(diagnostic) => {
      analysis.problem(diagnostic.span, diagnostic.message, code="SM-MODEL-015")
      return
    }
  }
  let type_ = analysis.analyze(parsed.root)
  if !(type_.resolve(model) is Boolean) {
    analysis.problem(
      parsed.root.span,
      "I expected this condition to return a boolean, but statically found \{type_.name(model)}.",
      code="SM-MODEL-017",
    )
  }
}
