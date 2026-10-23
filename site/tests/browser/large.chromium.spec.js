// Review focus 2: a pasted 1 MB model keeps the page responsive. Typing works while the Worker runs.
// The library needs minutes for a model this large, so the Worker is stopped after 10 seconds and the
// page says so. Only one request runs at a time, so the limit measures one check. No result for old
// text replaces a newer one. Runs on Chromium: it needs key input and a 1 MB insert
// (README.md).
import { expect, test } from "./fixtures.js";
import { chooseSample, openPlayground, settled } from "./playground.js";
import { siteUrl } from "./site.js";

function largeModel(size = 1_000_000) {
  let text = '$version: "2"\nnamespace big\n';
  for (let i = 0; text.length < size; i++) {
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
  // The result of the old sample stays, marked "checking". Its row names a place in the old text,
  // so it is no longer a button that moves the cursor.
  await expect(page.locator(".pg-check")).toContainText("checking");
  await expect(page.locator(".pg-diag.pg-diag-stale")).toHaveCount(1);
  await expect(page.locator("button.pg-diag")).toHaveCount(0);

  // No answer in 10 seconds: the page stops the Worker and says so.
  await expect(page.locator(".pg-notice")).toHaveText(
    "The check took more than 10 seconds, so the playground stopped it and started a new Worker. Change the model to check it again.",
    { timeout: 20_000 },
  );
  // The text typed during the first check goes to the new Worker, which also stops after 10 seconds.
  await expect(page.locator(".pg-check")).toHaveText("Stopped", { timeout: 25_000 });
  await expect(page.locator(".pg-diag")).toHaveCount(0);
  await expect(page.locator("#pg-editor .cm-lintRange-error")).toHaveCount(0);

  // The new Worker answers.
  await chooseSample(page, "Order");
  await settled(page);
  await expect(page.locator(".pg-okbox")).toHaveText("✓ The model is valid. 1 shape.");
  expect(page.errors).toEqual([]);
});

// The time of one check of `model` in a Worker of this page, in milliseconds.
async function timeOneCheck(page, model) {
  return page.evaluate(async (text) => {
    const data = JSON.parse(document.querySelector('meta[name="smithy-data"]').getAttribute("content"));
    const worker = new Worker(data.playground.worker);
    const ask = (seq, model) =>
      new Promise((resolve) => {
        worker.onmessage = (event) => resolve(event.data);
        worker.postMessage(JSON.stringify(["Validate", { seq, model }]));
      });
    await ask(1, "namespace a\n"); // the first answer includes the start of the Worker
    const started = performance.now();
    await ask(2, text);
    const ms = performance.now() - started;
    worker.terminate();
    return ms;
  }, model);
}

// A model whose check takes about `target` milliseconds on this machine. The time of a check grows
// with the square of the shape count, so the size follows from one timed check.
async function modelForCheckTime(page, target) {
  const probe = 40_000;
  const ms = await timeOneCheck(page, largeModel(probe));
  const size = Math.round(probe * Math.sqrt(target / Math.max(ms, 1)));
  return largeModel(Math.min(Math.max(size, 10_000), 200_000));
}

test("typing bursts during a long check end in its result, not in a stopped check", async ({ page, context }) => {
  test.setTimeout(120_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await openPlayground(page, siteUrl("playground/"));
  // One check takes about 3 s here, whatever the speed of the machine. The page allows 10 s.
  const model = await modelForCheckTime(page, 3_000);
  await page.evaluate((text) => navigator.clipboard.writeText(text), model);
  await page.locator("#pg-editor .cm-content").click();
  await page.keyboard.press("ControlOrMeta+a");
  await page.keyboard.press("ControlOrMeta+v");
  // Six bursts, each after the 250 ms wait, while the check of the pasted text runs. If each wait sent
  // a request, the last of seven 3 s checks would wait behind the others for more than 10 s and stop.
  // With one request at a time, the newest text goes when the running check ends: about two checks.
  for (let i = 0; i < 6; i++) {
    await page.waitForTimeout(400);
    await page.keyboard.type(`// burst ${i}\n`);
  }
  await expect(page.locator(".pg-okbox")).toHaveText(/^✓ The model is valid\. \d+ shapes\.$/, { timeout: 60_000 });
  await expect(page.locator(".pg-status")).toHaveAttribute("data-waiting", "false");
  await expect(page.locator(".pg-notice")).toHaveCount(0);
  expect(page.errors).toEqual([]);
});
