# Smithy code generation core

`moonrockz/smithy-codegen` is a language-neutral core for Smithy code
generators. A generator for one target language builds on it. The module has no
file access, no network access and no process access. A generator returns its
files as a `Map[String, String]` from a path to a text, and the build runner
writes them.

The output is deterministic. No unordered iteration decides the order of the
output, and the same model gives the same bytes. Text sorts are lexical.

## Parts

| Part | Types and functions | Purpose |
|------|---------------------|---------|
| Symbols | `Symbol`, `SymbolName`, `Namespace`, `OutputPath`, `PackageName`, `SymbolDependency`, `SymbolReference` | Name a generated item, its file and its dependencies. Each type has a checked `parse` constructor. |
| Symbol provider | `SymbolProvider`, `ReservedWords` | Map a shape to a `Symbol` and a member to a name. Decorators and a cache add behavior. |
| Shape order | `service_closure`, `topological_order` | List the shapes of a service and order them by their dependencies. |
| Code writer | `CodeWriter`, `TemplateValue`, `Section`, `Interceptor` | Write text with templates, indentation, imports and sections. |
| Writer delegator | `WriterDelegator` | Keep one writer for each output file and collect the files. |
| Integrations | `Integration[C]`, `sort_integrations` | Add behavior to a generator: ordered hooks for the model, the provider and the writers. |
| Director | `DirectedCodegen[C]`, `CreateContext`, `run_codegen` | Walk the shapes of a service and call one function for each kind of shape. |
| Build plugin | `PluginContext`, `build_plugin` | Read the build settings and adapt a generator to the build runner. |

The walks keep their own stacks and do not recurse. The closure and the
topological order finish for a chain of 20,000 shapes.

### Shape order

`topological_order` places a shape after the shapes that it depends on. A cycle
is placed as one unit, by its dependencies. The order inside a cycle is lexical.
The result keeps member shapes. The director skips them.

### Errors

Each function that can fail raises `CodegenError`. The messages are in the first
person and name the construct. For example, a missing service gives
`MissingService`, and a bad template gives `InvalidTemplate` with the offset of
the problem. `build_plugin` converts a `CodegenError` to a build error.

## Templates

`CodeWriter::write` renders a template and ends the line. `write_inline`
renders a template and continues the line. `\r\n` in a template becomes `\n`.

| Syntax | Meaning |
|--------|---------|
| `$$` | A literal `$`. |
| `$L`, `$S`, `$T`, `$C` | The next argument, with a formatter. |
| `$1L` | The argument at position 1 (positions start at 1). |
| `$name:L`, `${name:L}` | The value `name` from the context of the writer. |
| `${name:C\|}` | Align the later lines of the value with the column of the expression. |
| `${?x}` ... `${/x}` | Render the block when `x` is true. |
| `${^x}` ... `${/x}` | Render the block when `x` is false. |
| `${#x}` ... `${/x}` | Render the block for each item of the list or record `x`. |
| `${#x as k, v}` | The same, with the names `k` and `v` for the key and the value. |
| `key`, `value` | The key and the value of the item in a loop. |
| `key.first`, `key.last` | True for the first and for the last item in a loop. |
| `${-` ... `-}` | Remove the white space before or after the tag. |

The formatters are:

| Formatter | Result |
|-----------|--------|
| `L` | A literal: text, a number or a Boolean as it is. |
| `S` | A string literal, with quotes and escapes. |
| `T` | A symbol. The writer adds an import when the symbol is in another namespace. |
| `C` | Code from a `Call` value, written by a nested writer. |

Add a formatter with `put_formatter`. Its character is an uppercase ASCII letter.

More rules:

- A block tag alone on a line leaves no line in the output.
- `${#x}` over a missing name or over `Null` is an error.
- A template that fails writes nothing and leaves the import tracker unchanged.
- Two symbols with the same name from two namespaces in one file: the writer
  writes the name of the second one in full.
- Use `push_state` and `pop_state` to save and restore the indentation, the
  newline prefix, the context and the formatters.

## Sections and interceptors

`inject_section` opens and closes a named section in one call, and the section is
empty. `push_section` and `pop_section` write a body between them. An
`Interceptor` for the section name changes the body:

- `Interceptor::prepender` writes before the body.
- `Interceptor::appender` writes after the body.
- `Interceptor::new` replaces the body. It receives the previous text.

Interceptors run in the order of their registration. A section that opens in the
middle of a line continues that line.

## Example

The example writes a structure. `$T` adds an import for a symbol from another
namespace. An interceptor adds a line to the section `header`.

```mbt check
///|
test {
  let item = @codegen.Symbol::new(
    @codegen.SymbolName::parse("Item").unwrap(),
    namespace=@codegen.Namespace::parse("example.items", separator=".").unwrap(),
  )
  let order = @codegen.Symbol::new(
    @codegen.SymbolName::parse("Order").unwrap(),
    namespace=@codegen.Namespace::parse("example.orders", separator=".").unwrap(),
  )
  let writer = @codegen.CodeWriter::new(namespace=order.namespace)
  writer.on_section(
    @codegen.Interceptor::appender("header", (w, _) => w.write("// generated")),
  )
  writer.inject_section(@codegen.Section::new("header"))
  writer.put_context("members", @codegen.Record({ "item": @codegen.Sym(item) }))
  writer.write(
    "structure $T {\n${#members}\n    ${key:L}: ${value:T}\n${/members}\n}",
    args=[@codegen.Sym(order)],
  )
  assert_eq(
    writer.to_string(),
    "// generated\nstructure Order {\n    item: Item\n}\n",
  )
  assert_eq(writer.imports().map(entry => entry.name.to_string()), ["Item"])
}
```

## Build plugin

`build_plugin` adapts a function from `PluginContext` to the plugin type of
`moonrockz/smithy-build`. The settings of a plugin start with `service`, the
shape ID of the service. `PluginContext::check_settings` fails on a key that the
generator does not know.

The subpackage `moonrockz/smithy-codegen/fixture` is a toy generator that
writes an outline of each shape. It tests the module end to end. The Smithy CLI
registers it as the plugin `codegenFixture`. Its settings are `service`
(required) and `header` (optional text for the first line of each file).

```json
{
  "version": "1.0",
  "sources": ["model"],
  "plugins": {
    "codegenFixture": {
      "service": "example.orders#Orders",
      "header": "generated"
    }
  }
}
```

```sh
smithy build --config smithy-build.json
```

The plugin writes one file for each shape, for example
`example/orders/Order.outline`. It also writes `dependencies.txt` when a symbol
needs a package.
