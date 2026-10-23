// Review focus 1: a half-typed model gives diagnostics, never a stuck or dead Worker, and a result for
// old text never replaces the result for newer text. The tests use the short Order sample, so that
// every line is on screen for the DOM edits.
import { expect, lightpandaQuirk, test } from "./fixtures.js";
import { chooseSample, clearEditor, openPlayground, replaceInEditor, settled } from "./playground.js";
import { siteUrl } from "./site.js";

test.beforeEach(async ({ lightpanda: page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await chooseSample(page, "Order");
  await settled(page);
  await expect(page.locator(".pg-okbox")).toHaveText("✓ The model is valid. 1 shape.");
});

test.afterEach(async ({ lightpanda: page }) => {
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});

test("an unbalanced brace gives a diagnostic, and the Worker still answers", async ({ lightpanda: page }) => {
  await replaceInEditor(page, "structure Order {", "structure Order {{");
  await settled(page);
  await expect(page.locator(".pg-diag .pg-sev").first()).toHaveText("ERROR");
  await expect(page.locator(".pg-check")).toContainText("error");
  await replaceInEditor(page, "structure Order {{", "structure Order {");
  await settled(page);
  await expect(page.locator(".pg-okbox")).toHaveText("✓ The model is valid. 1 shape.");
});

test("a deleted $version gives a result, not a stopped check", async ({ lightpanda: page }) => {
  await replaceInEditor(page, '$version: "2"', "");
  await settled(page);
  await expect(page.locator(".pg-check")).not.toHaveText("Stopped");
  await expect(page.locator(".pg-okbox, .pg-diag").first()).toBeVisible();
});

test("an empty editor is a valid model with no shapes", async ({ lightpanda: page }) => {
  await clearEditor(page);
  await settled(page);
  await expect(page.locator(".pg-okbox")).toHaveText("✓ The model is valid. 0 shapes.");
  await expect(page.locator(".pg-cursor")).toHaveText("Ln 1, Col 1");
});

test("a result for old text never replaces the result for newer text", async ({ lightpanda: page }) => {
  // Record every state of the check from now on.
  await page.evaluate(() => {
    window.pgStates = [];
    const record = () => window.pgStates.push(document.querySelector(".pg-check")?.textContent ?? "");
    new MutationObserver(record).observe(document.querySelector(".pg-status"), {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
    });
  });
  // A burst of edits: each breaks or fixes the model. The last one fixes it.
  for (let i = 0; i < 4; i++) {
    await replaceInEditor(page, "quantity: Integer", "quantity: Intger");
    await page.waitForTimeout(i * 120);
    await replaceInEditor(page, "quantity: Intger", "quantity: Integer");
    if (i < 3) await page.waitForTimeout(i * 120);
  }
  const lastEdit = await page.evaluate(() => window.pgStates.length);
  await settled(page);
  await expect(page.locator(".pg-okbox")).toHaveText("✓ The model is valid. 1 shape.");
  await expect(page.locator("#pg-editor .cm-lintRange-error")).toHaveCount(0);
  // After the last edit, the previous result can show, marked "checking", until the newest answer
  // comes. Once it comes, no answer for older text replaces it.
  const after = await page.evaluate((n) => window.pgStates.slice(n), lastEdit);
  const answered = after.findIndex((state) => !state.includes("checking"));
  expect(answered).toBeGreaterThanOrEqual(0);
  expect(after.slice(answered).filter((state) => state !== "✓ valid")).toEqual([]);
});

test("right after a change, the result for the old text shows as checking", async ({ lightpanda: page }) => {
  await replaceInEditor(page, "quantity: Integer", "quantity: Intger");
  await settled(page);
  await expect(page.locator(".pg-check")).toHaveText("● 1 error");
  await replaceInEditor(page, "quantity: Intger", "quantity: Integer");
  // The page has the change when the row of the old result is stale. The wait of 250 ms before the
  // check has not ended, so no request runs yet: the status must still say that a check comes.
  await expect(page.locator(".pg-diag-stale")).toHaveCount(1);
  expect(await page.textContent(".pg-check")).toBe("● 1 error · checking");
  await settled(page);
  await expect(page.locator(".pg-check")).toHaveText("✓ valid");
});
