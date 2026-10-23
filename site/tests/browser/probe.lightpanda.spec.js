// What the playground needs from Lightpanda 1.0.1: a Web Worker, the DOM of CodeMirror, and the
// clipboard. A check that Lightpanda cannot run moves to a *.chromium.spec.js file and into README.md.
import { expect, lightpandaQuirk, test } from "./fixtures.js";
import { openPlayground, replaceInEditor, settled } from "./playground.js";
import { siteUrl } from "./site.js";

test("a Web Worker runs the Smithy library and answers", async ({ lightpanda: page }) => {
  await page.goto(siteUrl("playground/"));
  const reply = await page.evaluate(
    (url) =>
      new Promise((resolve, reject) => {
        const worker = new Worker(url);
        worker.onmessage = (event) => {
          worker.terminate();
          resolve(event.data);
        };
        worker.onerror = (event) => reject(new Error(event.message));
        worker.postMessage(JSON.stringify(["Validate", { seq: 7, model: "namespace a\nstructure S {}\n" }]));
      }),
    siteUrl("playground/worker.js"),
  );
  expect(JSON.parse(reply)).toEqual(["Diagnostics", { seq: 7, items: [], shapes: 1 }]);
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});

test("CodeMirror renders its DOM, marks a diagnostic and reads a change of its DOM", async ({ lightpanda: page }) => {
  await openPlayground(page, siteUrl("playground/"));
  expect(await page.locator("#pg-editor .cm-line").count()).toBeGreaterThan(10);
  await expect(page.locator("#pg-editor .cm-gutters")).toHaveCount(1);
  await expect(page.locator("#pg-editor .cm-lint-marker-error")).toHaveCount(0); // line 46 is not on screen
  await replaceInEditor(page, "namespace example.peers", "namespace example.chat");
  await settled(page);
  await expect(page.locator(".pg-diag .pg-msg")).toHaveText(
    "I could not resolve shape example.chat#Intger, referenced by example.chat#PostMessageOutput$count.",
  );
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});

test("the clipboard API is missing, so the clipboard checks run on Chromium", async ({ lightpanda: page }) => {
  await page.goto(siteUrl("playground/"));
  // When this fails, Lightpanda has the clipboard: move the clipboard checks here and update README.md.
  expect(await page.evaluate(() => typeof navigator.clipboard)).toBe("undefined");
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});
