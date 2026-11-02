# Asset provenance

The art and code in this project were authored as code with AI coding assistance under the
owner's direction. The work is original: no third-party or AI-generated images were used, and
no tracing was used. Grandpa Yugong is an original design for this project based only on the
story in the Liezi (列子, "The Foolish Old Man Who Removed the Mountains", 愚公移山), a text in
the public domain. No film, animation, game, picture book, or illustration of the tale was used
as a reference.

| Asset | File | How it was made |
|---|---|---|
| Pose rig (key poses, routines, squash and stretch) | `characters/yugong/YugongRig.swift` | Coordinates and timings written by hand as code |
| Grandpa Yugong, ink style (side view, poses) | `characters/yugong/YugongArt.swift` | Ellipses, Bezier paths and tapered strokes written as AppKit/Core Graphics drawing code |
| Grandpa Yugong, pixel style: heads | `characters/yugong/YugongPixelHeads.swift` | Pixels placed by hand in text grids, one character per pixel (side, front, back, menu-bar size; expression patches) |
| Grandpa Yugong, pixel style: body | `characters/yugong/YugongArt.swift` | The same rig drawn without anti-aliasing on a 40 or 20 pixel grid, then a 1-pixel outline pass |
| Magpie (까치) | `YugongArt.swift` (ink), `YugongPixelHeads.swift` (pixel, hand-placed) | As above |
| Grandson (손주, the Codex helper) | `characters/yugong/YugongScene.swift` | Vector drawing code; pixel style rasterized on a 24 pixel grid |
| Scenes: sky, eroding mountain, ground, seal | `characters/yugong/YugongScene.swift` | Gradients, ordered dithering and paths in code |
| Turnaround (front/back), expressions, character sheet | `characters/yugong/YugongSheet.swift` | Drawing code; rendered by the `YugongSheet` tool |
| App icon | `characters/yugong/YugongIcon.swift` | The pixel scene and figure above, composed on a 52-pixel grid in code (v0.1) |
| Earlier discussion sketches (pebble, rabbit, mochi) | `archive/` | Superseded; kept for the record, not built |

## Authorship

The visual assets are authored as drawing code. AI coding assistance was used under the owner's
direction. General craft principles informed the work, but no specific character design was
copied.
