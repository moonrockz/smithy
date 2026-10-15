///|
/// `TraitStatements = *(Trait [WS])`.
fn Parser::parse_traits(self : Parser) -> Array[@ast.Trait] raise ParseError {
  let traits : Array[@ast.Trait] = []
  while self.at_kind(At) {
    traits.push(self.parse_trait())
  }
  traits
}

///|
/// `Trait = "@" ShapeId [TraitBody]`; `TraitBody = "(" [WS] [TraitStructure / TraitNode] ")"`.
/// A body is a structure when it starts with a key followed by `:`.
fn Parser::parse_trait(self : Parser) -> @ast.Trait raise ParseError {
  let at = self.expect_kind(At, "`@`")
  guard self.adjacent() && self.at_kind(Identifier) else {
    self.fail(
      "SM-PARSE-001",
      "UNEXPECTED TOKEN",
      "I was expecting a trait name right after `@` but found \{self.found()}",
      self.here(),
      example="@required",
    )
  }
  let id = self.parse_shape_id()
  self.push_context("the trait `@\{id.value}`", at.span)
  let mut end = id.span.end()
  let body : @ast.TraitBody? = if self.at_kind(LParen) {
    ignore(self.advance())
    self.enter()
    let b : @ast.TraitBody = if self.at_kind(RParen) {
      Structure([][:])
    } else if (self.at_kind(Identifier) || self.at_kind(String)) &&
      self.peek1() is Some(n) &&
      n.kind == Colon {
      Structure(self.parse_object_kvps(RParen, "a trait body")[:])
    } else {
      Node(self.parse_node_value())
    }
    let close = self.expect_kind(RParen, "`)` to close the trait body")
    self.leave()
    end = close.span.end()
    Some(b)
  } else {
    None
  }
  self.pop_context()
  { id, body, span: at.span.start.to(end), }
}

///|
/// An error for 2.0-only syntax in a 1.0 file. The messages are the
/// reference's. Reports nothing when `version_unknown`: a broken `$`
/// control statement might have been `$version: "2"`, so gating on 1.0
/// would be reporting an error we can't actually back up.
fn Parser::require_v2(
  self : Parser,
  feature : String,
  span : @span.Span,
) -> Unit raise ParseError {
  guard !self.version_unknown else { return }
  guard self.version != Some(V2) else { return }
  let message = match feature {
    "mixins" => "Mixins can only be used with Smithy version 2 or later"
    "elision" => "Members can only elide targets in IDL version 2 or later"
    "for" =>
      "Resource properties can only be used with Smithy version 2 or later"
    _ =>
      "Inlined operation inputs and outputs can only be used with Smithy version 2 or later"
  }
  self.fail(
    "SM-PARSE-007",
    "NEEDS SMITHY IDL 2",
    message,
    span,
    notes=[
      "This file is Smithy IDL 1.0: " +
      (if self.version is None {
        "it has no `$version` statement, so I read it as version 1.0."
      } else {
        "its `$version` says so."
      }),
    ],
    hint="Add `$version: \"2\"` as the first line of the file.",
  )
}
