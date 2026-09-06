# Adaptive hourglass app icon

The September 6, 2026 owner request replaces the clock/checkmark identity with
an hourglass. The iPhone app now supplies distinct light and dark artwork in its
existing primary AppIcon asset catalog. The Watch uses the same light artwork,
with space around the subject for the system's circular mask.

The hourglass retains WellSpent's navy, amber and teal palette. Both appearances
preserve its scale, caps, glass waist, sand levels and central stream. The light
background is warm ivory; the dark variant uses charcoal with darker teal glass.
The default Store icon remains fully opaque. Both variants are RGB PNG files
normalized to 1024 by 1024 pixels; no rounded corners are baked into either.

## System appearance

The dark image uses the asset catalog's `luminosity: dark` appearance. iOS owns
selection through Home Screen icon customization. With Automatic icon appearance,
it follows system light/dark appearance; a manually chosen icon appearance can
override that. There is no in-app icon switch or alternate-icon API call.
Tinted/clear treatments remain system-generated. watchOS uses one appearance.

This uses the supported asset-catalog icon workflow, not a layered Icon Composer
document. It does not claim dynamic material layers or gyro-driven highlights.
References checked September 6, 2026:

- [Apple asset catalog icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
- [Apple app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons)

## Artwork provenance

Artwork was generated with the built-in image-generation tool. The selected
outputs were normalized with macOS `sips`; no drawing or retouching script was
used. The project consumes the checked-in assets rather than generator-cache
paths. The original clock/check artwork remains in Git history.

Final light prompt:

> Use case: logo-brand. Asset type: production iPhone app icon for WellSpent, a polished personal billable-time tracker. Create ONE square 1024 by 1024 pixel final icon image, not a presentation or mockup. Light appearance. A single beautifully simple upright hourglass, centered, with a bold readable silhouette: smoothly rounded midnight-navy upper and lower caps, gently curving glass body with a narrow waist, restrained translucent pale-teal glass, warm amber sand collecting in a small lower mound and a thin falling stream. Premium native iOS aesthetic: precise symmetric geometry, softly beveled surfaces, very subtle dimensional lighting, calm and understated. Match the app's navy/amber/teal visual identity. Full-bleed warm ivory background from edge to edge; the system will supply the outer rounded-square mask. Hourglass occupies about 62 percent of width and 72 percent of height, with generous balanced safe margins and nothing near corners, suitable for a circular Watch crop too. No text, letters, numbers, clock face, checkmark, extra symbols, texture, particles, drop shadow outside the subject, borders, premade rounded-square tile, or transparent corners. Clean crisp rendering, immediately legible at 60 pixels. Deliver the icon artwork only.

The dark appearance was derived from the light artwork with geometry preserved
and dark slate/teal material colors. An intermediate transparency request yielded
an opaque checkerboard and was rejected. The selected final correction prompt:

> Use case: precise-object-edit. Create the production dark-mode app icon from this reference. Keep the hourglass exactly unchanged: same shape, scale, placement, dark teal glass, slate caps and amber sand. Replace ALL of the checkerboard background with a perfectly smooth full-bleed dark charcoal background, RGB approximately 24,28,36 (#181C24). No transparency is wanted in this output. No checkerboard, no pattern, no texture in the background, no outer shadow, no rounded-square tile, no text. The background must reach every edge and corner. Preserve the whole hourglass and its balanced margins. Deliver ONE square icon image only, 1024x1024 if possible.

## Validation boundaries

The artwork change does not alter timer behavior, model schemas, wire contracts,
bundle identifiers or privacy declarations. Source/visual review, compiled asset
validation, signed packaging, and physical Home Screen appearance are separate
observations. A subsequent release task allocates a new build and records its
own checks; prior build 5 archive evidence remains bound to its original icon.

Physical checks should confirm the new icon on iPhone and Watch, light/dark/Auto
selection on iPhone, and the idle/paused/running complication entry workflow in
`WAT-29-DESIGN-REVISION.md`. Installation must preserve the existing data store.
