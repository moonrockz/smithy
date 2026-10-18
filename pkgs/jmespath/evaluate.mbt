///|
fn truthy(value : Json) -> Bool {
  match value {
    Null | False => false
    String(s) => !s.is_empty()
    Array(xs) => !xs.is_empty()
    Object(fields) => !fields.is_empty()
    _ => true
  }
}

///|
fn json_type(value : Json) -> String {
  match value {
    Null => "null"
    True | False => "boolean"
    Number(_, ..) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
priv enum Task {
  Eval(Node, Json, Int32)
  Sub(Node, Int32)
  AtIndex(Int32)
  AtSlice(Int32?, Int32?, Int32?, Span)
  Flatten
  ProjectStart(Node, Int32, Bool)
  Project(Array[Json], Node, Int32, Array[Json], Int32)
  ProjectValue(Array[Json], Node, Int32, Array[Json], Int32)
  FilterStart(Node, Node, Int32)
  Filter(Array[Json], Node, Node, Int32, Array[Json], Int32)
  FilterPredicate(Array[Json], Node, Node, Int32, Array[Json], Int32)
  FilterValue(Array[Json], Node, Node, Int32, Array[Json], Int32)
  ListResult(Int32)
  HashResult(Array[String])
  Negate
  BinaryLeft(Operator, Node, Json, Int32)
  Compare(Operator, Json)
  Call(String, Array[Node], Span, Int32)
  Callback(String, Array[Json], Node, Int32, Array[Json], Int32)
  CallbackValue(String, Array[Json], Node, Int32, Array[Json], Int32)
}

///|
fn take_results(values : Array[Json], count : Int32) -> Array[Json] {
  let out = []
  for _ in 0..<count {
    out.push(values.pop().unwrap())
  }
  out.rev_iter().to_array()
}

///|
fn slice_bound(value : Int32, length : Int32, negative : Bool) -> Int32 {
  let value = if value < 0 { value + length } else { value }
  if negative {
    value.max(-1).min(length - 1)
  } else {
    value.max(0).min(length)
  }
}

///|
fn slice_array(
  input : Json,
  start : Int32?,
  stop : Int32?,
  step : Int32?,
  span : Span,
) -> Json raise JmespathError {
  let step = step.unwrap_or(1)
  if step == 0 {
    problem(
      InvalidValue,
      span,
      "I expected a nonzero JMESPath slice step, but found 0.",
    )
  }
  guard input is Array(values) else { return Json::null() }
  let n = values.length()
  let negative = step < 0
  let mut i = start
    .map(v => slice_bound(v, n, negative))
    .unwrap_or(if negative { n - 1 } else { 0 })
  let end = stop
    .map(v => slice_bound(v, n, negative))
    .unwrap_or(if negative { -1 } else { n })
  let out = []
  while (if negative { i > end } else { i < end }) {
    out.push(values[i])
    if (!negative && step >= end - i) || (negative && step <= end - i) {
      break
    }
    i += step
  }
  Json::array(out)
}

///|
/// Evaluate with an explicit continuation stack, including function callbacks.
pub fn Expression::evaluate(
  self : Expression,
  input : Json,
  max_steps~ : Int32 = 1000000,
) -> Json raise JmespathError {
  let tasks = [Task::Eval(self.root, input, 0)]
  let values : Array[Json] = []
  let mut remaining = max_steps
  while tasks.pop() is Some(task) {
    match task {
      Eval(expr, input, depth) => {
        if remaining <= 0 || depth >= 256 {
          problem(
            InvalidValue,
            expr.span,
            "I reached the JMESPath evaluation step or nesting limit.",
          )
        }
        remaining -= 1
        let next = depth + 1
        match expr.kind {
          Identity => values.push(input)
          Literal(value) => values.push(value)
          Field(name) =>
            values.push(
              match input {
                Object(fields) => fields.get(name).unwrap_or(Json::null())
                _ => Json::null()
              },
            )
          Subexpression(left, right) => {
            tasks.push(Sub(right, next))
            tasks.push(Eval(left, input, next))
          }
          Index(left, index) => {
            tasks.push(AtIndex(index))
            tasks.push(Eval(left, input, next))
          }
          Slice(left, start, stop, step) => {
            tasks.push(AtSlice(start, stop, step, expr.span))
            tasks.push(Eval(left, input, next))
          }
          Flatten(left) => {
            tasks.push(Flatten)
            tasks.push(Eval(left, input, next))
          }
          Projection(left, right) => {
            tasks.push(ProjectStart(right, next, false))
            tasks.push(Eval(left, input, next))
          }
          ObjectProjection(left, right) => {
            tasks.push(ProjectStart(right, next, true))
            tasks.push(Eval(left, input, next))
          }
          Filter(left, predicate, right) => {
            tasks.push(FilterStart(predicate, right, next))
            tasks.push(Eval(left, input, next))
          }
          MultiList(children) =>
            if input == Json::null() {
              values.push(input)
            } else {
              tasks.push(ListResult(children.length()))
              for child in children.rev_iter() {
                tasks.push(Eval(child, input, next))
              }
            }
          MultiHash(children) =>
            if input == Json::null() {
              values.push(input)
            } else {
              tasks.push(HashResult(children.map(entry => entry.0)))
              for (_, child) in children.rev_iter() {
                tasks.push(Eval(child, input, next))
              }
            }
          Not(child) => {
            tasks.push(Negate)
            tasks.push(Eval(child, input, next))
          }
          Binary(op, left, right) => {
            tasks.push(BinaryLeft(op, right, input, next))
            tasks.push(Eval(left, input, next))
          }
          Function(name, args) => {
            check_arity(name, args.length(), expr.span) |> ignore
            tasks.push(Call(name, args, expr.span, next))
            for arg in args.rev_iter() {
              if !(arg.kind is ExpressionRef(_)) {
                tasks.push(Eval(arg, input, next))
              }
            }
          }
          ExpressionRef(_) =>
            problem(
              InvalidType,
              expr.span,
              "I expected JSON, but found a JMESPath expression reference.",
            )
        }
      }
      Sub(right, depth) => tasks.push(Eval(right, values.pop().unwrap(), depth))
      AtIndex(index) => {
        let result = match values.pop().unwrap() {
          Array(xs) =>
            xs
            .get(if index < 0 { index + xs.length() } else { index })
            .unwrap_or(Json::null())
          _ => Json::null()
        }
        values.push(result)
      }
      AtSlice(start, stop, step, span) =>
        values.push(slice_array(values.pop().unwrap(), start, stop, step, span))
      Flatten =>
        match values.pop().unwrap() {
          Array(xs) => {
            let out = []
            for x in xs {
              match x {
                Array(xs) => out.append(xs)
                _ => out.push(x)
              }
            }
            values.push(Json::array(out))
          }
          _ => values.push(Json::null())
        }
      ProjectStart(right, depth, object) => {
        let source = values.pop().unwrap()
        let xs = match (object, source) {
          (false, Array(xs)) => xs
          (true, Object(fields)) => {
            let xs = []
            for _, x in fields {
              xs.push(x)
            }
            xs
          }
          _ => {
            values.push(Json::null())
            continue
          }
        }
        tasks.push(Project(xs, right, 0, [], depth))
      }
      Project(xs, right, i, out, depth) =>
        if i == xs.length() {
          values.push(Json::array(out))
        } else {
          tasks.push(ProjectValue(xs, right, i + 1, out, depth))
          tasks.push(Eval(right, xs[i], depth))
        }
      ProjectValue(xs, right, i, out, depth) => {
        let value = values.pop().unwrap()
        if value != Json::null() {
          out.push(value)
        }
        tasks.push(Project(xs, right, i, out, depth))
      }
      FilterStart(predicate, right, depth) =>
        match values.pop().unwrap() {
          Array(xs) => tasks.push(Filter(xs, predicate, right, 0, [], depth))
          _ => values.push(Json::null())
        }
      Filter(xs, predicate, right, i, out, depth) =>
        if i == xs.length() {
          values.push(Json::array(out))
        } else {
          tasks.push(FilterPredicate(xs, predicate, right, i, out, depth))
          tasks.push(Eval(predicate, xs[i], depth))
        }
      FilterPredicate(xs, predicate, right, i, out, depth) =>
        if truthy(values.pop().unwrap()) {
          tasks.push(FilterValue(xs, predicate, right, i + 1, out, depth))
          tasks.push(Eval(right, xs[i], depth))
        } else {
          tasks.push(Filter(xs, predicate, right, i + 1, out, depth))
        }
      FilterValue(xs, predicate, right, i, out, depth) => {
        let value = values.pop().unwrap()
        if value != Json::null() {
          out.push(value)
        }
        tasks.push(Filter(xs, predicate, right, i, out, depth))
      }
      ListResult(count) => values.push(Json::array(take_results(values, count)))
      HashResult(keys) => {
        let results = take_results(values, keys.length())
        let out : Map[String, Json] = Map([])
        for i, key in keys {
          out[key] = results[i]
        }
        values.push(Json::object(out))
      }
      Negate => values.push(Json::boolean(!truthy(values.pop().unwrap())))
      BinaryLeft(op, right, input, depth) => {
        let a = values.pop().unwrap()
        match op {
          Pipe => tasks.push(Eval(right, a, depth))
          Or if truthy(a) => values.push(a)
          And if !truthy(a) => values.push(a)
          Or | And => tasks.push(Eval(right, input, depth))
          _ => {
            tasks.push(Compare(op, a))
            tasks.push(Eval(right, input, depth))
          }
        }
      }
      Compare(op, a) => {
        let b = values.pop().unwrap()
        let result = match op {
          Equal => Json::boolean(a == b)
          NotEqual => Json::boolean(a != b)
          _ =>
            match (a, b) {
              (Number(a, ..), Number(b, ..)) =>
                Json::boolean(
                  match op {
                    Less => a < b
                    LessEqual => a <= b
                    Greater => a > b
                    GreaterEqual => a >= b
                    _ => false
                  },
                )
              _ => Json::null()
            }
        }
        values.push(result)
      }
      Call(name, nodes, span, depth) => {
        let count = nodes
          .iter()
          .filter(n => !(n.kind is ExpressionRef(_)))
          .count()
        let results = take_results(values, count)
        let args = []
        let mut i = 0
        for arg in nodes {
          args.push(
            match arg.kind {
              ExpressionRef(expr) => Reference(expr)
              _ => {
                let value = results[i]
                i += 1
                Value(value)
              }
            },
          )
        }
        check_arguments(name, nodes, args, span)
        if name == "map" ||
          name == "sort_by" ||
          name == "min_by" ||
          name == "max_by" {
          let (array, reference) = if name == "map" {
            (args[1], args[0])
          } else {
            (args[0], args[1])
          }
          guard array is Value(Array(xs)) && reference is Reference(expr) else {
            return type_error(name, "an array and an expression", span)
          }
          tasks.push(Callback(name, xs, expr, 0, [], depth))
        } else {
          values.push(call(name, nodes, args, span))
        }
      }
      Callback(name, xs, expr, i, out, depth) =>
        if i == xs.length() {
          values.push(
            if name == "map" {
              Json::array(out)
            } else {
              apply_keys(name, xs, out, expr.span)
            },
          )
        } else {
          tasks.push(CallbackValue(name, xs, expr, i + 1, out, depth))
          tasks.push(Eval(expr, xs[i], depth))
        }
      CallbackValue(name, xs, expr, i, out, depth) => {
        out.push(values.pop().unwrap())
        tasks.push(Callback(name, xs, expr, i, out, depth))
      }
    }
  }
  values.pop().unwrap()
}

///|
/// Parse and evaluate a JMESPath expression against a JSON value.
pub fn search(
  source : String,
  input : Json,
  max_steps~ : Int32 = 1000000,
) -> Json raise JmespathError {
  parse(source).evaluate(input, max_steps~)
}
