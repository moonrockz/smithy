// Share links, "Open in playground" and links the page cannot read (review focus 5). The clipboard
// does not exist in Lightpanda, so the page shows the link: that is the case these tests use.
// The clipboard itself is in share.chromium.spec.js.
import { expect, lightpandaQuirk, test } from "./fixtures.js";
import {
  chooseSample,
  expectDefaultWithMessage,
  linkState,
  openPlayground,
  openTranscript,
  repoFile,
  settled,
  shareFragment,
  stateOfFragment,
} from "./playground.js";
import { siteUrl } from "./site.js";

const valid = "JSON-RPC chat protocol";

// The URL that the Share link button gave, shown in the box under the toolbar.
async function sharedUrl(page) {
  await page.locator("#pg-share").dispatchEvent("click");
  const box = page.locator("#pg-share-url");
  await expect(box).toBeVisible();
  const url = await box.inputValue();
  expect(url).toContain("/playground/#v1.");
  return url;
}

async function transcriptSettings(page) {
  return page.evaluate(() => ({
    protocol: document.querySelector("#pg-protocol")?.value,
    format: document.querySelector("#pg-format")?.value,
    version: document.querySelector("#pg-version")?.value,
    preset: document.querySelector("#pg-preset")?.value,
    client: document.querySelector("#pg-dir-client")?.value,
    server: document.querySelector("#pg-dir-server")?.value,
    complete: document.querySelector("#pg-complete")?.checked,
  }));
}

test("a share link restores the model, the tab and every setting of the Transcript tab", async ({ lightpanda: page }) => {
  await openTranscript(page, valid);
  await page.selectOption("#pg-transcript-sample", { label: "Editor log (JSONL)" });
  await expect(page.locator("#pg-dir-client")).toHaveValue("in");
  await page.locator("#pg-dir-client").fill("cin");
  await page.locator("#pg-complete").dispatchEvent("click");
  await expect(page.locator("#pg-complete")).toBeChecked();
  const before = await transcriptSettings(page);
  expect(before).toMatchObject({ protocol: "example.peers#Editor", version: "2.0", client: "cin", complete: true });
  const url = await sharedUrl(page);
  await expect(page.locator("#pg-share-status")).toContainText("Your browser cannot use the clipboard");
  // The address shows the link, and the link has every field.
  const state = stateOfFragment(url.slice(url.indexOf("#") + 1));
  expect(state.tab).toBe("TranscriptTab");
  expect(state.protocol).toBe("example.peers#Editor");
  expect(state.version).toBe("2.0");
  expect(state.complete).toBe(true);
  expect(state.selector).toBe("structure > member");
  expect(state.log_preset).toBeTruthy();
  expect(state.model).toContain("namespace example.peers");

  // Lightpanda has one page for each connection: open the link in the same page.
  const other = page;
  await page.goto("about:blank");
  await page.goto(url);
  await expect(other.locator("#pg-editor .cm-content")).toContainText("namespace example.peers");
  await settled(other);
  await expect(other.locator(".pg-trpanel")).not.toHaveClass(/pg-off/);
  await expect(other.locator("#pg-share-status")).toBeEmpty();
  await expect(other.locator("#pg-example option:checked")).toHaveText("Shared link");
  await expect(other.locator("#pg-transcript-sample option:checked")).toHaveText("Shared link");
  expect(await transcriptSettings(other)).toEqual(before);
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});

test("a share link restores the Transform tab with its output and selector", async ({ lightpanda: page }) => {
  await openPlayground(page, siteUrl("playground/"));
  await chooseSample(page, valid);
  await settled(page);
  await page.locator(".pg-tab", { hasText: "Transform" }).dispatchEvent("click");
  await page.selectOption("#pg-output-kind", "selector");
  await page.locator("#pg-selector").fill("structure");
  const url = await sharedUrl(page);
  const other = page;
  await page.goto("about:blank");
  await page.goto(url);
  await settled(other);
  await expect(other.locator(".pg-transform")).not.toHaveClass(/pg-off/);
  await expect(other.locator("#pg-output-kind")).toHaveValue("selector");
  await expect(other.locator("#pg-selector")).toHaveValue("structure");
});

