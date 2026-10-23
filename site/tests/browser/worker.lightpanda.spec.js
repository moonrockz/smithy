// A Worker that never answers is replaced after 10 seconds. The test serves such a Worker through
// request interception.
import { expect, lightpandaQuirk, test } from "./fixtures.js";
import { siteUrl } from "./site.js";

test("a Worker that does not answer in 10 seconds is ended and a new one starts", async ({ lightpanda: page }) => {
  let loads = 0;
  await page.route("**/playground/worker.js", (route) => {
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
  expect(loads).toBe(2);
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});
