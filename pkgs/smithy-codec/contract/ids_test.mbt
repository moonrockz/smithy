///|
fn refused(run : () -> Unit raise @contract.IdentityError) -> String {
  try run() catch {
    @contract.InvalidIdentity(kind, message) => kind + ": " + message
  } noraise {
    _ => "accepted"
  }
}

///|
test "boundary constructors refuse invalid identities" {
  inspect(
    refused(() => ignore(@contract.ProfileId::parse("morphir-v4"))),
    content="accepted",
  )
  inspect(
    refused(() => ignore(@contract.ProfileId::parse("Morphir"))),
    content="ProfileId: I expected lower-case letters and digits separated by single '.' or '-', but found \"Morphir\".",
  )
  inspect(
    refused(() => ignore(@contract.ProfileId::parse("a--b"))),
    content="ProfileId: I expected lower-case letters and digits separated by single '.' or '-', but found \"a--b\".",
  )
  inspect(
    refused(() => ignore(@contract.AdapterId::parse("x."))),
    content="AdapterId: I expected lower-case letters and digits separated by single '.' or '-', but found \"x.\".",
  )
  inspect(
    refused(() => ignore(@contract.BundleId::parse(""))),
    content="BundleId: I expected lower-case letters and digits separated by single '.' or '-', but found \"\".",
  )
  inspect(
    refused(() => ignore(@contract.WireName::parse(""))),
    content="WireName: I expected a wire name of 1..1024 characters.",
  )
  inspect(
    refused(() => {
      ignore(
        @contract.WireName::parse(
          String::from_array([(0xD800).unsafe_to_char()]),
        ),
      )
    }),
    content="WireName: I expected a wire name without an unpaired surrogate.",
  )
  inspect(
    refused(() => ignore(@contract.Release::parse("4.0"))),
    content="Release: I expected a release of three components X.Y.Z, but found \"4.0\".",
  )
  inspect(
    refused(() => ignore(@contract.Release::parse("4.01.0"))),
    content="Release: I expected decimal release components without leading zeros, but found \"4.01.0\".",
  )
  inspect(
    refused(() => {
      ignore(
        @contract.ReleaseInterval::new(
          @contract.Release::parse("4.0.0"),
          @contract.Release::parse("3.0.0"),
        ),
      )
    }),
    content="ReleaseInterval: I expected the interval start 4.0.0 to precede its end 3.0.0.",
  )
  let interval = @contract.ReleaseInterval::new(
    @contract.Release::parse("3.1.0"),
    @contract.Release::parse("3.2.0"),
  )
  assert_true(interval.contains(@contract.Release::parse("3.1.9")))
  assert_false(interval.contains(@contract.Release::parse("3.2.0")))
  assert_true(
    @contract.Release::parse("3.10.0") > @contract.Release::parse("3.9.0"),
  )
}
