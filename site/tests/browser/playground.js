// Steps on the playground page that the tests share.
import { expect } from "./fixtures.js";

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
