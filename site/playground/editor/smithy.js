// Smithy IDL for CodeMirror: a stream language with the token kinds of the site's highlighter
// (site/highlight/highlight.mbt, scan_smithy), and folding for {}, [] and () blocks.
import { StreamLanguage, foldService } from "@codemirror/language";

const shapeKeywords = new Set([
  "service", "resource", "operation", "structure", "union", "list", "map", "set",
  "string", "blob", "boolean", "byte", "short", "integer", "long", "float", "double",
  "bigInteger", "bigDecimal", "timestamp", "document", "enum", "intEnum", "apply",
]);
const statementKeywords = new Set(["namespace", "use", "metadata"]);
const identChar = /[A-Za-z0-9_]/;

// Keywords are contextual, as in the highlighter: a shape keyword counts at the start of a line,
// and the word after it is a shape name. A text block ("""...""") can span lines.
export const smithyLanguage = StreamLanguage.define({
  name: "smithy",
  startState: () => ({ lineStart: true, expectName: false, expectMods: false, textBlock: false }),
  copyState: (s) => ({ ...s }),
  token(stream, state) {
    if (stream.sol()) {
      state.lineStart = true;
      state.expectName = false;
      state.expectMods = false;
    }
    if (state.textBlock) {
      if (stream.skipTo('"""')) {
        stream.pos += 3;
        state.textBlock = false;
      } else {
        stream.skipToEnd();
      }
      return "string";
    }
    if (stream.eatSpace() || stream.eat(",") || stream.eat("\r")) {
      return null;
    }
    const atStart = state.lineStart;
    state.lineStart = false;
    if (stream.match("///")) {
      stream.skipToEnd();
      return "docComment";
    }
    if (stream.match("//")) {
      stream.skipToEnd();
      return "lineComment";
    }
    if (stream.match('"""')) {
      if (stream.skipTo('"""')) {
        stream.pos += 3;
      } else {
        stream.skipToEnd();
        state.textBlock = true;
      }
      return "string";
    }
    if (stream.eat('"')) {
      let escaped = false;
      let ch;
      while ((ch = stream.next()) != null) {
        if (ch === '"' && !escaped) break;
        escaped = !escaped && ch === "\\";
      }
      return "string";
    }
    const ch = stream.peek();
    if ((ch === "@" || ch === "$") && identChar.test(stream.string.charAt(stream.pos + 1))) {
      stream.next();
      stream.match(/^[A-Za-z0-9_.#]+/);
      return ch === "@" ? "meta" : "keyword";
    }
    if (stream.match(/^-?\d[\d.]*(?:[eE][+-]?\d+)?/)) {
      return "number";
    }
    const word = stream.match(/^[A-Za-z0-9_]+/);
    if (word) {
      const text = word[0];
      // `list: String` and `string = "x"` name a member, not a shape.
      const rest = stream.string.slice(stream.pos);
      if (/^[ \t]*[:=]/.test(rest)) return null;
      if (atStart && shapeKeywords.has(text)) {
        state.expectName = true;
        return "keyword";
      }
      if (atStart && statementKeywords.has(text)) return "keyword";
      if (state.expectName) {
        state.expectName = false;
        state.expectMods = true;
        return "typeName";
      }
      if (state.expectMods && (text === "for" || text === "with")) return "keyword";
      if (text === "true" || text === "false" || text === "null") return "keyword";
      return null;
    }
    if (stream.next() === "{") {
      state.expectName = false;
      state.expectMods = false;
    }
    return null;
  },
  languageData: { commentTokens: { line: "//" } },
});

const opening = { "{": "}", "[": "]", "(": ")" };
const closing = new Set(["}", "]", ")"]);

// The farthest that a fold looks for the end of a block, in characters. A larger block does not fold,
// so a very large model stays fast.
const SCAN_LIMIT = 200000;

// The index after the string that starts at `i` in `text`, or text.length when it does not end.
function stringEnd(text, i) {
  let j = i + 1;
  while (j < text.length) {
    if (text[j] === "\\") j += 2;
    else if (text[j] === '"') return j + 1;
    else j += 1;
  }
  return text.length;
}

// The position of the bracket that closes the one at `open`, or -1.
function findClose(doc, open) {
  const end = Math.min(doc.length, open + 1 + SCAN_LIMIT);
  const text = doc.sliceString(open, end);
  const stack = [opening[text[0]]];
  let i = 1;
  while (i < text.length) {
    const c = text[i];
    if (c === "/" && text[i + 1] === "/") {
      const nl = text.indexOf("\n", i);
      if (nl < 0) return -1;
      i = nl + 1;
    } else if (c === '"' && text.startsWith('"""', i)) {
      const e = text.indexOf('"""', i + 3);
      if (e < 0) return -1;
      i = e + 3;
    } else if (c === '"') {
      i = stringEnd(text, i);
    } else if (opening[c]) {
      stack.push(opening[c]);
      i += 1;
    } else if (closing.has(c)) {
      if (stack.pop() !== c) return -1;
      if (stack.length === 0) return open + i;
      i += 1;
    } else {
      i += 1;
    }
  }
  return -1;
}

// Folds the last bracket of a line that the same line does not close.
export const bracketFolding = foldService.of((state, lineStart) => {
  const line = state.doc.lineAt(lineStart);
  const text = line.text;
  const open = [];
  let i = 0;
  while (i < text.length) {
    const c = text[i];
    if (c === "/" && text[i + 1] === "/") break;
    if (c === '"') {
      if (text.startsWith('"""', i)) return null;
      i = stringEnd(text, i);
      continue;
    }
    if (opening[c]) open.push(i);
    else if (closing.has(c)) open.pop();
    i += 1;
  }
  if (open.length === 0) return null;
  const from = line.from + open[open.length - 1];
  const to = findClose(state.doc, from);
  if (to < 0 || to <= line.to) return null;
  return { from: from + 1, to };
});
