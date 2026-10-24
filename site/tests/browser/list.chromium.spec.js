// The Validate list: its text can be selected and copied, names in a message show as code, the Go
// button works from the keyboard, and "Group repeats" keeps its choice. Runs on Chromium: it needs
// mouse drags, key input and the clipboard (README.md).
import { expect, test } from "./fixtures.js";
import { openPlayground, settled } from "./playground.js";
import { scaleModel } from "./scale-model.js";
import { siteUrl } from "./site.js";

const message =
  "I could not resolve shape example.peers#Intger, referenced by example.peers#PostMessageOutput$count.";

test("the text of a row can be selected and copied, and the drag does not move the cursor", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await openPlayground(page, siteUrl("playground/"));
  const row = page.locator(".pg-diag-go");
  await expect(row.locator(".pg-msg")).toHaveText(message);
  const cursor = await page.locator(".pg-cursor").textContent();

  // A drag along the first line of the message selects its text, as in any page. The message can
  // wrap, so the drag keeps to the first line and not to the gap between lines.
  const box = await row.locator(".pg-msg").boundingBox();
  await page.mouse.move(box.x + 1, box.y + 8);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width - 1, box.y + 8, { steps: 10 });
  await page.mouse.up();
  const selected = await page.evaluate(() => window.getSelection().toString());
  expect(selected.length).toBeGreaterThan(20);
  expect(message).toContain(selected.trim());
  await expect(page.locator(".pg-cursor")).toHaveText(cursor);
  await page.keyboard.press("ControlOrMeta+c");
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(selected);

  // A click without a drag moves the cursor to the place of the diagnostic.
  await row.locator(".pg-loc").click();
  await expect(page.locator(".pg-cursor")).toHaveText("Ln 46, Col 31");
  expect(page.errors).toEqual([]);
});

test("the shape IDs of a message show as code", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await expect(page.locator(".pg-diag .pg-msg .pg-ref")).toHaveText([
    "example.peers#Intger",
    "example.peers#PostMessageOutput$count",
  ]);
  const style = await page
    .locator(".pg-diag .pg-msg .pg-ref")
    .first()
    .evaluate((el) => getComputedStyle(el).fontFamily);
  const text = await page.locator(".pg-diag .pg-msg").evaluate((el) => getComputedStyle(el).fontFamily);
  expect(style).not.toBe(text);
});

test("Go moves the cursor from the keyboard", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await page.locator(".pg-go").focus();
  await expect(page.locator(".pg-go")).toHaveAccessibleName("Go to line 46");
  await page.keyboard.press("Enter");
  await expect(page.locator(".pg-cursor")).toHaveText("Ln 46, Col 31");
  await expect(page.locator("#pg-editor .cm-content")).toBeFocused();
});

test("Group repeats is on at first, and the browser keeps the choice", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  const button = page.locator("#pg-group");
  await expect(button).toHaveAttribute("aria-pressed", "true");
  await button.click();
  await expect(button).toHaveAttribute("aria-pressed", "false");
  await page.reload();
  await openPlayground(page, siteUrl("playground/"));
  await expect(button).toHaveAttribute("aria-pressed", "false");
  await button.click();
  await expect(button).toHaveAttribute("aria-pressed", "true");
  await page.reload();
  await openPlayground(page, siteUrl("playground/"));
  await expect(button).toHaveAttribute("aria-pressed", "true");
});

test("opening the repeats of a group does not move the cursor", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await openPlayground(page, siteUrl("playground/"));
  await page.evaluate((text) => navigator.clipboard.writeText(text), scaleModel(30));
  await page.locator("#pg-editor .cm-content").click();
  await page.keyboard.press("ControlOrMeta+a");
  await page.keyboard.press("ControlOrMeta+v");
  await settled(page);
  // The paste leaves the cursor at the end of the model, far from line 9 of the group.
  await expect(page.locator(".pg-cursor")).toHaveText(/^Ln \d{3}, Col 1$/);
  const cursor = await page.locator(".pg-cursor").textContent();
  const group = page.locator(".pg-diag", { has: page.locator(".pg-repeat") });
  await expect(group.locator(".pg-repeat")).toHaveText("×3");
  const summary = group.locator(".pg-repeats summary");
  await expect(summary).toHaveText("2 more messages for this place");
  await summary.click();
  await expect(group.locator(".pg-repeat-list li")).toHaveCount(2);
  await expect(page.locator(".pg-cursor")).toHaveText(cursor);
  await expect(summary).toBeFocused();
  // From the keyboard, Enter on the summary closes the group and keeps the focus there.
  await page.keyboard.press("Enter");
  await expect(group.locator(".pg-repeats")).not.toHaveAttribute("open", "");
  await expect(summary).toBeFocused();
});
