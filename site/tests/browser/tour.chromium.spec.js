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

test("Undo after a file tab switch never moves the text of one file into another", async ({ page }) => {
  await page.goto(siteUrl("tour/shape-ids/"));
  await expect(page.locator("#tour-editor .cm-content")).toBeVisible();
  await settled(page);
  const editor = page.locator("#tour-editor .cm-content");
  const modelTab = page.getByRole("tab", { name: "model.smithy" });
  const commonTab = page.getByRole("tab", { name: "common.smithy" });

  await modelTab.click();
  await expect(editor).toContainText("structure Forecast");
  const modelStart = await editorText(page);
  await commonTab.click();
  await expect(editor).toContainText("CityName");
  const commonStart = await editorText(page);
  expect(commonStart).not.toEqual(modelStart);

  // Type in model.smithy, then switch to common.smithy and back.
  await modelTab.click();
  await expect(editor).toContainText("structure Forecast");
  await editor.click();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("// edited");
  await settled(page);
  const modelEdited = await editorText(page);
  expect(modelEdited).toContain("// edited");
  await commonTab.click();
  await expect(editor).not.toContainText("// edited");
  expect(await editorText(page)).toEqual(commonStart);
  await modelTab.click();
  await expect(editor).toContainText("// edited");

  // Undo until nothing changes: model.smithy goes back to its own start text, never to common.smithy.
  await editor.click();
  let before = "";
  for (let i = 0; i < 30; i++) {
    const text = await editorText(page);
    if (text === before) break;
    before = text;
    await page.keyboard.press("ControlOrMeta+z");
    await settled(page);
  }
  const modelUndone = await editorText(page);
  expect(modelUndone).toEqual(modelStart);
  expect(modelUndone).not.toContain("CityName {");

  // common.smithy is unchanged, and Undo there has nothing to undo.
  await commonTab.click();
  await expect(editor).toContainText("CityName");
  expect(await editorText(page)).toEqual(commonStart);
  await editor.click();
  await page.keyboard.press("ControlOrMeta+z");
  expect(await editorText(page)).toEqual(commonStart);

  // A reload shows the stored text of each file.
  await page.reload();
  await expect(editor).toBeVisible();
  await settled(page);
  await commonTab.click();
  await expect(editor).toContainText("CityName");
  expect(await editorText(page)).toEqual(commonStart);
  await modelTab.click();
  await expect(editor).toContainText("structure Forecast");
  expect(await editorText(page)).toEqual(modelStart);
  expect(page.errors).toEqual([]);
});

// The two tabs of the first include block of the lesson: the CLI and the MoonBit block.
function includeTabs(page) {
  const group = page.locator(".ms-tabs").first();
  return {
    cli: group.locator(".ms-tab-panel").nth(0),
    api: group.locator(".ms-tab-panel").nth(1),
    label: (name) => group.locator(".ms-tab-label", { hasText: name }),
  };
}

async function expectCliShown({ cli, api }) {
  await expect(cli).toBeVisible();
  await expect(cli).toContainText("$ smithy convert --to json greeting.smithy");
  await expect(api).toBeHidden();
}

async function expectApiShown({ cli, api }) {
  await expect(api).toBeVisible();
  await expect(api).toContainText("@smithy.Loader::new()");
  await expect(cli).toBeHidden();
}

test("the include tabs switch without a reload", async ({ page }) => {
  await openLesson(page);
  const tabs = includeTabs(page);
  await expectCliShown(tabs);

  await tabs.label("MoonBit").click();
  await expectApiShown(tabs);

  // The arrow keys move between the tabs, as for any radio group.
  await page.locator("#tabs-1-2").focus();
  await page.keyboard.press("ArrowLeft");
  await expectCliShown(tabs);
  await expect(page.locator("#tabs-1-1")).toBeChecked();
  expect(page.errors).toEqual([]);
});

test("the selected include tab stays after an edit and its answer", async ({ page }) => {
  await openLesson(page);
  const tabs = includeTabs(page);
  await tabs.label("MoonBit").click();
  await expectApiShown(tabs);

  // Delete the namespace line: the editor, the findings and the output all re-render.
  await page.locator("#tour-editor .cm-content").click();
  await page.keyboard.press("ControlOrMeta+Home");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Shift+End");
  await page.keyboard.press("Backspace");
  await settled(page);
  await page.getByRole("tab", { name: /Findings/ }).click();
  await expect(page.locator(".tour-finding")).toHaveCount(1);
  await expect(page.locator("#tabs-1-2")).toBeChecked();
  await expectApiShown(tabs);
  expect(page.errors).toEqual([]);
});

test("the include tabs switch with JavaScript off", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(lessonUrl);
  const tabs = includeTabs(page);
  await expectCliShown(tabs);
  await tabs.label("MoonBit").click();
  await expectApiShown(tabs);
  await context.close();
});
