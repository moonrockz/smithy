// Where the tests find the site and Lightpanda.
export const sitePort = Number(process.env.SITE_PORT ?? 8091);
export const cdpUrl = process.env.LIGHTPANDA_CDP ?? "http://127.0.0.1:9222";

// The URL of `path` in a channel: "" is the root (/smithy/), "next/" is /smithy/next/.
export function siteUrl(path, channel = "") {
  return `http://127.0.0.1:${sitePort}/smithy/${channel}${path}`;
}
