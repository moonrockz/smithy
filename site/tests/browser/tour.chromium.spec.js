// The first tour lesson on Chromium: the output, a changed line, a stored edit, Reset and a model with a
// finding. Key input needs Chromium (README.md).
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
  // The output changed back, so its name line is marked as changed against the edited output.
  expect(await outputText(page)).not.toContain("Welcome");
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
