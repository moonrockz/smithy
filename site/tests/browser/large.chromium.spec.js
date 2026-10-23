// Review focus 2: a pasted 1 MB model keeps the page responsive. Typing works while the Worker runs.
// The library needs minutes for a model this large, so the Worker is stopped after 10 seconds and the
// page says so. No result for old text shows. Runs on Chromium: it needs key input and a 1 MB insert
// (README.md).
import { expect, test } from "./fixtures.js";
import { chooseSample, openPlayground, settled } from "./playground.js";
import { siteUrl } from "./site.js";

function largeModel() {
  let text = '$version: "2"\nnamespace big\n';
  for (let i = 0; text.length < 1_000_000; i++) {
    text += `structure S${i} {\n    a: String\n    b: Integer\n}\n\n`;
  }
  return text;
}

test("a 1 MB model keeps typing and the status bar live, and a stopped check names the reason", async ({ page, context }) => {
  test.setTimeout(90_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await openPlayground(page, siteUrl("playground/"));
  // Paste the model, as a reader does.
  await page.evaluate((text) => navigator.clipboard.writeText(text), largeModel());
  await page.locator("#pg-editor .cm-content").click();
  await page.keyboard.press("ControlOrMeta+a");
  await page.keyboard.press("ControlOrMeta+v");
  await expect(page.locator(".pg-status")).toHaveAttribute("data-waiting", "true");

  // The page answers at once while the Worker runs.
  const started = Date.now();
  await page.keyboard.type("// more");
  await expect(page.locator(".pg-cursor")).toHaveText(/^Ln \d{5}, Col 8$/);
  expect(Date.now() - started).toBeLessThan(3_000);
  const roundTrip = await page.evaluate(async () => {
    const t0 = performance.now();
    await new Promise((resolve) => setTimeout(resolve, 0));
    return performance.now() - t0;
  });
  expect(roundTrip).toBeLessThan(500);
  await expect(page.locator(".pg-status")).toHaveAttribute("data-waiting", "true");
  // The result of the old sample is gone: it was for other text.
  await expect(page.locator(".pg-diag")).toHaveCount(1);

  // No answer in 10 seconds: the page stops the Worker and says so.
  await expect(page.locator(".pg-notice")).toHaveText(
    "The check took more than 10 seconds, so the playground stopped it and started a new Worker. Change the model to check it again.",
    { timeout: 20_000 },
  );
  await expect(page.locator(".pg-check")).toHaveText("Stopped");
  await expect(page.locator(".pg-diag")).toHaveCount(0);
  await expect(page.locator("#pg-editor .cm-lintRange-error")).toHaveCount(0);

  // The new Worker answers.
  await chooseSample(page, "Order");
  await settled(page);
  await expect(page.locator(".pg-okbox")).toHaveText("✓ The model is valid. 1 shape.");
  expect(page.errors).toEqual([]);
});
