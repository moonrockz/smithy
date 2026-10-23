// The editors of the playground. The MoonBit script of the page (site/playground/ui) calls these
// functions through `globalThis.smithyEditors`; each editor has the id of the element it is in.
import { Compartment, EditorState } from "@codemirror/state";
import {
  EditorView, drawSelection, highlightActiveLine, highlightActiveLineGutter, keymap, lineNumbers,
} from "@codemirror/view";
import {
  HighlightStyle, bracketMatching, foldCode, foldGutter, foldKeymap, indentOnInput, syntaxHighlighting, unfoldCode,
} from "@codemirror/language";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { highlightSelectionMatches, searchKeymap } from "@codemirror/search";
import { lintGutter, lintKeymap, setDiagnostics } from "@codemirror/lint";
import { json } from "@codemirror/lang-json";
import { markdown } from "@codemirror/lang-markdown";
import { tags } from "@lezer/highlight";
import { bracketFolding, smithyLanguage } from "./smithy.js";

// A dark editor in both site themes, as the mockup.
const theme = EditorView.theme(
  {
    "&": { height: "100%", backgroundColor: "var(--code-bg)", color: "#e6edf3", fontSize: "13px" },
    ".cm-scroller": { fontFamily: "var(--mono)", lineHeight: "1.55" },
    ".cm-content": { caretColor: "#e6edf3" },
    ".cm-cursor, .cm-dropCursor": { borderLeftColor: "#e6edf3" },
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection": {
      backgroundColor: "#264f78",
    },
    ".cm-gutters": { backgroundColor: "var(--code-bg)", color: "#59606b", borderRight: "1px solid #22262e" },
    ".cm-activeLine": { backgroundColor: "#ffffff08" },
    ".cm-activeLineGutter": { backgroundColor: "#ffffff0d", color: "#9ba3af" },
    ".cm-foldGutter .cm-gutterElement": { color: "#7d8590", cursor: "pointer" },
    ".cm-foldPlaceholder": { backgroundColor: "#a5b4fc", color: "#0d1117", border: "none", padding: "0 4px" },
    ".cm-lintRange-error": {
      backgroundImage: "none",
      textDecoration: "wavy underline #f85149",
      textUnderlineOffset: "3px",
    },
    ".cm-lintRange-warning": {
      backgroundImage: "none",
      textDecoration: "wavy underline #d29922",
      textUnderlineOffset: "3px",
    },
    ".cm-lint-marker": { width: "1em", height: "1em", content: "none" },
    ".cm-lint-marker-error": { backgroundImage: "none" },
    ".cm-lint-marker-error::before": { content: '"●"', color: "#f85149", fontSize: "11px" },
    ".cm-lint-marker-warning": { backgroundImage: "none" },
    ".cm-lint-marker-warning::before": { content: '"●"', color: "#d29922", fontSize: "11px" },
    ".cm-matchingBracket": { backgroundColor: "#3b4252", outline: "none" },
    ".cm-tooltip": { backgroundColor: "#161b22", color: "#e6edf3", border: "1px solid #30363d" },
    ".cm-panels": { backgroundColor: "#161b22", color: "#e6edf3" },
  },
  { dark: true },
);

const highlight = HighlightStyle.define([
  { tag: tags.keyword, color: "#ff7b72" },
  { tag: [tags.typeName, tags.definition(tags.variableName)], color: "#d2a8ff" },
  { tag: tags.meta, color: "#ffa657" },
  { tag: tags.string, color: "#a5d6ff" },
  { tag: [tags.lineComment, tags.comment], color: "#8b949e", fontStyle: "italic" },
  { tag: tags.docComment, color: "#8b949e", fontStyle: "italic", fontWeight: "600" },
  { tag: [tags.number, tags.bool, tags.null], color: "#79c0ff" },
  { tag: tags.propertyName, color: "#7ee787" },
  { tag: [tags.heading, tags.strong], color: "#d2a8ff", fontWeight: "700" },
  { tag: tags.monospace, color: "#a5d6ff" },
]);

const languages = {
  smithy: () => [smithyLanguage, bracketFolding],
  json: () => json(),
  markdown: () => markdown(),
};

const views = new Map();
// The compartment of the language of each editor, so that the output editor can change language.
const languageSlots = new Map();

