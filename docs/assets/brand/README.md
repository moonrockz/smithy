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
