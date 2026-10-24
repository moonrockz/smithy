// The first tour lesson on Chromium: the output, a changed line, a stored edit, Reset, a model with a
// finding and the expand buttons of the two right-hand panes. Key input needs Chromium (README.md).
import { expect, test } from "./fixtures.js";
import { siteUrl } from "./site.js";

const lessonUrl = siteUrl("tour/hello-smithy/");

// The check has its answer when the busy mark is gone.
async function settled(page) {
  await expect(page.locator(".tour-busy")).toHaveCount(0, { timeout: 15_000 });
}

async function openLesson(page) {
  await page.goto(lessonUrl);
  await expect(page.locator("#tour-editor .cm-content")).toBeVisible();
  await expect(page.locator("#tour-output .cm-content")).toBeAttached();
  await settled(page);
}

const editorText = (page) => page.locator("#tour-editor .cm-content").innerText();
const outputText = (page) => page.locator("#tour-output .cm-content").innerText();

test("the lesson shows its output, marks a changed line, keeps an edit and resets", async ({ page }) => {
  await openLesson(page);

  // No findings; the JSON AST tab shows the model.
  await page.getByRole("tab", { name: /Findings/ }).click();
  await expect(page.getByText("The model has no findings.")).toBeVisible();
  await page.getByRole("tab", { name: /JSON AST/ }).click();
  await expect(page.locator("#tour-output .cm-content")).toContainText("example#Greeting");
  await expect(page.locator("#tour-output .tour-changed")).toHaveCount(0);

  // Replace the structure name.
  await page.locator("#tour-editor .cm-content").getByText("Greeting").dblclick();
  await page.keyboard.type("Welcome");
  await settled(page);
  const output = page.locator("#tour-output .cm-content");
  await expect(output).toContainText("example#Welcome");
  await expect(output).not.toContainText("example#Greeting");
  // Exactly the lines that hold the new name have the class.
  const lines = await output.locator(".cm-line").allInnerTexts();
  const expected = lines.filter((line) => line.includes("Welcome"));
  expect(expected.length).toBeGreaterThan(0);
  await expect(page.locator("#tour-output .cm-line.tour-changed")).toHaveCount(expected.length);
  expect(await page.locator("#tour-output .cm-line.tour-changed").allInnerTexts()).toEqual(expected);

  // The edit stays after a reload.
  await page.reload();
  await expect(page.locator("#tour-editor .cm-content")).toContainText("structure Welcome");
  await settled(page);
  await page.getByRole("tab", { name: /JSON AST/ }).click();
  await expect(page.locator("#tour-output .cm-content")).toContainText("example#Welcome");

  // Reset gives the starting model back.
  await page.getByRole("button", { name: "Reset", exact: true }).click();
  await expect(page.locator("#tour-editor .cm-content")).toContainText("structure Greeting");
  await settled(page);
  expect(await editorText(page)).not.toContain("Welcome");
  await expect(page.locator("#tour-output .cm-content")).toContainText("example#Greeting");
  expect(await outputText(page)).not.toContain("Welcome");
  // The output changed back, so exactly the lines that hold the old name are marked as changed against the
  // edited output.
  const resetLines = await output.locator(".cm-line").allInnerTexts();
  const changedBack = resetLines.filter((line) => line.includes("Greeting"));
  expect(changedBack.length).toBeGreaterThan(0);
  await expect(page.locator("#tour-output .cm-line.tour-changed")).toHaveCount(changedBack.length);
  expect(await page.locator("#tour-output .cm-line.tour-changed").allInnerTexts()).toEqual(changedBack);
  expect(page.errors).toEqual([]);
});

test("a model with no namespace shows the finding of the lesson", async ({ page }) => {
  await openLesson(page);
  // The namespace statement is on the third line.
  await page.locator("#tour-editor .cm-content").click();
  await page.keyboard.press("ControlOrMeta+Home");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Shift+End");
  await page.keyboard.press("Backspace");
  await settled(page);
  expect(await editorText(page)).not.toContain("namespace");

  await page.getByRole("tab", { name: /Findings/ }).click();
  const finding = page.locator(".tour-finding");
  await expect(finding).toHaveCount(1);
  await expect(finding).toContainText("ERROR");
  await expect(finding).toContainText("Model");
  await expect(finding).toContainText("I found `structure` but no `namespace` statement before it");
  // The output did not run: the tab says why, and nothing is marked.
  await page.getByRole("tab", { name: /JSON AST/ }).click();
  await expect(page.locator(".tour-err")).toBeVisible();
  await expect(page.locator("#tour-output .tour-changed")).toHaveCount(0);
  expect(page.errors).toEqual([]);
});

const height = async (locator) => (await locator.boundingBox())?.height ?? 0;

