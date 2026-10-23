// The Transcript tab: the samples, Step and Run all, a JSONL log, and the empty states.
import { expect, lightpandaQuirk, test } from "./fixtures.js";
import { openTranscript, settled } from "./playground.js";

const valid = "JSON-RPC chat protocol";

function noErrors(page) {
  expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
}

test("the chat variant gives the three findings of the mockup under their entries", async ({ lightpanda: page }) => {
  await openTranscript(page, valid);
  await expect(page.locator("#pg-transcript-sample option:checked")).toHaveText("Chat with three findings");
  await expect(page.locator("#pg-protocol option:checked")).toHaveText("example.peers#EchoChat");
  await expect(page.locator(".pg-trcli")).toHaveText(
    "CLI: smithy validate rpc transcript --protocol example.peers#EchoChat model.smithy transcript.md",
  );
  await page.locator("#pg-runall").dispatchEvent("click");
  await expect(page.locator(".pg-verdict")).toHaveText("● not valid · complete", { timeout: 15_000 });
  await expect(page.locator(".pg-find-code")).toHaveText(["TypeMismatch", "RequiredMember", "MissingResponse"]);
  // Each finding is under its entry, as the library writes it.
  const third = page.locator('.pg-entry[data-entry="2"]');
  await expect(third.locator(".pg-entry-dir")).toHaveText("server → reply · line 19");
  await expect(third.locator(".pg-find")).toContainText("TypeMismatch I expected a integer value, but found string.");
  await expect(third.locator(".pg-find-at")).toHaveText(
    "/result · example.peers#PostMessageOutput$count · related to entry 0",
  );
  await expect(page.locator('.pg-entry[data-entry="0"] .pg-okmark')).toHaveCount(1);
  await expect(page.locator('.pg-entry[data-entry="3"] .pg-find-code')).toHaveText(["RequiredMember", "MissingResponse"]);
  await expect(page.locator(".pg-stat")).toHaveText(["4entries checked", "3error findings", "1calls without a reply"]);
  await expect(page.locator("#pg-runall")).toBeDisabled();
  noErrors(page);
});

test("Step checks one entry at a time and Reset clears the list", async ({ lightpanda: page }) => {
  await openTranscript(page, valid);
  await page.locator("#pg-step").dispatchEvent("click");
  await expect(page.locator(".pg-entry")).toHaveCount(4, { timeout: 15_000 });
  await expect(page.locator(".pg-entry:not(.pg-entry-pending)")).toHaveCount(1);
  await expect(page.locator(".pg-stat").first()).toHaveText("1entries checked");
  for (const checked of [2, 3]) {
    await expect(page.locator("#pg-step")).toBeEnabled();
    await page.locator("#pg-step").dispatchEvent("click");
    await expect(page.locator(".pg-entry:not(.pg-entry-pending)")).toHaveCount(checked);
  }
  await expect(page.locator(".pg-find-code")).toHaveText(["TypeMismatch"]);
  await page.locator("#pg-reset").dispatchEvent("click");
  await expect(page.locator(".pg-entry")).toHaveCount(0);
  await expect(page.locator(".pg-trnotices")).toContainText("Select Step to check one entry");
  noErrors(page);
});

test("the editor log runs with its version and its dir-message preset", async ({ lightpanda: page }) => {
  await openTranscript(page, valid);
  await page.selectOption("#pg-transcript-sample", { label: "Editor log (JSONL)" });
  await expect(page.locator("#pg-format")).toHaveValue("jsonl");
  await expect(page.locator("#pg-version")).toHaveValue("2.0");
  await expect(page.locator("#pg-dir-client")).toHaveValue("in");
  await expect(page.locator("#pg-dir-server")).toHaveValue("out");
  await expect(page.locator(".pg-trcli")).toHaveText(
    "CLI: smithy validate rpc transcript --protocol example.peers#Editor --version 2.0 --log-preset dir-message --direction in=client --direction out=server model.smithy transcript.jsonl",
  );
  await page.locator("#pg-runall").dispatchEvent("click");
  // The summary of the README of examples/json-rpc.
  await expect(page.locator(".pg-verdict")).toHaveText("✓ valid · complete · 19 lines · 8 not JSON · 2 skipped", {
    timeout: 15_000,
  });
  await expect(page.locator(".pg-stat").first()).toHaveText("9entries checked");
  await expect(page.locator(".pg-find")).toHaveCount(0);
  noErrors(page);
});

test("a model with errors has no protocols, and the button opens the JSON-RPC example", async ({ lightpanda: page }) => {
  await openTranscript(page, null);
  await expect(page.locator(".pg-trnotices")).toContainText(
    "The model has errors, so the playground cannot find its JSON-RPC protocols.",
  );
  await expect(page.locator("#pg-runall")).toBeDisabled();
  await page.locator("#pg-open-protocols").dispatchEvent("click");
  await settled(page);
  await expect(page.locator("#pg-example option:checked")).toHaveText(valid);
  await expect(page.locator("#pg-protocol option")).toHaveText([
    "example.peers#EchoChat",
    "example.peers#Editor",
    "example.peers#OneWay",
    "example.peers#OrderedEditor",
  ]);
  await expect(page.locator("#pg-runall")).toBeEnabled();
});

test("a model with no protocol says that a transcript needs one", async ({ lightpanda: page }) => {
  await openTranscript(page, "Order");
  await expect(page.locator(".pg-trnotices")).toContainText(
    "The model has no structure with the @jsonRpcProtocol trait. A transcript check needs one.",
  );
  await expect(page.locator("#pg-protocol")).toBeDisabled();
});

test("a change of the transcript after the check says so, and Run all checks the new text", async ({ lightpanda: page }) => {
  await openTranscript(page, valid);
  await page.selectOption("#pg-transcript-sample", { label: "Chat" });
  await page.locator("#pg-runall").dispatchEvent("click");
  await expect(page.locator(".pg-verdict")).toHaveText("✓ valid · complete", { timeout: 15_000 });
  await page.evaluate(() => {
    for (const line of document.querySelectorAll("#pg-transcript .cm-content .cm-line")) {
      if (line.textContent.includes('"result": 1')) line.textContent = line.textContent.replace('"result": 1', '"result": "x"');
    }
  });
  await expect(page.locator(".pg-trstale")).toContainText("changed after the check started");
  await page.locator("#pg-runall").dispatchEvent("click");
  await expect(page.locator(".pg-find-code")).toHaveText(["TypeMismatch"], { timeout: 15_000 });
});
