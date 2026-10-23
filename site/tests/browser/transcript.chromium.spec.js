// The Transcript tab on Chromium: a log of 20,000 lines (review focus 2), key input during Run all, and layout.
import { expect, test } from "./fixtures.js";
import { chooseSample, openPlayground, settled } from "./playground.js";
import { siteUrl } from "./site.js";

async function openTranscript(page) {
  await openPlayground(page, siteUrl("playground/"));
  await chooseSample(page, "JSON-RPC chat protocol");
  await settled(page);
  await page.getByRole("tab", { name: "Transcript" }).click();
}

// A dir-message log of the Editor protocol: 10,000 hover calls and their replies. Every 100th reply has a
// number for the string result, so the log has 100 TypeMismatch findings, spread over the log.
function editorLog() {
  const lines = [];
  for (let i = 0; i < 10_000; i++) {
    lines.push(
      JSON.stringify({
        dir: "in",
        message: { jsonrpc: "2.0", id: i, method: "textDocument/hover", params: { uri: "file:///a.txt", line: 1, character: 2 } },
      }),
    );
    lines.push(JSON.stringify({ dir: "out", message: { jsonrpc: "2.0", id: i, result: i % 100 === 0 ? 3 : "docs" } }));
  }
  return lines.join("\n");
}

async function noPageScroll(page) {
  const [scroll, client] = await page.evaluate(() => [
    document.documentElement.scrollWidth,
    document.documentElement.clientWidth,
  ]);
  expect(scroll).toBeLessThanOrEqual(client);
}

test("a log of 20,000 lines runs in groups, and the editors stay live", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await openTranscript(page);
  await page.selectOption("#pg-transcript-sample", { label: "Editor log (JSONL)" });
  await page.evaluate((text) => globalThis.smithyEditors.load("pg-transcript", text), editorLog());
  await expect(page.locator("#pg-transcript .cm-content")).toContainText('"id":0');
  // Measure the longest gap between two frames while the check runs.
  await page.evaluate(() => {
    const probe = { maxGap: 0, last: performance.now(), running: true, findsBeforeEnd: false };
    globalThis.frameProbe = probe;
    const tick = () => {
      const now = performance.now();
      probe.maxGap = Math.max(probe.maxGap, now - probe.last);
      probe.last = now;
      if (document.querySelector(".pg-find") && !document.querySelector(".pg-verdict")) probe.findsBeforeEnd = true;
      if (probe.running) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
  await page.locator("#pg-runall").click();
  // Typing in the model editor still works while the Worker checks the log.
  await page.locator("#pg-editor .cm-content").click();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type("\n// typed during the run");
  await expect(page.locator(".pg-cursor")).toHaveText(/^Ln \d+, Col 24$/);
  // Typing can scroll the page to the cursor; after that, the run does not scroll the page.
  const scrolled = await page.evaluate(() => window.scrollY);
  await expect(page.locator(".pg-verdict")).toContainText("● not valid", { timeout: 30_000 });
  const probe = await page.evaluate(() => {
    globalThis.frameProbe.running = false;
    return globalThis.frameProbe;
  });
  // The findings came before the end of the run, and no frame waited long.
  expect(probe.findsBeforeEnd).toBe(true);
  expect(probe.maxGap).toBeLessThan(1_000);
  await expect(page.locator(".pg-verdict")).toContainText("20000 lines · 0 not JSON · 0 skipped");
  await expect(page.locator(".pg-stat")).toHaveText(["20000entries checked", "100error findings", "0calls without a reply"]);
  // The list shows a part of the entries and says so.
  const rows = await page.locator(".pg-entry").count();
  expect(rows).toBeLessThanOrEqual(200);
  await expect(page.locator(".pg-trnote")).toContainText("The transcript has 20000 entries.");
  await expect(page.locator(".pg-entry-gap").first()).toBeVisible();
  // The first entries with findings are in the list: each 100th reply.
  await expect(page.locator('.pg-entry[data-entry="1"] .pg-find-code')).toHaveText("TypeMismatch");
  await expect(page.locator('.pg-entry[data-entry="201"] .pg-find-code')).toHaveText("TypeMismatch");
  // The model changed during the run, so the tab says that the check is old.
  await expect(page.locator(".pg-trstale")).toContainText("changed after the check started");
  // The cursor of the transcript editor is at the last checked entry.
  const active = await page.locator("#pg-transcript .cm-lineNumbers .cm-activeLineGutter").textContent();
  expect(active).toBe("20000");
  // The cursor of the transcript editor moved, but the page did not scroll.
  expect(await page.evaluate(() => window.scrollY)).toBe(scrolled);
  expect(page.errors).toEqual([]);
});

test("at 360 px and 1440 px the Transcript tab with findings has no page scroll", async ({ page }) => {
  for (const [width, height] of [
    [360, 780],
    [1440, 900],
  ]) {
    await page.setViewportSize({ width, height });
    await openTranscript(page);
    await page.locator("#pg-runall").click();
    await expect(page.locator(".pg-verdict")).toHaveText("● not valid · complete", { timeout: 15_000 });
    await noPageScroll(page);
    await page.screenshot({ path: `test-results/transcript-${width}.png`, fullPage: width === 360 });
  }
  expect(page.errors).toEqual([]);
});

test("a click on the line of an entry moves the cursor of the transcript editor", async ({ page }) => {
  await openTranscript(page);
  await page.locator("#pg-runall").click();
  await expect(page.locator(".pg-verdict")).toBeVisible({ timeout: 15_000 });
  await page.locator('.pg-entry[data-entry="2"] .pg-linkbtn').click();
  await expect(page.locator("#pg-transcript .cm-lineNumbers .cm-activeLineGutter")).toHaveText("19");
});
