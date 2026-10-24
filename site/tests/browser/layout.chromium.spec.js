// Layout: Lightpanda has no layout engine, so these checks run on Chromium (README.md).
import { expect, test } from "./fixtures.js";
import { openPlayground } from "./playground.js";
import { siteUrl } from "./site.js";

async function noPageScroll(page) {
  const [scroll, client] = await page.evaluate(() => [
    document.documentElement.scrollWidth,
    document.documentElement.clientWidth,
  ]);
  expect(scroll).toBeLessThanOrEqual(client);
}

test("at 360 px the playground has no page scroll and the panes stack", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 780 });
  await openPlayground(page, siteUrl("playground/"));
  await noPageScroll(page);
  const model = await page.locator(".pg-model").boundingBox();
  const results = await page.locator(".pg-results").boundingBox();
  expect(results.y).toBeGreaterThanOrEqual(model.y + model.height - 1);
  expect(model.width).toBeLessThanOrEqual(360);
});

test("at 360 px the landing page has no page scroll", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 780 });
  await page.goto(siteUrl(""));
  await noPageScroll(page);
  await expect(page.getByRole("heading", { name: "Try it without installing" })).toBeVisible();
});

test("at 1440 px the panes are side by side", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await openPlayground(page, siteUrl("playground/"));
  await noPageScroll(page);
  const model = await page.locator(".pg-model").boundingBox();
  const results = await page.locator(".pg-results").boundingBox();
  expect(results.x).toBeGreaterThan(model.x + model.width - 1);
  expect(Math.abs(results.y - model.y)).toBeLessThan(2);
});

test("a link to the playground loads its page and its script", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(siteUrl(""));
  await page.getByRole("link", { name: "Try the playground" }).click();
  await expect(page).toHaveURL(siteUrl("playground/"));
  await expect(page.locator("#pg-editor .cm-content")).toBeVisible();
  // And back out: the docs load as a page of their own.
  await page.getByRole("navigation").getByRole("link", { name: "Docs" }).click();
  await expect(page.locator("#pg-app")).toHaveCount(0);
  expect(page.errors).toEqual([]);
});

// The install tab bar of the landing page sits on its code box. The tab group
// of a Markdown page has a class of its own, so its margin does not apply here.
test("the landing page install tabs touch their code box", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(siteUrl(""));
  const bar = await page.locator(".ms-start .ms-tabs").boundingBox();
  const code = await page.locator(".ms-start .ms-code").boundingBox();
  expect(Math.abs(code.y - (bar.y + bar.height))).toBeLessThanOrEqual(1);
});