test("a pane expands to the right column and the split view comes back", async ({ page }) => {
  await openLesson(page);
  const edit = page.locator(".tour-pane.tour-edit");
  const out = page.locator(".tour-pane.tour-out");
  const editor = page.locator("#tour-editor");
  const output = page.locator("#tour-output");
  const panes = page.locator(".tour-panes");
  const splitEditor = await height(editor);
  expect(splitEditor).toBeGreaterThan(50);

  // Change the model: replace the structure name.
  await page.locator("#tour-editor .cm-content").getByText("Greeting").dblclick();
  await page.keyboard.type("Welcome");
  await settled(page);
  await expect(page.locator("#tour-editor .cm-content")).toContainText("structure Welcome");

  // The output fills the column; the editor pane stays in the DOM, hidden.
  const expandOutput = page.getByRole("button", { name: "Expand the output" });
  await expect(expandOutput).toHaveAttribute("aria-pressed", "false");
  await expandOutput.click();
  await expect(panes).toHaveClass(/tour-output-only/);
  await expect(edit).toBeHidden();
  await expect(edit).toHaveCount(1);
  await expect(out).toBeVisible();
  const columnHeight = await height(panes);
  expect(await height(out)).toBeGreaterThan(columnHeight - 2);
  const back = page.getByRole("button", { name: "Expand the output" });
  await expect(back).toHaveAttribute("aria-pressed", "true");
  await expect(back).toHaveAttribute("title", "Show both panes");
  await expect(back).toHaveCount(1);
  await page.screenshot({ path: "../.dev/out/tour-expanded-output.png" });

  // Both panes come back; the editor keeps the typed text and its undo history.
  await back.click();
  await expect(panes).not.toHaveClass(/tour-(editor|output)-only/);
  await expect(edit).toBeVisible();
  await expect(out).toBeVisible();
  await expect(page.locator("#tour-editor .cm-content")).toContainText("structure Welcome");
  await page.locator("#tour-editor .cm-content").click();
  await page.keyboard.press("ControlOrMeta+z");
  await expect(page.locator("#tour-editor .cm-content")).not.toContainText("Welcome");
  await expect(page.locator("#tour-editor .cm-content")).toContainText("structure Greeting");
  await settled(page);

  // The editor fills the column; its element is taller, and not blank.
  await page.getByRole("button", { name: "Expand the editor" }).click();
  await expect(panes).toHaveClass(/tour-editor-only/);
  await expect(out).toBeHidden();
  await expect(out).toHaveCount(1);
  await expect(output).toHaveCount(1);
  await expect(edit).toBeVisible();
  await expect.poll(() => height(editor)).toBeGreaterThan(splitEditor + 20);
  // CodeMirror drew into the new size: its scroller fills the element.
  await expect.poll(async () => (await height(page.locator("#tour-editor .cm-scroller"))) >= (await height(editor)) - 2).toBe(true);
  await expect(page.locator("#tour-editor .cm-content")).toContainText("structure Greeting");
  await page.screenshot({ path: "../.dev/out/tour-expanded-editor.png" });

  // The keyboard: Tab from the last file tab reaches the button; Space presses it.
  await page.getByRole("button", { name: "Expand the editor" }).click();
  await expect(panes).not.toHaveClass(/tour-(editor|output)-only/);
  await page.getByRole("tab", { name: "model.smithy" }).focus();
  await page.keyboard.press("Tab");
  await expect(page.getByRole("button", { name: "Expand the editor" })).toBeFocused();
  await page.keyboard.press("Space");
  await expect(panes).toHaveClass(/tour-editor-only/);
  await expect(page.getByRole("button", { name: "Expand the editor" })).toBeFocused();
  await expect(page.getByRole("button", { name: "Expand the editor" })).toHaveAttribute("aria-pressed", "true");
  await page.keyboard.press("Space");
  await expect(panes).not.toHaveClass(/tour-(editor|output)-only/);
  expect(page.errors).toEqual([]);
});

test("on a phone the expanded output fills the shared area and the editor pane is hidden", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 800 });
  await openLesson(page);
  const edit = page.locator(".tour-pane.tour-edit");
  const out = page.locator(".tour-pane.tour-out");
  const panes = page.locator(".tour-panes");
  const splitHeight = await height(panes);
  const button = page.getByRole("button", { name: "Expand the output" });
  await button.scrollIntoViewIfNeeded();
  await button.click();
  await expect(panes).toHaveClass(/tour-output-only/);
  await expect(edit).toBeHidden();
  await expect(edit).toHaveCount(1);
  await expect(out).toBeVisible();
  // The output takes the height of the viewport that the two panes shared.
  await expect.poll(() => height(out)).toBeGreaterThan(800 - 200);
  expect(await height(panes)).toBeGreaterThan(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await button.click();
  await expect(panes).not.toHaveClass(/tour-(editor|output)-only/);
  await expect(edit).toBeVisible();
  await expect(out).toBeVisible();
  expect(await height(panes)).toBeGreaterThan(splitHeight - 2);
  expect(page.errors).toEqual([]);
});

test("in dark mode the expand button shows against its background", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await openLesson(page);
  const button = page.getByRole("button", { name: "Expand the editor" });
  await expect(button).toBeVisible();
  const [color, background] = await button.evaluate((el) => {
    const style = getComputedStyle(el);
    return [style.color, style.backgroundColor];
  });
  expect(color).not.toEqual(background);
  expect(page.errors).toEqual([]);
});
