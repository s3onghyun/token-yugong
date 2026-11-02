# Asset provenance

How each visual asset in this prototype was made. No asset uses image generation, tracing,
stock art, fonts drawn as art, screenshots, or any existing character design. Grandpa Yugong is
an original design for this project based only on the story in the Liezi (列子, "The Foolish Old
Man Who Removed the Mountains", 愚公移山), a text in the public domain. No film, animation, game,
picture book or illustration of the tale was used as a reference.

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

## Who made them, and with what

- Written on 2026-11-02 by Claude (an AI coding assistant, in Claude Code) at the owner's
  request, as code and text. The session ran on the owner's personal Claude account. It did not
  use company accounts or company tools.
- General craft reading only, nothing copied: the principles that make tiny characters charming
  (big readable head, simple shapes, one strong colour accent, exaggerated anticipation) as
  commonly discussed for menu-bar and pocket pets. No specific character's design was copied.

## Ownership caveat (read before selling)

Art produced mainly by an AI may not be protected by copyright in some countries (for example,
the US Copyright Office requires human authorship). Before selling or registering Grandpa Yugong,
the final character should be authored or substantially reworked by a human (the owner or a
contracted artist with a work-for-hire or assignment agreement). This design is a strong,
reviewable starting point, not yet a protectable asset.
