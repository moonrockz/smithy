// Steps on the playground page that the tests share.
import { readFileSync } from "node:fs";
import { deflateRawSync, inflateRawSync } from "node:zlib";
import { expect } from "./fixtures.js";
import { siteUrl } from "./site.js";

// The status bar has data-waiting="false" when the newest check has its answer.
export async function settled(page) {
  await expect(page.locator(".pg-status")).toHaveAttribute("data-waiting", "false", { timeout: 15_000 });
}

export async function openPlayground(page, url) {
  await page.goto(url);
  // The workbench is mounted when the editor is in it.
  await expect(page.locator("#pg-editor .cm-content")).toBeVisible();
  await settled(page);
}

// Change the text of the editor as a native text input does: in the DOM of the editor. CodeMirror
// reads the change back. Lightpanda sends no key input to the editor, so the Lightpanda tests edit
// this way. Only the lines that the editor shows can change, and `from` must be in one line.
export async function replaceInEditor(page, from, to) {
  const done = await page.evaluate(
    ([from, to]) => {
      for (const line of document.querySelectorAll("#pg-editor .cm-content .cm-line")) {
        if (line.textContent.includes(from)) {
          line.textContent = line.textContent.replace(from, to);
          return true;
        }
      }
      return false;
    },
    [from, to],
  );
  expect(done, `the editor shows "${from}"`).toBe(true);
}

// Remove every line of the editor. All lines must be on screen (a short sample).
export async function clearEditor(page) {
  await page.evaluate(() => {
    const lines = [...document.querySelectorAll("#pg-editor .cm-content .cm-line")];
    lines.slice(1).forEach((line) => line.remove());
    lines[0].textContent = "";
  });
}

// Select a sample of the picker by its title.
export async function chooseSample(page, title) {
  await page.selectOption("#pg-example", { label: title });
}

// Open the Transcript tab, after a sample of the model picker when `sample` is given. Lightpanda has no
// layout, so the tab is selected with a click event.
export async function openTranscript(page, sample) {
  await openPlayground(page, siteUrl("playground/"));
  if (sample) {
    await chooseSample(page, sample);
    await settled(page);
  }
  await page.locator(".pg-tab", { hasText: "Transcript" }).dispatchEvent("click");
  await expect(page.locator(".pg-trpanel")).not.toHaveClass(/pg-off/);
}

// The fragment of a share link for a state, as the playground writes it: `v1.` and the base64url text
// of the raw deflate of the JSON. Used for states that the page cannot make itself, such as a model
// that unpacks to a large size.
export function shareFragment(state) {
  return "v1." + deflateRawSync(Buffer.from(JSON.stringify(state))).toString("base64url");
}

// The state in a share fragment.
export function stateOfFragment(fragment) {
  return JSON.parse(inflateRawSync(Buffer.from(fragment.slice("v1.".length), "base64url")).toString("utf8"));
}

// The text of a file of the repository.
export function repoFile(path) {
  return readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8");
}

// The minimal state of a link: the model, and the settings of the Validate tab.
export function linkState(overrides = {}) {
  return {
    model: repoFile("examples/json-rpc/peers.smithy"),
    transcript: "",
    tab: "ValidateTab",
    output: "JsonAst",
    protocol: "example.peers#EchoChat",
    format: "Markdown",
    complete: false,
    ...overrides,
  };
}

// The page has opened a link that it could not read: it shows the reason and the default example.
export async function expectDefaultWithMessage(page, ...texts) {
  await expect(page.locator("#pg-editor .cm-content")).toBeVisible();
  await settled(page);
  const status = page.locator("#pg-share-status");
  await expect(status).toContainText("I could not open this link.");
  await expect(status).toContainText("I opened the default example instead.");
  for (const text of texts) {
    await expect(status).toContainText(text);
  }
  await expect(page.locator("#pg-example")).toHaveValue("1");
  await expect(page.locator("#pg-editor .cm-content")).toContainText("structure");
  await expect(page.locator(".pg-check")).toContainText("1 error");
}
