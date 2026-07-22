# DARE brand kit

The ChengetAi-designed identity for the **DARE Digital Repository**
(Digital Archive & Research Exchange).

## Palette

| Role | Hex | Use |
|---|---|---|
| Emerald (primary) | `#0E5C4A` | Header, buttons, links |
| Deep emerald | derived (75% + black) | Footer, hover states |
| Gold (accent) | `#C8A24B` | Monogram, underlines, highlights |

## Marks

- `logo.svg` — 320×80 navbar lock-up: emerald rounded emblem with a gold serif
  **D** and underline, next to a **DARE / DIGITAL REPOSITORY** wordmark.
- `favicon.svg` — 256×256 tab icon: the same serif-D monogram on emerald.

## Apply to a deployment

The frontend ships PNGs (browsers refuse SVG bytes served under `.png`/`.ico`
names), so rasterize once, then hand the PNGs to `chengetai brand`:

```bash
# On any machine with rsvg or ImageMagick:
rsvg-convert -w 320 -h 80  logo.svg    > logo.png
rsvg-convert -w 256 -h 256 favicon.svg > favicon.png
#   (or: convert -background none logo.svg logo.png)

chengetai brand dare \
  --name "DARE Digital Repository" --institution DARE --publisher DARE \
  --primary '#0E5C4A' --accent '#C8A24B' \
  --logo logo.png --favicon favicon.png \
  --apply
```

Colours alone need no images at all:

```bash
chengetai brand dare --primary '#0E5C4A' --accent '#C8A24B' --apply
```
