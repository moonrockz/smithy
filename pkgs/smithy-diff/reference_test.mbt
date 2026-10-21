///|
fn fixture(name : String) -> String raise {
  @fs.read_file_to_string("../../tests/tck/diff/" + name)
}

///|
fn load(name : String) -> @smithy.Model raise {
  let result = @smithy.Loader::new().add_idl(name, fixture(name)).assemble()
  guard result.model is Some(model) else {
    fail(
      name +
      "\n" +
      result.validation_events().map(e => e.id + ": " + e.message).join("\n"),
    )
  }
  model
}

///|
fn mutate(model : @smithy.Model, changes : Json) -> @smithy.Model raise {
  guard changes is Array(changes) else { fail("Invalid mutation list") }
  let shapes = model.shapes.copy()
  for change in changes {
    guard change is { "shape": String(shape_id), "trait": String(trait_id), .. } else {
      fail("Invalid trait mutation")
    }
    let shape_id = @smithy.ShapeId::parse(shape_id).unwrap()
    let trait_id = @smithy.ShapeId::parse(trait_id).unwrap()
    let shape = shapes.get(shape_id).unwrap()
    let traits = shape.traits.copy()
    if change is { "value": value, .. } {
      traits[trait_id] = @smithy.NodeValue::from_json(value)
    } else {
      ignore(traits.remove(trait_id))
    }
    shapes[shape_id] = { ..shape, traits, }
  }
  { ..model, shapes, }
}

///|
test "all pinned reference cases match full events and breaking status" {
  let manifest = @json.parse(fixture("events.json"))
  guard manifest
    is {
      "referenceSha": String("30bdab593f0c2cdf96036782cc3ce15c43a711ef"),
      "cases": Array(cases),
      ..
    } else {
    fail("Invalid reference manifest")
  }
  assert_true(cases.length() >= 84)
  let failures = []
  for case in cases {
    guard case
      is {
        "old": String(old_path),
        "new": String(new_path),
        "breaking": breaking,
        "events": Array(expected),
        ..
      } else {
      fail("Invalid reference case")
    }
    let old_model = load(old_path)
    let new_model = if case is { "mutations": changes, .. } {
      mutate(old_model, changes)
    } else {
      load(new_path)
    }
    let result = @diff.compare(old_model, new_model)
    let actual_keys = result.events.map(e => {
      e.id +
      "|" +
      e.shape.map(id => id.to_string()).unwrap_or("-") +
      "|" +
      e.severity +
      "|" +
      e.message
    })
    let expected_keys = expected.map(e => {
      match e {
        {
          "id": String(id),
          "shape": String(shape),
          "severity": String(severity),
          "message": String(message),
          ..
        } => id + "|" + shape + "|" + severity + "|" + message
        _ => "invalid"
      }
    })
    actual_keys.sort_by((a, b) => a.lexical_compare(b))
    expected_keys.sort_by((a, b) => a.lexical_compare(b))
    if actual_keys != expected_keys || Json(result.is_breaking()) != breaking {
      failures.push(
        old_path +
        "\n  expected: " +
        expected_keys.join(", ") +
        "\n  actual:   " +
        actual_keys.join(", "),
      )
    }
  }
  assert_eq(failures.join("\n\n"), "")
}

///|
test "every vendored model and events fixture is represented in reference cases" {
  guard @json.parse(fixture("events.json")) is { "cases": Array(cases), .. } else {
    fail("Invalid cases")
  }
  let used : Set[String] = Set([])
  for case in cases {
    guard case is { "old": String(old_path), "new": String(new_path), .. } else {
      fail("Invalid case paths")
    }
    used.add(old_path)
    used.add(new_path)
  }
  guard @json.parse(fixture("inventory.json")) is { "files": Array(files), .. } else {
    fail("Invalid inventory")
  }
  let uncovered = []
  for file in files {
    guard file is { "path": String(path), .. } else {
      fail("Invalid inventory entry")
    }
    if path == "LICENSE" {
      continue
    }
    let model_path = if path.has_suffix(".events") {
      path[:path.length() - 7].to_owned() + ".a.smithy"
    } else {
      path
    }
    if !used.contains(model_path) {
      uncovered.push(path)
    }
  }
  assert_eq(uncovered, [])
}
