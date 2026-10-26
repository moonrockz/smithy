///|
fn pkg_ns(path : String) -> @codegen.Namespace {
  @codegen.Namespace::parse(path, separator="/").unwrap()
}

///|
fn pkg_symbol(path : String, name : String) -> @codegen.Symbol {
  @codegen.Symbol::new(imp_name(name), ns=pkg_ns(path))
}

///|
/// The last segment of an import path, as Go and MoonBit name a package.
fn last_segment(ns : @codegen.Namespace) -> @codegen.SymbolName {
  let parts = ns.text.split("/").map(part => part.to_owned()).collect()
  imp_name(parts[parts.length() - 1])
}

///|
fn go_policy() -> @codegen.ImportPolicy {
  @codegen.ImportPolicy::by_package(
    qualify=(qualifier, symbol) => {
      "\{qualifier.to_string()}.\{symbol.name.to_string()}"
    },
    qualifier=last_segment,
    locals_block_qualifiers=true,
  )
}

///|
fn moonbit_policy() -> @codegen.ImportPolicy {
  @codegen.ImportPolicy::by_package(
    qualify=(qualifier, symbol) => {
      "@\{qualifier.to_string()}.\{symbol.name.to_string()}"
    },
    qualifier=last_segment,
    locals_block_qualifiers=false,
  )
}

///|
fn pkg_import(
  path : String,
  qualifier : String,
  explicit~ : Bool = false,
) -> @codegen.PackageImport {
  { ns: pkg_ns(path), qualifier: imp_name(qualifier), explicit, }
}

///|
test "the default policy imports by name" {
  let w = @codegen.CodeWriter::new(
    ns=imp_ns("a"),
    imports=@codegen.ImportPolicy::by_name(),
  )
  w.write("use $T", args=[@codegen.Sym(imp_symbol("b", "Item"))])
  assert_eq(w.to_string(), "use Item\n")
  assert_eq(w.imports(), [imp_entry("b", "Item")])
  assert_eq(w.package_imports(), [])
}

///|
test "a package policy qualifies a foreign symbol and imports its package" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/payments"),
    imports=go_policy(),
  )
  w.write("var a $T = $T", args=[
    @codegen.Sym(pkg_symbol("example/payments/rpc", "Decimal")),
    @codegen.Sym(pkg_symbol("example/payments/rpc", "Zero")),
  ])
  assert_eq(w.to_string(), "var a rpc.Decimal = rpc.Zero\n")
  assert_eq(w.package_imports(), [pkg_import("example/payments/rpc", "rpc")])
  assert_eq(w.imports(), [])
}

///|
test "a package policy writes local and root symbols bare" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/payments"),
    imports=moonbit_policy(),
  )
  w.write("$T $T", args=[
    @codegen.Sym(pkg_symbol("example/payments", "Money")),
    @codegen.Sym(@codegen.Symbol::new(imp_name("String"))),
  ])
  assert_eq(w.to_string(), "Money String\n")
  assert_eq(w.package_imports(), [])
}

///|
test "moonbit qualifies with an at sign" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/pos"),
    imports=moonbit_policy(),
  )
  w.write("$T", args=[@codegen.Sym(pkg_symbol("example/pos/rpc", "Peer"))])
  assert_eq(w.to_string(), "@rpc.Peer\n")
}

///|
test "an explicit qualifier names the package" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/payments"),
    imports=go_policy(),
  )
  let reference = @codegen.SymbolReference::new(
    pkg_symbol("example/payments/rpc", "ID"),
    local_name=Some(imp_name("jrpc")),
  )
  w.write("$T $T", args=[
    @codegen.Ref(reference),
    @codegen.Sym(pkg_symbol("example/payments/rpc", "Decimal")),
  ])
  assert_eq(w.to_string(), "jrpc.ID jrpc.Decimal\n")
  assert_eq(w.package_imports(), [
    pkg_import("example/payments/rpc", "jrpc", explicit=true),
  ])
}

