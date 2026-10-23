// Keyboard input into the editor. Lightpanda sends no key input to CodeMirror (README.md).
import { expect, test } from "./fixtures.js";
import { openPlayground, settled } from "./playground.js";
import { siteUrl } from "./site.js";

test("typing fixes the model, and the status bar follows the cursor", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await page.locator("button.pg-diag").click();
  await expect(page.locator(".pg-cursor")).toHaveText("Ln 46, Col 31");
  await expect(page.locator("#pg-editor .cm-content")).toBeFocused();
  await page.keyboard.press("End");
  // The line is `structure PostMessageOutput { count: Intger }`: 45 characters.
  await expect(page.locator(".pg-cursor")).toHaveText("Ln 46, Col 46");
  for (let i = 0; i < 2; i++) await page.keyboard.press("ArrowLeft");
  for (let i = 0; i < 3; i++) await page.keyboard.press("Backspace");
  await page.keyboard.type("eger");
  await expect(page.locator(".pg-cursor")).toHaveText("Ln 46, Col 45");
  await settled(page);
  await expect(page.locator(".pg-check")).toHaveText("✓ valid");
  await expect(page.locator(".pg-okbox")).toHaveText(/^✓ The model is valid\. \d+ shapes\.$/);
  expect(page.errors).toEqual([]);
});

test("Ctrl-Shift-[ folds a block and Ctrl-Shift-] unfolds it", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  // Line 21 is `service ChatServer {`.
  await page.locator("#pg-editor .cm-line", { hasText: "service ChatServer {" }).click();
  await page.keyboard.press("Control+Shift+BracketLeft");
  await expect(page.locator("#pg-editor .cm-foldPlaceholder")).toHaveCount(1);
  await expect(page.locator("#pg-editor .cm-content")).not.toContainText("operations: [Echo, PostMessage]");
  await page.keyboard.press("Control+Shift+BracketRight");
  await expect(page.locator("#pg-editor .cm-foldPlaceholder")).toHaveCount(0);
  // The gutter folds too.
  await page.locator("#pg-editor .cm-foldGutter .cm-gutterElement", { hasText: "▾" }).first().click();
  await expect(page.locator("#pg-editor .cm-foldPlaceholder")).toHaveCount(1);
  expect(page.errors).toEqual([]);
});

test("Smithy tokens have the kinds of the site highlighter", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  const color = (text) =>
    page.locator("#pg-editor .cm-line span", { hasText: new RegExp(`^${text}$`) }).first().evaluate((e) => getComputedStyle(e).color);
  expect(await color("structure")).toBe("rgb(255, 123, 114)"); // keyword
  expect(await color("EchoChat")).toBe("rgb(210, 168, 255)"); // shape name
  expect(await color("@jsonRpcProtocol")).toBe("rgb(255, 166, 87)"); // trait
  expect(await color('"1.0"')).toBe("rgb(165, 214, 255)"); // string
});
