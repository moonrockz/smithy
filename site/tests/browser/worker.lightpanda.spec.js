// A Worker that never answers is replaced after 10 seconds. The test serves such a Worker through
// request interception.
import { expect, lightpandaQuirk, test } from "./fixtures.js";
import { siteUrl } from "./site.js";

// The Worker script, with or without the query that names the build.
const workerScript = /\/playground\/worker\.js(\?|$)/;

test("a Worker that does not answer in 10 seconds is ended and a new one starts", async ({ lightpanda: page }) => {
  let loads = 0;
  await page.route(workerScript, (route) => {
    loads += 1;
    return route.fulfill({ contentType: "text/javascript", body: "self.onmessage = () => {};" });
  });
  await page.goto(siteUrl("playground/"));
  await expect(page.locator(".pg-check")).toContainText("checking");
  await expect(page.locator(".pg-notice")).toHaveText(
    "The check took more than 10 seconds, so the playground stopped it and started a new Worker. Change the model to check it again.",
    { timeout: 20_000 },
  );
  await expect(page.locator(".pg-check")).toHaveText("Stopped");
  await expect.poll(() => loads).toBe(2);
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});

test("a Worker that stops with an error is replaced at once, and the page says that the check failed", async ({ lightpanda: page }) => {
  let loads = 0;
  await page.route(workerScript, (route) => {
    loads += 1;
    return route.fulfill({ contentType: "text/javascript", body: 'throw new Error("boom");' });
  });
  const started = Date.now();
  await page.goto(siteUrl("playground/"));
  await expect(page.locator(".pg-notice p")).toHaveText(
    "The check failed because the Worker stopped with an error. The playground started a new Worker. Change the model to check it again.",
  );
  expect(Date.now() - started).toBeLessThan(8_000);
  await expect(page.locator(".pg-check")).toHaveText("Failed");
  // One restart: the new Worker fails too, but no request runs, so it is not restarted again.
  await expect.poll(() => loads).toBe(2);
  await page.waitForTimeout(1_000);
  expect(loads).toBe(2);
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});

test("a Worker of another build answers at once, and the page says to reload it", async ({ lightpanda: page }) => {
  const urls = [];
  // The answer of the Worker to a request that it could not read (core.handle_json).
  const answer = JSON.stringify(["Blocked", { seq: -1, reason: "I could not read the request: old", kind: "Other" }]);
  await page.route(workerScript, (route) => {
    urls.push(route.request().url());
    return route.fulfill({
      contentType: "text/javascript",
      body: `self.onmessage = () => self.postMessage(${JSON.stringify(answer)});`,
    });
  });
  const started = Date.now();
  await page.goto(siteUrl("playground/"));
  await expect(page.locator("#pg-mismatch")).toHaveText("The page and its checker do not match. Reload the page.");
  expect(Date.now() - started).toBeLessThan(8_000);
  await expect(page.locator(".pg-check")).toHaveText("Failed");
  // The Worker URL names the build, so that a cached Worker of another build does not answer.
  expect(urls).toHaveLength(1);
  expect(urls[0]).toMatch(/\/smithy\/next\/playground\/worker\.js\?v=[0-9a-f]{40}$/);
  // No new Worker starts: it would load the same script.
  await page.waitForTimeout(1_000);
  expect(urls).toHaveLength(1);
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});
