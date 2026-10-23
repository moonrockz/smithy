// Share link with the clipboard, Download, and layout. These need Chromium: Lightpanda has no
// clipboard and no layout (README.md).
import { expect, test } from "./fixtures.js";
import { openPlayground, settled, stateOfFragment } from "./playground.js";
import { siteUrl } from "./site.js";

test.use({ permissions: ["clipboard-read", "clipboard-write"] });

async function noPageScroll(page) {
  const [scroll, client] = await page.evaluate(() => [
    document.documentElement.scrollWidth,
    document.documentElement.clientWidth,
  ]);
  expect(scroll).toBeLessThanOrEqual(client);
}

test("Share link copies the URL, puts it in the address bar, and the link opens the same state", async ({ page }) => {
  const requests = [];
  page.on("request", (request) => requests.push(request.url()));
  await openPlayground(page, siteUrl("playground/"));
  await page.getByRole("tab", { name: "Transform" }).click();
  await page.selectOption("#pg-output-kind", "idl");
  const before = requests.length;
  await page.getByRole("button", { name: "Share link" }).click();
  await expect(page.locator("#pg-share-status")).toContainText("The link is in the address bar and on your clipboard.");
  const copied = await page.evaluate(() => navigator.clipboard.readText());
  expect(copied).toBe(page.url());
  expect(copied).toMatch(/\/smithy\/playground\/#v1\./);
  expect(stateOfFragment(copied.slice(copied.indexOf("#") + 1))).toMatchObject({ tab: "TransformTab", output: "Idl" });
  // Making a link sends nothing to a server.
  expect(requests.slice(before).filter((url) => !url.startsWith("blob:"))).toEqual([]);
  await page.goto("about:blank");
  await page.goto(copied);
  await settled(page);
  await expect(page.locator("#pg-output-kind")).toHaveValue("idl");
  await expect(page.getByRole("tab", { name: "Transform" })).toHaveAttribute("aria-selected", "true");
  await expect(page.locator("#pg-editor .cm-content")).toContainText("structure");
  expect(page.errors).toEqual([]);
});

test("a link opened in this tab after the page loaded is read, not ignored", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  // The user pastes a link into the address bar. Only the fragment differs, so the browser fires
  // `hashchange` and the page loads again with the link.
  await page.evaluate(() => (location.hash = "#v1.AAAA"));
  await expect(page.locator("#pg-share-status")).toContainText("I could not open this link.");
});

test("when the clipboard is missing, the page shows the link in a box", async ({ page }) => {
  await page.addInitScript(() => Object.defineProperty(navigator, "clipboard", { value: undefined }));
  await page.setViewportSize({ width: 360, height: 780 });
  await openPlayground(page, siteUrl("playground/"));
  await page.getByRole("button", { name: "Share link" }).click();
  const box = page.locator("#pg-share-url");
  await expect(box).toBeVisible();
  expect(await box.inputValue()).toBe(page.url());
  await noPageScroll(page);
  expect(page.errors).toEqual([]);
});

test("Download saves the model, and the transcript on its tab, and sends nothing to a server", async ({ page }) => {
  const requests = [];
  page.on("request", (request) => requests.push(request.url()));
  await openPlayground(page, siteUrl("playground/"));
  const before = requests.length;
  const [model] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "Download" }).click()]);
  expect(model.suggestedFilename()).toBe("model.smithy");
  expect(await readFile(model)).toContain("structure");
  await page.getByRole("tab", { name: "Transcript" }).click();
  const names = [];
  page.on("download", (download) => names.push(download.suggestedFilename()));
  await page.getByRole("button", { name: "Download" }).click();
  await expect.poll(() => names.sort()).toEqual(["model.smithy", "transcript.md"]);
  expect(requests.slice(before).filter((url) => !url.startsWith("blob:"))).toEqual([]);
});

test("at 360 px a message about a link has no page scroll", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 780 });
  await page.goto(siteUrl("playground/") + "#v1." + "A".repeat(9000));
  await expect(page.locator("#pg-share-status")).toContainText("I could not open this link.");
  await noPageScroll(page);
});

test("at 360 px the example page with its button has no page scroll", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 780 });
  await page.goto(siteUrl("examples/json-rpc/"));
  await expect(page.locator("#ms-open-playground")).toBeVisible();
  await noPageScroll(page);
  await page.locator("#ms-open-playground").click();
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace example.peers");
  await noPageScroll(page);
});

async function readFile(download) {
  const stream = await download.createReadStream();
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}
