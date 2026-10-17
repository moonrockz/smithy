# moonrockz/smithy-syntax

Smithy IDL syntax for MoonBit. See [README.mbt.md](README.mbt.md) and the maintained [design](DESIGN.md).

The facade exports `parse_tokens`, `codes`, and `render_all_to` for clients
that already have tokens or a diagnostic sink. Scanner pipeline records
`Piece` and `Step`, and parser implementation types `Depth` and `ParseError`,
are available through their packages rather than through the facade.
The property-test generators live in `internal/lawkit`.