///|
test "two packages with one qualifier get distinct aliases in order of use" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/app"),
    imports=go_policy(),
  )
  w.write("$T $T $T $T", args=[
    @codegen.Sym(pkg_symbol("example/a/rpc", "One")),
    @codegen.Sym(pkg_symbol("example/b/rpc", "Two")),
    @codegen.Sym(pkg_symbol("example/c/rpc", "Three")),
    @codegen.Sym(pkg_symbol("example/b/rpc", "Four")),
  ])
  assert_eq(w.to_string(), "rpc.One rpc2.Two rpc3.Three rpc2.Four\n")
  assert_eq(w.package_imports(), [
    pkg_import("example/a/rpc", "rpc"),
    pkg_import("example/b/rpc", "rpc2"),
    pkg_import("example/c/rpc", "rpc3"),
  ])
}

///|
test "a reserved name blocks an qualifier when the policy says so" {
  let go = @codegen.CodeWriter::new(
    ns=pkg_ns("example/app"),
    imports=go_policy(),
  )
  go.reserve_name(imp_name("rpc"))
  go.write("$T", args=[@codegen.Sym(pkg_symbol("example/x/rpc", "ID"))])
  assert_eq(go.to_string(), "rpc2.ID\n")
  let mbt = @codegen.CodeWriter::new(
    ns=pkg_ns("example/app"),
    imports=moonbit_policy(),
  )
  mbt.reserve_name(imp_name("rpc"))
  mbt.write("$T", args=[@codegen.Sym(pkg_symbol("example/x/rpc", "ID"))])
  assert_eq(mbt.to_string(), "@rpc.ID\n")
}

///|
test "a local symbol of the writer namespace blocks an qualifier" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/app"),
    imports=go_policy(),
  )
  w.write("$T $T", args=[
    @codegen.Sym(pkg_symbol("example/app", "time")),
    @codegen.Sym(pkg_symbol("time", "Time")),
  ])
  assert_eq(w.to_string(), "time time2.Time\n")
}

///|
test "references import their packages and dependencies" {
  let dependency = imp_dep("github.com/example/decimal", "v1.2.0")
  let element = pkg_symbol("github.com/example/decimal", "Big").with_dependency(
    dependency,
  )
  let list = pkg_symbol("example/payments/rpc", "List").with_reference(
    @codegen.SymbolReference::new(element),
  )
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/payments"),
    imports=go_policy(),
  )
  w.add_import(list)
  assert_eq(w.package_imports(), [
    pkg_import("example/payments/rpc", "rpc"),
    pkg_import("github.com/example/decimal", "decimal"),
  ])
  assert_eq(w.dependencies(), [dependency])
}

///|
test "child writers share the package imports" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/payments"),
    imports=go_policy(),
  )
  let child = w.child()
  child.write("$T", args=[
    @codegen.Sym(pkg_symbol("example/payments/rpc", "ID")),
  ])
  assert_eq(child.to_string(), "rpc.ID\n")
  assert_eq(w.package_imports(), [pkg_import("example/payments/rpc", "rpc")])
}

///|
test "a failed template leaves the package imports unchanged" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/payments"),
    imports=go_policy(),
  )
  w.write("$T", args=[@codegen.Sym(pkg_symbol("example/a/rpc", "One"))])
  try
    w.write("$T $L", args=[@codegen.Sym(pkg_symbol("example/b/rpc", "Two"))])
  catch {
    _ => ()
  } noraise {
    _ => fail("expected an error for the missing argument")
  }
  assert_eq(w.package_imports(), [pkg_import("example/a/rpc", "rpc")])
  // The qualifier of the rolled-back package is free again.
  w.write("$T", args=[@codegen.Sym(pkg_symbol("example/c/rpc", "Three"))])
  assert_eq(w.package_imports(), [
    pkg_import("example/a/rpc", "rpc"),
    pkg_import("example/c/rpc", "rpc2"),
  ])
}

///|
test "package imports sort by import path" {
  let w = @codegen.CodeWriter::new(
    ns=pkg_ns("example/app"),
    imports=go_policy(),
  )
  w.write("$T $T", args=[
    @codegen.Sym(pkg_symbol("time", "Time")),
    @codegen.Sym(pkg_symbol("encoding/json", "RawMessage")),
  ])
  assert_eq(w.package_imports(), [
    pkg_import("encoding/json", "json"),
    pkg_import("time", "time"),
  ])
}
