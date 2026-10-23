///|
fn kinds(tokens : Array[Token]) -> String {
  tokens
  .filter(t => t.kind != Plain)
  .map(t => {
    let k = match t.kind {
      Keyword => "kw"
      Str => "str"
      Comment => "com"
      Number => "num"
      Tag => "tag"
      Type => "type"
      DocComment => "doc"
      Plain => "plain"
    }
    k + ":" + t.text
  })
  .join(" ")
}

///|
fn joined(tokens : Array[Token]) -> String {
  tokens.map(t => t.text).join("")
}

///|
/// The first 20 lines of `examples/json-rpc/peers.smithy`.
let peers_head : String =
  #|$version: "2"
  #|namespace example.peers
  #|
  #|use smithy.rpc#jsonRpc
  #|use smithy.rpc#jsonRpcLifecycle
  #|use smithy.rpc#jsonRpcProtocol
  #|use smithy.rpc#jsonRpcSession
  #|use smithy.rpc#method
  #|
  #|/// JSON-RPC 1.0 section 4 echo and chat examples.
  #|@jsonRpcProtocol(
  #|    versions: ["1.0"]
  #|    peers: [
  #|        { name: "client", accepts: ChatClient }
  #|        { name: "server", accepts: ChatServer }
  #|    ]
  #|)
  #|structure EchoChat {}
  #|
  #|@jsonRpc(versions: ["1.0"])
  #|service ChatServer {
  #|    version: "1"

///|
test "smithy: first 20 lines of peers.smithy" {
  let tokens = highlight("smithy", peers_head)
  assert_eq(joined(tokens), peers_head)
  inspect(
    kinds(tokens),
    content=(
      #|kw:$version str:"2" kw:namespace kw:use kw:use kw:use kw:use kw:use doc:/// JSON-RPC 1.0 section 4 echo and chat examples. tag:@jsonRpcProtocol str:"1.0" str:"client" str:"server" kw:structure type:EchoChat tag:@jsonRpc str:"1.0" kw:service type:ChatServer str:"1"
    ),
  )
}

///|
test "smithy: shape keywords are contextual, names are types" {
  let src = "structure A for B with [C] {\n    list: String\n    flag: true\n}\nlist Names { member: String }\n"
  let tokens = highlight("smithy", src)
  assert_eq(joined(tokens), src)
  inspect(
    kinds(tokens),
    content=(
      #|kw:structure type:A kw:for kw:with kw:true kw:list type:Names
    ),
  )
}

///|
test "smithy: text blocks, numbers, comments, traits" {
  let src = "@documentation(\"\"\"\n  two\n  \"\"\")\n@range(min: -1.5e3, max: 20)\n// plain\nstring S\n"
  let tokens = highlight("smithy", src)
  assert_eq(joined(tokens), src)
  inspect(
    kinds(tokens),
    content=(
      #|tag:@documentation str:"""
      #|  two
      #|  """ tag:@range num:-1.5e3 num:20 com:// plain kw:string type:S
    ),
  )
}

///|
test "json and jsonl: strings, numbers, literals" {
  let src = "{\"id\": -1, \"ok\": true, \"x\": null}\n[1.5e2, \"a\"]"
  let tokens = highlight("json", src)
  assert_eq(joined(tokens), src)
  inspect(
    kinds(tokens),
    content=(
      #|str:"id" num:-1 str:"ok" kw:true str:"x" kw:null num:1.5e2 str:"a"
    ),
  )
  assert_eq(highlight("jsonl", src), tokens)
}

///|
test "moonbit keywords, attributes, strings, comments" {
  let src = "#smithy.given(\"a {int}\")\nfn f(w : W) -> Unit { // hi\n  let n = 42\n}"
  let tokens = highlight("moonbit", src)
  assert_eq(joined(tokens), src)
  inspect(
    kinds(tokens),
    content="tag:#smithy.given str:\"a {int}\" kw:fn com:// hi kw:let num:42",
  )
}

///|
test "shell comments and strings; unknown languages are plain" {
  let src = "# 1. add\nmoon add \"moonrockz/smithy\"\n"
  assert_eq(
    kinds(highlight("bash", src)),
    "com:# 1. add str:\"moonrockz/smithy\"",
  )
  let plain = highlight("text", "anything 42")
  assert_eq(plain, [{ kind: Plain, text: "anything 42", }])
  assert_eq(highlight("moonbit", ""), [])
}

///|
test "unterminated strings run to the end of the line" {
  let src = "let s = \"open\nnext"
  let tokens = highlight("moonbit", src)
  assert_eq(joined(tokens), src)
  inspect(kinds(tokens), content="kw:let str:\"open")
}

///|
test "every language reproduces its source exactly" {
  let langs = [
    "moonbit", "mbt", "smithy", "bash", "sh", "shell", "console", "zsh", "json",
    "jsonl", "text",
  ]
  let samples = [
    "", "\n", "\r\n", "\"", "a \"b\" # c // d", "\"\"\"", "\"\"\"x\n\"\"", "structure X {\n  a: 1\n}\n",
    "$version: \"2\"\n@t(\"s\")\n/// d", "-", "1e", "1e+",
  ]
  for lang in langs {
    for src in samples {
      assert_eq(joined(highlight(lang, src)), src)
    }
  }
}
