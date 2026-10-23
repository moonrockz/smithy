// The Transform tab: outputs, blocked runs and the hint line.
import { expect, lightpandaQuirk, test } from "./fixtures.js";
import { chooseSample, openPlayground, settled } from "./playground.js";
import { siteUrl } from "./site.js";

const valid = "JSON-RPC chat protocol";

async function openTransform(page, sample) {
  await openPlayground(page, siteUrl("playground/"));
  if (sample) {
    await chooseSample(page, sample);
    await settled(page);
  }
  await page.locator(".pg-tab", { hasText: "Transform" }).dispatchEvent("click");
  await expect(page.locator(".pg-transform")).not.toHaveClass(/pg-off/);
}

async function run(page, output) {
  await page.selectOption("#pg-output-kind", output);
  await page.locator("#pg-run").dispatchEvent("click");
}

test("JSON AST of the valid sample starts with a brace and the version", async ({ lightpanda: page }) => {
  await openTransform(page, valid);
  await expect(page.locator(".pg-cli")).toHaveText("CLI: smithy convert --to json model.smithy");
  await expect(page.locator("#pg-copy")).toBeDisabled();
  await run(page, "json-ast");
  await expect(page.locator("#pg-output .cm-line").first()).toHaveText("{", { timeout: 15_000 });
  await expect(page.locator("#pg-output .cm-content")).toContainText('"smithy": "2.0"');
  await expect(page.locator("#pg-copy")).toBeEnabled();
  await expect(page.locator("#pg-download-output")).toBeEnabled();
  await expect(page.locator(".pg-files")).toBeEmpty();
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});

test("a selector lists the shape IDs and the hint names the command", async ({ lightpanda: page }) => {
  await openTransform(page, valid);
  await page.selectOption("#pg-output-kind", "selector");
  await expect(page.locator("#pg-selector")).toHaveValue("structure > member");
  await expect(page.locator(".pg-cli")).toHaveText(
    "CLI: smithy select --selector 'structure > member' model.smithy",
  );
  await page.locator("#pg-run").dispatchEvent("click");
  await expect(page.locator("#pg-output .cm-content")).toContainText("example.peers#EchoInput$text", { timeout: 15_000 });
});

test("a model with errors blocks the run with the copy of the brief", async ({ lightpanda: page }) => {
  await openTransform(page, null);
  await run(page, "json-ast");
  await expect(page.locator(".pg-notices .pg-notice")).toHaveText(
    "The model has errors. Fix them in the Validate tab first.",
    { timeout: 15_000 },
  );
  await expect(page.locator("#pg-copy")).toBeDisabled();
});

test("another block shows the reason of the library, and OpenAPI has the protocol note", async ({ lightpanda: page }) => {
  await openTransform(page, valid);
  await expect(page.locator(".pg-note")).toHaveCount(0);
  await run(page, "openapi-3.0.2");
  await expect(page.locator(".pg-notices .pg-notice")).toHaveText(
    "I found no service with a protocol trait in the model.",
    { timeout: 15_000 },
  );
  await expect(page.locator(".pg-note")).toContainText("loads the bundled OpenAPI protocol definitions");
  await expect(page.locator(".pg-cli")).toContainText('"openapi": {"version": "3.0.2"}');
});

test("OpenRPC picks a service with jsonRpc 2.0", async ({ lightpanda: page }) => {
  await openTransform(page, valid);
  await run(page, "openrpc");
  await expect(page.locator("#pg-output .cm-content")).toContainText('"openrpc": "1.3.2"', { timeout: 15_000 });
  await expect(page.locator(".pg-warning")).toHaveCount(0);
});

test("the Validate tab still shows the diagnostics after a run", async ({ lightpanda: page }) => {
  await openTransform(page, null);
  await run(page, "json-ast");
  await expect(page.locator(".pg-notices .pg-notice")).toBeVisible({ timeout: 15_000 });
  await page.locator(".pg-tab", { hasText: "Validate" }).dispatchEvent("click");
  await expect(page.locator(".pg-diag")).toHaveCount(1);
  await settled(page);
});