test("a protocol that the model does not have gives fitted settings and a working picker", async ({ lightpanda: page }) => {
  const state = linkState({ tab: "TranscriptTab", protocol: "gone#Missing", transcript: "---\nversion: 1.0\n---\n" });
  await page.goto(siteUrl("playground/") + "#" + shareFragment(state));
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace example.peers");
  await settled(page);
  await expect(page.locator(".pg-trpanel")).not.toHaveClass(/pg-off/);
  const options = await page.locator("#pg-protocol option").evaluateAll((all) => all.map((o) => o.value));
  expect(options.length).toBeGreaterThan(0);
  expect(options).not.toContain("gone#Missing");
  await expect(page.locator("#pg-protocol")).toHaveValue(options[0]);
});

test("a link that the page cannot read shows a message and the default example", async ({ lightpanda: page }) => {
  const cases = [
    ["a corrupt link", "v1.AAAA", "I could not unpack the link"],
    ["a character that is not base64url", "v1.ab+c", "not in base64url"],
    ["a link from a newer format", "v2.AAAA", "it has the format v2", "newer version of the site"],
    ["a text that is not a link", "section", "start with v1."],
    ["a link that is too long", "v1." + "A".repeat(9000), "9003 characters", "8000 at most"],
    [
      "a link that unpacks to a large state",
      shareFragment(linkState({ model: "a".repeat(3_000_000) })),
      "The link unpacks to more than 2097152 bytes.",
    ],
  ];
  for (const [name, fragment, ...texts] of cases) {
    expect(fragment.length, name).toBeGreaterThan(3);
    await page.goto(siteUrl("playground/") + "#" + fragment);
    await expectDefaultWithMessage(page, ...texts);
  }
  // The large state is short in a link: the limit is about the size after unpacking.
  expect(shareFragment(linkState({ model: "a".repeat(3_000_000) })).length).toBeLessThan(8000);
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
});

test("a link made on /next/ opens on the release channel, and a future format shows the message", async ({ lightpanda: page }) => {
  await openPlayground(page, siteUrl("playground/", "next/"));
  await chooseSample(page, valid);
  await settled(page);
  const url = await sharedUrl(page);
  expect(url).toContain("/smithy/next/playground/#v1.");
  const root = url.replace("/smithy/next/playground/", "/smithy/playground/");
  await page.goto(root);
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace example.peers");
  await settled(page);
  await expect(page.locator("#pg-share-status")).toBeEmpty();
  // A fragment of a format that the page does not know: the message, never a blank page.
  await page.goto(siteUrl("playground/") + "#v2." + url.split("#v1.")[1]);
  await expectDefaultWithMessage(page, "it has the format v2");
});

test("Open in playground links to a state that decodes to the model of the example", async ({ lightpanda: page }) => {
  await page.goto(siteUrl("examples/json-rpc/"));
  const button = page.locator("#ms-open-playground");
  await expect(button).toHaveText("Open in playground");
  const href = await button.getAttribute("href");
  expect(href).toMatch(/^\/smithy\/playground\/#v1\./);
  // The pre-render writes the link: the page text from the server has it.
  const html = await page.evaluate(() => fetch(location.href).then((r) => r.text()));
  expect(html).toContain(`href="${href}"`);
  const state = stateOfFragment(href.slice(href.indexOf("#") + 1));
  expect(state.model).toBe(repoFile("examples/json-rpc/peers.smithy"));
  expect(state.tab).toBe("ValidateTab");
  await page.goto(`http://127.0.0.1:${new URL(page.url()).port}${href}`);
  await expect(page.locator("#pg-editor .cm-content")).toContainText("namespace example.peers");
  await settled(page);
  await expect(page.locator(".pg-check")).toContainText("valid");
  await expect(page.locator("#pg-share-status")).toBeEmpty();
});

test("an example whose directory has no model in the picker has no button", async ({ lightpanda: page }) => {
  await page.goto(siteUrl("examples/openrpc/"));
  await expect(page.locator("h1").first()).toBeVisible();
  await expect(page.locator("#ms-open-playground")).toHaveCount(0);
  await page.goto(siteUrl("examples/"));
  await expect(page.locator("#ms-open-playground")).toHaveCount(0);
});
