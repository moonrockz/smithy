// The smoke test of the playground: one error in the default sample, then the fix and the valid state.
import { expect, lightpandaQuirk, test } from "./fixtures.js";
import { openPlayground, replaceInEditor, settled } from "./playground.js";
import { rootChannel, siteUrl } from "./site.js";

const root = rootChannel();

for (const channel of ["next/", ""]) {
  test(`the playground at /smithy/${channel} shows one error and then the valid state`, async ({ lightpanda: page }) => {
    // The root is checked only when it is this checkout (README.md).
    test.skip(channel === "" && !root.thisCheckout, root.reason);
    await openPlayground(page, siteUrl("playground/", channel));
    await expect(page.locator("#pg-example option:checked")).toHaveText("JSON-RPC chat protocol (with a mistake)");
    const diagnostic = page.locator(".pg-diag");
    await expect(diagnostic).toHaveCount(1);
    await expect(diagnostic.locator(".pg-sev")).toHaveText("ERROR");
    await expect(diagnostic.locator(".pg-msg")).toHaveText(
      "I could not resolve shape example.peers#Intger, referenced by example.peers#PostMessageOutput$count.",
    );
    await expect(diagnostic.locator(".pg-loc")).toContainText("model.smithy:46:31 · Target.UnresolvedShape");
    await expect(page.locator(".pg-tab-on .pg-count")).toHaveText("1");
    await expect(page.locator(".pg-check")).toHaveText("● 1 error");

    // A click on the diagnostic moves the cursor to its place; the editor then shows the line.
    await diagnostic.dispatchEvent("click");
    await expect(page.locator(".pg-cursor")).toHaveText("Ln 46, Col 31");
    await expect(page.locator("#pg-editor .cm-lintRange-error")).toHaveText("count: Intger");
    await expect(page.locator("#pg-editor .cm-lint-marker-error")).toHaveCount(1);

    await replaceInEditor(page, "Intger", "Integer");
    await settled(page);
    await expect(page.locator(".pg-okbox")).toHaveText(/^✓ The model is valid\. \d+ shapes\.$/);
    await expect(page.locator(".pg-check")).toHaveText("✓ valid");
    await expect(page.locator(".pg-count")).toHaveCount(0);
    await expect(page.locator(".pg-diag")).toHaveCount(0);
    await expect(page.locator("#pg-editor .cm-lintRange-error")).toHaveCount(0);
    expect(page.errors.filter((e) => e !== lightpandaQuirk)).toEqual([]);
  });
}
