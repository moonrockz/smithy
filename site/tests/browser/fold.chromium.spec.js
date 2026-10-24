// Folded controls: the code view of the Transform and Transcript tabs starts on the same pixel row as
// the model editor, the status bars mirror each other, Run, Step and Run all stay in the tab row, the
// browser keeps the folds, and a notice that needs the reader opens the controls again. Runs on
// Chromium: it measures the layout (README.md).
import { expect, test } from "./fixtures.js";
import { chooseSample, openPlayground, settled } from "./playground.js";
import { siteUrl } from "./site.js";

const valid = "JSON-RPC chat protocol";

async function top(page, editor) {
  return (await page.locator(`${editor} .cm-line`).first().boundingBox()).y;
}

test("a folded Transform tab lines its output up with the model, and Run stays in the tab row", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await openPlayground(page, siteUrl("playground/"));
  await chooseSample(page, valid);
  await expect(page.locator(".pg-check")).toHaveText("✓ valid", { timeout: 15_000 });
  await page.getByRole("tab", { name: "Transform" }).click();
  const fold = page.locator("#pg-fold");
  await expect(fold).toHaveAttribute("aria-expanded", "true");
  await expect(page.locator("#pg-run-folded")).toHaveCount(0);
  await fold.click();
  await expect(fold).toHaveAttribute("aria-expanded", "false");
  await expect(page.locator("#pg-output-kind")).toBeHidden();
  await expect(page.locator(".pg-cli")).toBeHidden();
  await page.locator("#pg-run-folded").click();
  await expect(page.locator("#pg-output .cm-line").first()).toHaveText("{", { timeout: 15_000 });
  expect(await top(page, "#pg-output")).toBe(await top(page, "#pg-editor"));
  // The status bars have the same place and height.
  const left = await page.locator(".pg-status").boundingBox();
  const right = await page.locator(".pg-rstatus").boundingBox();
  expect(right.y).toBe(left.y);
  expect(right.height).toBe(left.height);
  await expect(page.locator(".pg-rstatus")).toHaveText("JSON AST · model.json");
  // Open again: the controls come back.
  await fold.click();
  await expect(page.locator("#pg-output-kind")).toBeVisible();
  expect(await top(page, "#pg-output")).toBeGreaterThan(await top(page, "#pg-editor"));
  expect(page.errors).toEqual([]);
});

test("a folded Transcript tab lines its editor up with the model, and Step and Run all stay", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await openPlayground(page, siteUrl("playground/"));
  await chooseSample(page, valid);
  await expect(page.locator(".pg-check")).toHaveText("✓ valid", { timeout: 15_000 });
  await page.getByRole("tab", { name: "Transcript" }).click();
  await page.locator("#pg-fold").click();
  await expect(page.locator("#pg-transcript-sample")).toBeHidden();
  expect(await top(page, "#pg-transcript")).toBe(await top(page, "#pg-editor"));
  await expect(page.locator(".pg-rstatus")).toHaveText("Not checked");
  await page.locator("#pg-runall-folded").click();
  await expect(page.locator(".pg-rstatus")).toHaveText(/^\d+ entries checked · \d+ findings?$/, { timeout: 15_000 });
  await expect(page.locator("#pg-step-folded")).toBeDisabled();
  await expect(page.locator(".pg-stale-tag")).toHaveCount(0);
  // A change after the check: the folded tab hides the notice, so the status bar says the result is old.
  await page.locator("#pg-transcript .cm-content").click();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("\n");
  await expect(page.locator(".pg-stale-tag")).toHaveText("older than the editors: select Step or Run all");
  expect(page.errors).toEqual([]);
});

test("the browser keeps the folds of each tab", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await chooseSample(page, valid);
  await page.getByRole("tab", { name: "Transform" }).click();
  await page.locator("#pg-fold").click();
  await page.reload();
  await openPlayground(page, siteUrl("playground/"));
  await chooseSample(page, valid);
  await settled(page);
  await page.getByRole("tab", { name: "Transform" }).click();
  await expect(page.locator("#pg-fold")).toHaveAttribute("aria-expanded", "false");
  await page.getByRole("tab", { name: "Transcript" }).click();
  await expect(page.locator("#pg-fold")).toHaveAttribute("aria-expanded", "true");
  await page.getByRole("tab", { name: "Validate" }).click();
  await expect(page.locator("#pg-fold")).toHaveCount(0);
});

test("a refused run opens the folded controls, so its notice shows", async ({ page }) => {
  // The default sample has an error, so a transform does not run.
  await openPlayground(page, siteUrl("playground/"));
  await page.getByRole("tab", { name: "Transform" }).click();
  await page.locator("#pg-fold").click();
  await page.locator("#pg-run-folded").click();
  await expect(page.locator(".pg-notices .pg-notice")).toHaveText(
    "The model has errors. Fix them in the Validate tab first.",
    { timeout: 15_000 },
  );
  await expect(page.locator("#pg-fold")).toHaveAttribute("aria-expanded", "true");
  await expect(page.locator("#pg-output-kind")).toBeVisible();
});
