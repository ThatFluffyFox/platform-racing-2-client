# Optional Flash fonts

Flash drew PR2's text with Verdana (plus Arial and Times New Roman). Those fonts
are licensed by Microsoft and can't be included in this repository, so the
HTML5 build uses, in order:

1. the copy installed on the player's computer (most Windows and macOS systems),
2. a copy placed in this folder,
3. the bundled substitutes, DejaVu Sans and Liberation.

To get Flash's exact text on a machine without Verdana, copy your own licensed
font files here using these names, then rebuild:

| File | Font |
| --- | --- |
| `verdana.ttf` | Verdana |
| `verdanab.ttf` | Verdana Bold |
| `verdanai.ttf` | Verdana Italic |
| `verdanaz.ttf` | Verdana Bold Italic |
| `arial.ttf` | Arial |
| `times.ttf` | Times New Roman |

These are the file names Windows uses (`C:\Windows\Fonts`). On macOS they are in
`/System/Library/Fonts/Supplemental/` as `Verdana.ttf`, `Verdana Bold.ttf`, and
so on; rename them to the names above. `*.ttf` files here are git-ignored, so
they stay on your machine.
