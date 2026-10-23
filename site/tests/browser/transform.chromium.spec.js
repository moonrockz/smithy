// The Transform tab on Chromium: layout, the clipboard, and a model that key input changes.
import { expect, test } from "./fixtures.js";
import { chooseSample, openPlayground, settled } from "./playground.js";
import { siteUrl } from "./site.js";

// A restJson1 service with an HTTP method that OpenAPI omits. The Validate tab marks restJson1 here;
// the OpenAPI transform loads the bundled protocol definitions.
const warningModel = `$version: "2"
namespace example.web
use aws.protocols#restJson1
@restJson1
service Weather { version: "1", operations: [GetCity] }
@http(method: "CONNECT", uri: "/city")
operation GetCity { output: CityOutput }
structure CityOutput { name: String }
`;

async function openTransform(page, sample) {
  await openPlayground(page, siteUrl("playground/"));
  await chooseSample(page, sample);
  await settled(page);
  await page.getByRole("tab", { name: "Transform" }).click();
}

async function noPageScroll(page) {
  const [scroll, client] = await page.evaluate(() => [
    document.documentElement.scrollWidth,
    document.documentElement.clientWidth,
  ]);
  expect(scroll).toBeLessThanOrEqual(client);
}

test("Copy puts the shown file on the clipboard", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await openTransform(page, "JSON-RPC chat protocol");
  await page.getByRole("button", { name: "Run", exact: true }).click();
  await expect(page.locator("#pg-output .cm-line").first()).toHaveText("{", { timeout: 15_000 });
  await page.locator("#pg-copy").click();
  await expect(page.getByText("Copied to the clipboard.")).toBeVisible();
  const text = await page.evaluate(() => navigator.clipboard.readText());
  expect(text.startsWith("{\n")).toBe(true);
  expect(text).toContain('"smithy": "2.0"');
  expect(page.errors).toEqual([]);
});

test("Download saves the shown file and sends nothing to a server", async ({ page }) => {
  const requests = [];
  page.on("request", (request) => requests.push(request.url()));
  await openTransform(page, "JSON-RPC chat protocol");
  await page.getByRole("button", { name: "Run", exact: true }).click();
  await expect(page.locator("#pg-output .cm-line").first()).toHaveText("{", { timeout: 15_000 });
  const before = requests.length;
  const [download] = await Promise.all([page.waitForEvent("download"), page.locator("#pg-download-output").click()]);
  expect(download.suggestedFilename()).toBe("model.json");
  expect(requests.slice(before).filter((url) => !url.startsWith("blob:"))).toEqual([]);
});

test("OpenAPI works for a restJson1 model that Validate marks, and shows the converter warnings", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await page.locator("#pg-editor .cm-content").fill(warningModel);
  await settled(page);
  await expect(page.locator(".pg-diag")).toHaveCount(1);
  await page.getByRole("tab", { name: "Transform" }).click();
  await page.selectOption("#pg-output-kind", "openapi-3.0.2");
  await expect(page.locator(".pg-note")).toContainText("loads the bundled OpenAPI protocol definitions");
  await page.getByRole("button", { name: "Run", exact: true }).click();
  await expect(page.locator("#pg-output .cm-content")).toContainText('"openapi": "3.0.2"', { timeout: 15_000 });
  await expect(page.locator(".pg-warning")).toHaveText(
    "WARNING: example.web#GetCity: OpenAPI omits unsupported HTTP method `CONNECT`",
  );
  // The hint names the service of the run, and it describes the shown output, not the picker.
  const hint =
    'CLI: smithy build --config smithy-build.json, with the plugin "openapi": {"service": "example.web#Weather", "version": "3.0.2"}';
  await expect(page.locator(".pg-cli")).toHaveText(hint);
  await page.selectOption("#pg-output-kind", "json-ast");
  await expect(page.locator(".pg-cli")).toHaveText(hint);
  // The same model is blocked for an output that does not load the definitions.
  await page.getByRole("button", { name: "Run", exact: true }).click();
  await expect(page.locator(".pg-notices .pg-notice")).toHaveText(
    "The model has errors. Fix them in the Validate tab first.",
  );
});

test("a change after a run marks the output as old", async ({ page }) => {
  await openTransform(page, "JSON-RPC chat protocol");
  await page.getByRole("button", { name: "Run", exact: true }).click();
  await expect(page.locator("#pg-output .cm-line").first()).toHaveText("{", { timeout: 15_000 });
  await page.locator("#pg-editor .cm-content").click();
  await page.keyboard.press("Control+End");
  await page.keyboard.type("\nstructure Extra {}\n");
  await expect(page.locator(".pg-stale")).toHaveText("The model changed after this run. Select Run to update the output.");
  await settled(page);
});

for (const [width, height] of [
  [360, 780],
  [1440, 900],
]) {
  test(`at ${width} px the Transform tab with an output has no page scroll`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await openTransform(page, "JSON-RPC chat protocol");
    await page.selectOption("#pg-output-kind", "openapi-3.1.0");
    await page.getByRole("button", { name: "Run", exact: true }).click();
    await expect(page.locator(".pg-notices .pg-notice")).toBeVisible({ timeout: 15_000 });
    await page.selectOption("#pg-output-kind", "json-ast");
    await page.getByRole("button", { name: "Run", exact: true }).click();
    await expect(page.locator("#pg-output .cm-line").first()).toHaveText("{", { timeout: 15_000 });
    await noPageScroll(page);
    // The editor sizes itself after its first paint, so poll for its box.
    await expect.poll(async () => (await page.locator("#pg-output").boundingBox()).width).toBeGreaterThan(200);
    const box = await page.locator("#pg-output").boundingBox();
    expect(box.height).toBeGreaterThan(150);
    expect(box.x + box.width).toBeLessThanOrEqual(width);
    await page.screenshot({ path: `test-results/transform-${width}.png`, fullPage: true });
  });
}
