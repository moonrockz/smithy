# smithy.mbt brand assets

The full-size originals of the smithy.mbt logo: the pink moonrockz bunny in a smith's apron, who forges hot metal
on an anvil on the moon. Use these files to make new sizes, for example for a desktop wallpaper, slides or print.
Do not link to them from the site: they are large.

| File | Size | Content |
|---|---|---|
| `smithy-badge-1024.png` | 1024 × 1024, transparent | The main logo: the round moon badge with the scene and the word "smithy.mbt". |
| `smithy-icon-1024.png` | 1024 × 1024, transparent | The icon: the bunny head and the raised hammer in the round navy badge, no text. It reads at 16 px. |
| `smithy-mark-1024.png` | 1024 × 1024, transparent | The mark: the bunny, the hammer and the anvil, no badge and no text. |
| `generation-prompts.txt` | | The prompts that made the art, for a new variant in the same style. |

The art is raster (PNG), painted with an image generator. There is no vector source.

## Variants

`variants/` keeps the other designs from the same session. They are not the official logo. Use them for
alternatives, for example a sticker or a slide. All are 1024 × 1024 with transparency.

| File | Content |
|---|---|
| `smithy-badge-1-1024.png` | Badge 1, "smithy.mbt": three-quarter view, gloves, the hot bar held with tongs. |
| `smithy-badge-3-1024.png` | Badge 3, "smithy.mbt": a two-handed backswing, full body, warm forge light. |
| `smithy-badge-1-smithy-text-1024.png` | Badge 1 with the earlier text "smithy". |
| `smithy-badge-2-smithy-text-1024.png` | Badge 2 (the official design) with the earlier text "smithy". |
| `smithy-badge-3-smithy-text-1024.png` | Badge 3 with the earlier text "smithy". |
| `smithy-mark-2-1024.png` | Mark 2: the hammer on the right, the hot bar held with tongs. |
| `smithy-icon-a-1024.png` | Icon try A: a larger face, with the arm visible. |
| `smithy-icon-c-1024.png` | Icon try C: a larger face, with the arm visible and an ear outside the disc. |

## Derived files

The small files come from these originals. To make them again, resize with any image tool (on macOS:
`sips -Z <size> <file> --out <file>`).

| File | Made from | Size |
|---|---|---|
| `docs/assets/smithy-badge.png` (README) | `smithy-badge-1024.png` | 480 px |
| `site/public/logo-56.png` (site header) | `smithy-icon-1024.png` | 56 px |
| `site/public/favicon.ico` | `smithy-icon-1024.png` | 16, 32 and 48 px, PNG entries |
| `site/public/favicon-32.png` | `smithy-icon-1024.png` | 32 px |
| `site/public/apple-touch-icon.png` | `smithy-icon-1024.png` | 164 px on a 180 px navy (`#0d1530`) square |
| `site/public/icon-192.png`, `icon-512.png` | `smithy-icon-1024.png` | 192 and 512 px |
