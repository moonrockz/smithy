// Where the tests find the site and Lightpanda, and which channel of the site they test.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const sitePort = Number(process.env.SITE_PORT ?? 8091);
export const cdpUrl = process.env.LIGHTPANDA_CDP ?? "http://127.0.0.1:9222";

const repo = fileURLToPath(new URL("../../..", import.meta.url));
// The output of site:pages, relative to the repository.
export const siteDir = process.env.SITE_DIR ?? "_site";

// The URL of `path` in a channel: "next/" is /smithy/next/, "" is the root (/smithy/). The tests use
// next/ by default, because /smithy/next/ is always built from this checkout. The root is built from
// the newest release tag that contains site/, when there is one (README.md).
export function siteUrl(path, channel = "next/") {
  return `http://127.0.0.1:${sitePort}/smithy/${channel}${path}`;
}

// The site configuration in the page data of a built page (`<meta name="smithy-data">`).
function builtConfig(page) {
  const html = readFileSync(resolve(repo, siteDir, page), "utf8");
  const content = html.match(/<meta name="smithy-data" content="([^"]*)"/)?.[1];
  if (content === undefined) {
    throw new Error(`${page} in ${siteDir} has no smithy-data`);
  }
  const json = content
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
  return JSON.parse(json).config;
}

// Whether the root channel is built from this checkout, and the reason when it is not. site:pages
// builds the root from this checkout, with channel next, only while no release tag contains site/.
// A tag build has channel release. The checks of the root run only when it is this checkout: a
// tag build can be older than the tests, or have no playground.
export function rootChannel() {
  let config;
  try {
    config = builtConfig("index.html");
  } catch (error) {
    return { thisCheckout: false, reason: `I could not read the root of ${siteDir}: ${error.message}` };
  }
  if (config.channel === "Next") {
    return { thisCheckout: true, reason: "" };
  }
  return {
    thisCheckout: false,
    reason: `The root of ${siteDir} is the build of ${config.git_ref} (channel ${config.channel}), not of this checkout.`,
  };
}
