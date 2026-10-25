///|
/// The message of the error that `f` raises; it fails when `f` raises none.
fn message_of(f : () -> Unit raise) -> String raise {
  f() catch {
    Failure(msg) => return msg
    e => return e.to_string()
  }
  fail("I expected an error, but there was none")
}

///|
fn step_error(text : String) -> String raise {
  message_of(() => ignore(read_steps(@json.parse(text), "case")))
}

///|
fn setup_error(text : String) -> String raise {
  message_of(() => ignore(read_transcript(@json.parse(text), "lesson")))
}

///|
test "a step count must be a whole number from 1" {
  for count in ["0", "1.5", "-1", "\"1\""] {
    let msg = step_error(
      "{\"steps\": [{\"count\": \{count}, \"findings\": []}]}",
    )
    assert_true(msg.contains("\"count\" as a whole number from 1"))
  }
  let msg = step_error("{\"steps\": [{\"findings\": []}]}")
  assert_true(msg.contains("\"count\" as a whole number from 1"))
}

///|
test "steps must be an array" {
  let msg = step_error("{\"steps\": {\"count\": 1}}")
  assert_true(msg.contains("\"steps\" must be an array"))
}

///|
test "an item of steps has the keys count and findings only" {
  let msg = step_error(
    "{\"steps\": [{\"count\": 1, \"findings\": [], \"extra\": 1}]}",
  )
  assert_true(msg.contains("I do not know the key \"extra\""))
}

///|
test "transcript has the keys file and protocol only" {
  let msg = setup_error(
    "{\"file\": \"a.json\", \"protocol\": \"a#P\", \"format\": \"json\"}",
  )
  assert_true(msg.contains("I do not know the key \"format\""))
}

///|
test "the protocol of a transcript is not empty" {
  let msg = setup_error("{\"file\": \"a.json\", \"protocol\": \"\"}")
  assert_true(msg.contains("\"protocol\" is empty"))
}