// Line and column (both from 1) to a document position, kept inside the document.
function position(doc, line, column) {
  const l = doc.line(Math.min(Math.max(line, 1), doc.lines));
  return l.from + Math.min(Math.max(column - 1, 0), l.length);
}

const severities = { ERROR: "error", DANGER: "error", WARNING: "warning" };

const editors = {
  // Make an editor in the element `id`. `onChange()` runs after changes of the text, and
  // `onCursor(line, column)` after moves of the cursor.
  create(id, text, language, readOnly, onChange, onCursor) {
    const parent = document.getElementById(id);
    if (!parent || views.has(id)) return;
    // The page hears of changes after the update of the editor ends, so that nothing that it does
    // in answer can update the editor during an update. One report covers a burst of changes.
    const pending = { changed: false, cursor: null, timer: 0 };
    const report = () => {
      const { changed, cursor } = pending;
      pending.changed = false;
      pending.cursor = null;
      pending.timer = 0;
      if (changed) onChange();
      if (cursor) onCursor(cursor[0], cursor[1]);
    };
    const slot = new Compartment();
    const view = new EditorView({
      parent,
      state: EditorState.create({
        doc: text,
        extensions: [
          lineNumbers(),
          foldGutter({ openText: "▾", closedText: "▸" }),
          lintGutter(),
          highlightActiveLineGutter(),
          history(),
          drawSelection(),
          indentOnInput(),
          bracketMatching(),
          highlightActiveLine(),
          highlightSelectionMatches(),
          // Ctrl-Shift-[ and ] fold on every platform; foldKeymap gives macOS Cmd-Alt-[ and ] instead.
          keymap.of([
            { key: "Ctrl-Shift-[", run: foldCode },
            { key: "Ctrl-Shift-]", run: unfoldCode },
            ...defaultKeymap,
            ...historyKeymap,
            ...foldKeymap,
            ...searchKeymap,
            ...lintKeymap,
          ]),
          slot.of((languages[language] ?? (() => []))()),
          syntaxHighlighting(highlight),
          theme,
          EditorState.readOnly.of(readOnly),
          EditorView.contentAttributes.of({ "aria-label": `${id} editor` }),
          EditorView.updateListener.of((update) => {
            if (update.docChanged) pending.changed = true;
            if (update.docChanged || update.selectionSet) {
              const head = update.state.selection.main.head;
              const line = update.state.doc.lineAt(head);
              pending.cursor = [line.number, head - line.from + 1];
            }
            if ((pending.changed || pending.cursor) && !pending.timer) {
              pending.timer = setTimeout(report, 0);
            }
          }),
        ],
      }),
    });
    views.set(id, view);
    languageSlots.set(id, slot);
  },
  text(id) {
    return views.get(id)?.state.doc.toString() ?? "";
  },
  load(id, text) {
    const view = views.get(id);
    if (!view) return;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: 0 } });
  },
  // Replace the text and the language together. A language that the editor does not know is plain text.
  show(id, text, language) {
    const view = views.get(id);
    if (!view) return;
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: text },
      selection: { anchor: 0 },
      effects: languageSlots.get(id).reconfigure((languages[language] ?? (() => []))()),
      scrollIntoView: true,
    });
  },
  // `items` is a JSON array of diagnostics: severity, code, message and the 1-based start and end.
  // A diagnostic with line 0 has no place in the text and gets no mark.
  mark(id, items) {
    const view = views.get(id);
    if (!view) return;
    const doc = view.state.doc;
    const diagnostics = JSON.parse(items)
      .filter((d) => d.start_line > 0)
      .map((d) => {
        const from = position(doc, d.start_line, d.start_column);
        const end = d.end_line > 0 ? position(doc, d.end_line, d.end_column) : from;
        return {
          from,
          to: Math.max(from, end),
          severity: severities[d.severity] ?? "info",
          source: d.code,
          message: d.message,
        };
      });
    view.dispatch(setDiagnostics(view.state, diagnostics));
  },
  goTo(id, line, column) {
    const view = views.get(id);
    if (!view) return;
    const pos = position(view.state.doc, line, column);
    view.dispatch({ selection: { anchor: pos }, scrollIntoView: true });
    view.focus();
  },
};

globalThis.smithyEditors = editors;
