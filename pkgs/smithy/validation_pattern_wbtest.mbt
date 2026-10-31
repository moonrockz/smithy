///|
test "core_pattern escapes the literal dashes of a class" {
  inspect(
    core_pattern("^[a-zA-Z_][a-zA-Z_0-9-]*(:[a-zA-Z_][a-zA-Z_0-9-]*)?$"),
    content="^[a-zA-Z_][a-zA-Z_0-9\\-]*(:[a-zA-Z_][a-zA-Z_0-9\\-]*)?$",
  )
  inspect(core_pattern("[-a]"), content="[\\-a]")
  inspect(core_pattern("[^-a]"), content="[^\\-a]")
  inspect(core_pattern("[a-]"), content="[a\\-]")
  inspect(core_pattern("[a-z-_]"), content="[a-z\\-_]")
  inspect(core_pattern("[a-z-0-9]"), content="[a-z\\-0-9]")
  inspect(core_pattern("[\\s-a]"), content="[\\s\\-a]")
  inspect(core_pattern("[\\--/]"), content="[\\--/]")
  inspect(core_pattern("a-b[x]-c"), content="a-b[x]-c")
  inspect(core_pattern("[\\]-]"), content="[\\]\\-]")
}

///|
test "core_pattern gives ASCII classes for \\d and \\w" {
  inspect(core_pattern("^\\d+-\\w$"), content="^[0-9]+-[a-zA-Z0-9_]$")
}

///|
test "core patterns compile and match as ECMA 262 patterns do" {
  let pattern = "^[a-zA-Z_][a-zA-Z_0-9-]*(:[a-zA-Z_][a-zA-Z_0-9-]*)?$"
  let regex = @string.Regex::Regex(core_pattern(pattern))
  inspect(regex.execute("customname") is Some(_), content="true")
  inspect(regex.execute("custom-prefix:custom-name") is Some(_), content="true")
  inspect(regex.execute("too:many:colons") is Some(_), content="false")
}
