// Large models inside the 10 s limit of the Worker: a pasted model of about 1 MB (scale-model.js) gives its
// result in the Validate tab, and its JSON AST of about 5.4 MB shows in the Transform tab, with Copy and
// Download. Runs on Chromium: it needs a 1 MB paste, and Lightpanda stops the page when CodeMirror takes a
// text of 1 MB (README.md).
import { stat } from "node:fs/promises";
import { expect, test } from "./fixtures.js";
import { openPlayground, settled } from "./playground.js";
import { siteUrl } from "./site.js";
import { scaleEvents, scaleModel, transformableScaleModel } from "./scale-model.js";

// 2,430 units give 1,000,273 bytes of IDL (75,600 lines) and 9,725 shapes. The JSON AST has about
// 5,360,000 bytes (175,800 lines).
const units = 2_430;

// The page stops a request after 10 s. A result needs that time, the 250 ms wait after a change and the
// time of the page. A result that comes at all came inside the limit: at the limit the page ends the
// Worker and says so.
const resultTimeout = 15_000;
// The page needs about 2 s to read an answer of 5.4 MB and show it in the output editor (1.5 s of that
// in one frame), and about 8 s with SITE_CPU_THROTTLE=4.
const outputTimeout = 20_000;

// Paste `text` over the model, as a reader does.
async function pasteModel(page, text) {
  await page.evaluate((text) => navigator.clipboard.writeText(text), text);
  await page.locator("#pg-editor .cm-content").click();
  await page.keyboard.press("ControlOrMeta+a");
  await page.keyboard.press("ControlOrMeta+v");
}

test("a 1 MB model gives its diagnostics in the Validate tab inside the Worker limit", async ({ page, context }) => {
  test.setTimeout(60_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const model = scaleModel(units);
  expect(model.length).toBeGreaterThan(1_000_000);
  const events = scaleEvents(units);
  const errors = events.readOnly;
  const warnings = events.ranged + events.noBlob;
  const total = events.documented + errors + warnings;

  await openPlayground(page, siteUrl("playground/"));
  await pasteModel(page, model);
  const started = Date.now();
  await expect(page.locator(".pg-check")).toHaveText(`● ${errors} errors · ${warnings} warnings`, {
    timeout: resultTimeout,
  });
  const elapsed = Date.now() - started;
  await settled(page);
  await expect(page.locator(".pg-notice")).toHaveCount(0);
  // Repeats are grouped by default: the Marked.NoBlob warnings all name the one Payload blob, so they
  // are one row of the first 200. The list counts the diagnostics that are not in it.
  const rows = total - events.noBlob + 1;
  await expect(page.locator("#pg-group")).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator(".pg-listbar")).toContainText(`${total} diagnostics in ${rows} rows`);
  await expect(page.locator(".pg-diag")).toHaveCount(200);
  const group = page.locator(".pg-diag", { has: page.locator(".pg-repeat") });
  await expect(group).toHaveCount(1);
  await expect(group.locator(".pg-repeat")).toHaveText(`×${events.noBlob}`);
  await expect(group.locator(".pg-code")).toHaveText("Marked.NoBlob");
  await group.locator(".pg-repeats summary").click();
  // The open group lists 200 of the other messages, and counts the rest.
  await expect(group.locator(".pg-repeat-list li")).toHaveCount(201);
  await expect(group.locator(".pg-repeat-list li").last()).toHaveText(`${events.noBlob - 1 - 200} more messages`);
  await expect(page.locator(".pg-validate")).toContainText(
    `${total - 199 - events.noBlob} more diagnostics are not in the list. The editor marks all of them.`,
  );
  // Without grouping, the list shows the first 200 diagnostics. The status bar does not count NOTE
  // events, so the total proves the Documented NOTE of each unit.
  await page.locator("#pg-group").click();
  await expect(page.locator("#pg-group")).toHaveAttribute("aria-pressed", "false");
  await expect(page.locator(".pg-listbar")).toHaveText(`${total} diagnosticsGroup repeats`);
  await expect(page.locator(".pg-repeat")).toHaveCount(0);
  await expect(page.locator(".pg-diag")).toHaveCount(200);
  await expect(page.locator(".pg-validate")).toContainText(
    `${total - 200} more diagnostics are not in the list. The editor marks all of them.`,
  );
  expect(total - errors - warnings).toBe(events.documented);
  test.info().annotations.push({ type: "validate", description: `${model.length} bytes in ${elapsed} ms` });
  expect(page.errors).toEqual([]);
});

test("the JSON AST of a 1 MB model has several MB and shows with Copy and Download inside the Worker limit", async ({ page, context }) => {
  test.setTimeout(90_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const model = transformableScaleModel(units);
  const events = scaleEvents(units);

  await openPlayground(page, siteUrl("playground/"));
  await page.getByRole("tab", { name: "Transform" }).click();
  await pasteModel(page, model);
  // The check of the new text comes first. The model has no errors, so a Transform can run.
  await expect(page.locator(".pg-check")).toHaveText(`✓ valid · ${events.ranged + events.noBlob} warnings`, {
    timeout: resultTimeout,
  });
  await settled(page);

  await page.selectOption("#pg-output-kind", "json-ast");
  const started = Date.now();
  await page.getByRole("button", { name: "Run", exact: true }).click();
  // While the transform runs, the tab and the status bar show a turning ring.
  await expect(page.locator(".pg-transform .pg-spinner")).toBeVisible();
  await expect(page.locator(".pg-status .pg-busy")).toContainText("running the transform");
  await expect(page.locator("#pg-copy")).toBeEnabled({ timeout: outputTimeout });
  await expect(page.locator(".pg-spinner")).toHaveCount(0);
  const elapsed = Date.now() - started;
  await expect(page.locator("#pg-download-output")).toBeEnabled();
  await expect(page.locator(".pg-notices .pg-notice")).toHaveCount(0);
  await expect(page.locator("#pg-output .cm-line").first()).toHaveText("{");

  // Copy gives the whole file: several MB, with the last shape of the model.
  await page.locator("#pg-copy").click();
  await expect(page.getByText("Copied to the clipboard.")).toBeVisible();
  const output = await page.evaluate(() => navigator.clipboard.readText());
  expect(output.length).toBeGreaterThan(5_000_000);
  expect(output.startsWith("{\n")).toBe(true);
  expect(output).toContain('"smithy": "2.0"');
  expect(output).toContain(`"example.bench#Rec${units - 1}"`);

  // Download saves the same file.
  const [download] = await Promise.all([page.waitForEvent("download"), page.locator("#pg-download-output").click()]);
  expect(download.suggestedFilename()).toBe("model.json");
  expect((await stat(await download.path())).size).toBe(Buffer.byteLength(output));
  test.info().annotations.push({
    type: "transform",
    description: `${model.length} bytes of IDL to ${output.length} bytes of JSON AST in ${elapsed} ms`,
  });
  expect(page.errors).toEqual([]);
});
