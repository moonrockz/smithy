// Browser tests of the site. Run them from site/ with `bun run test:browser` (or `mise run site:test:browser`)
// after a build of both channels into _site (`mise run site:pages -- --out _site`). See README.md.
import { defineConfig } from "@playwright/test";
import { fileURLToPath } from "node:url";
import { cdpUrl, sitePort, siteUrl } from "./site.js";

const repo = fileURLToPath(new URL("../../..", import.meta.url));
// site/mise.toml pins Lightpanda, so the mise shim finds it only in site/.
const site = fileURLToPath(new URL("../..", import.meta.url));
const siteDir = process.env.SITE_DIR ?? "_site";
const cdpPort = new URL(cdpUrl).port;

export default defineConfig({
  testDir: ".",
  timeout: 60_000,
  expect: { timeout: 10_000 },
  // Lightpanda runs one page at a time well; the tests are few.
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["github"]] : "list",
  projects: [
    // Tests that drive Lightpanda through chromium.connectOverCDP (fixtures.js).
    { name: "lightpanda", testMatch: /\.lightpanda\.spec\.js$/ },
    // Tests that Lightpanda cannot run; README.md lists each one and why.
    { name: "chromium", testMatch: /\.chromium\.spec\.js$/, use: { browserName: "chromium" } },
  ],
  webServer: [
    {
      // The output of site:pages, served under /smithy/ as GitHub Pages serves it.
      command: `moonx scripts/site-dev.mbtx --serve ${siteDir} --base /smithy/ --port ${sitePort}`,
      cwd: repo,
      url: siteUrl("playground/"),
      reuseExistingServer: !process.env.CI,
      timeout: 180_000,
    },
    {
      // Workers are off in Lightpanda unless --load-resources asks for them.
      command: `lightpanda serve --host 127.0.0.1 --port ${cdpPort} --load-resources worker`,
      cwd: site,
      url: `${cdpUrl}/json/version`,
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
  ],
});
