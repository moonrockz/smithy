// Share link with the clipboard, Download, and layout. These need Chromium: Lightpanda has no
// clipboard and no layout (README.md).
import { expect, test } from "./fixtures.js";
import { linkState, openPlayground, settled, shareFragment, stateOfFragment } from "./playground.js";
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
  expect(copied).toMatch(/\/smithy\/next\/playground\/#v1\./);
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

test("a pasted link opens in place when nothing changed, and a bad link keeps the page", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  const marker = await page.evaluate(() => (window.__marker = Math.random()));
  const fragment = shareFragment(linkState({ model: "namespace pasted\n" }));
  await page.evaluate((f) => (location.hash = f), "#" + fragment);
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace pasted");
  await settled(page);
  await expect(page.locator("#pg-example option:checked")).toHaveText("Shared link");
  await expect(page.locator("#pg-incoming-open")).toHaveCount(0);
  // The page did not load again.
  expect(await page.evaluate(() => window.__marker)).toBe(marker);
  // A link that cannot be read keeps the state of the page, with the message.
  await page.evaluate(() => (location.hash = "#v1.AAAA"));
  await expect(page.locator("#pg-share-status")).toContainText("I could not open this link.");
  await expect(page.locator("#pg-share-status")).toContainText("I kept your page as it was.");
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace pasted");
  expect(page.errors).toEqual([]);
});

test("a pasted link after an edit asks first: Keep my changes keeps them, Open restores the new model", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await page.locator("#pg-editor .cm-content").fill("namespace mine\n");
  await settled(page);
  const fragment = shareFragment(linkState({ model: "namespace pasted\n", tab: "TransformTab", output: "Idl" }));
  await page.evaluate((f) => (location.hash = f), "#" + fragment);
  const ask = page.locator("#pg-incoming");
  await expect(ask).toContainText("Open the new link? You will lose your changes.");
  // Nothing changed yet.
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace mine");
  await page.getByRole("button", { name: "Keep my changes" }).click();
  await expect(page.locator("#pg-incoming-open")).toHaveCount(0);
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace mine");
  // Going to another fragment and back asks again.
  await page.evaluate(() => (location.hash = "#v1.AAAA"));
  await expect(page.locator("#pg-share-status")).toContainText("I kept your page as it was.");
  await page.evaluate((f) => (location.hash = f), "#" + fragment);
  await expect(ask).toContainText("Open the new link?");
  await page.getByRole("button", { name: "Open", exact: true }).click();
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace pasted");
  await settled(page);
  await expect(ask).toBeEmpty();
  await expect(page.getByRole("tab", { name: "Transform" })).toHaveAttribute("aria-selected", "true");
  await expect(page.locator("#pg-output-kind")).toHaveValue("idl");
  expect(page.errors).toEqual([]);
});

test("a pasted link after a fresh example pick opens with no question", async ({ page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await page.selectOption("#pg-example", { label: "Order" });
  await settled(page);
  const fragment = shareFragment(linkState({ model: "namespace pasted\n" }));
  await page.evaluate((f) => (location.hash = f), "#" + fragment);
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace pasted");
  await expect(page.locator("#pg-incoming-open")).toHaveCount(0);
  expect(page.errors).toEqual([]);
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
