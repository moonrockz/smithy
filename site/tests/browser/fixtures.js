import { test as base, chromium, expect } from "@playwright/test";
import { cdpUrl } from "./site.js";

// Lightpanda fires `selectionchange` while CodeMirror sets the selection inside its own update, where
// browsers fire it later. CodeMirror then reports this error. The edit still applies; README.md has
// the details. Only the Lightpanda tests allow it.
export const lightpandaQuirk = "Calls to EditorView.update are not allowed while an update is in progress";

// The errors of the page scripts, so that a test can require none.
function collectErrors(page) {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  return errors;
}

export const test = base.extend({
  // A page in Lightpanda, through a CDP connection of its own.
  lightpanda: async ({}, use) => {
    const browser = await chromium.connectOverCDP(cdpUrl);
    const context = browser.contexts()[0] ?? (await browser.newContext());
    const page = await context.newPage();
    page.errors = collectErrors(page);
    await use(page);
    await browser.close();
  },
  // A page in Playwright's Chromium.
  page: async ({ page }, use) => {
    page.errors = collectErrors(page);
    await use(page);
  },
});

export { expect };
