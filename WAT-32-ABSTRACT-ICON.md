# Abstract hourglass artwork revision

This revision supersedes the detailed hourglass artwork described in WAT-30.
The owner requested a simpler, more abstract icon on September 6, 2026, using
Apple's iOS Preview icon as a visual reference.

## Visual direction

The original hourglass had caps, glass edges, amber sand and dimensional surface
detail. The replacement reduces the identity to two broad rounded color planes
meeting at a narrow waist. Teal above and blue below form one upright hourglass
silhouette. Restrained tonal changes replace object-like rims and reflections.
No sand, grains, falling stream, enclosing frame, text or separate caps remain.

The coordinator inspected the rendered icon on
[Apple's Preview App Store page](https://apps.apple.com/us/app/preview/id536344167).
The design interpretation takes its few broad forms and strong silhouette as
guidance. Apple's loupe artwork is not copied or included in the app.

Light appearance uses a pale background and a navy-blue lower plane. Dark
appearance uses a deep navy background and a brighter blue lower plane for
contrast. The shape and layout remain aligned. Watch uses the light identity,
with clear margins for its circular system mask.

## Native assets

- iPhone light: `WellSpentApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- iPhone dark: `WellSpentApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png`
- Watch: `WellSpentWatch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`

The selected built-in image-generation outputs were normalized with `sips` to
1024-by-1024 opaque RGB PNGs and copied into the app asset catalogs. Native dark
appearance registration is unchanged. Automatic Home Screen icon appearance
continues to follow iOS system appearance; manual icon appearance can override
it. No alternate-icon API or in-app toggle was added.

## Prompt set

The built-in image-generation tool was used, not the fallback CLI. These prompts
are retained to make the artwork's origin and design constraints explicit.

Light generation:

> Use case: logo-brand. Create one original production app icon for WellSpent, an iPhone time tracker. The user rejected a detailed, realistic hourglass and wants a much simpler abstract icon in the visual language of Apple's iOS Preview icon: broad forms, a confident silhouette, restrained soft color, almost no surface detail. Design a single large upright HOURGLASS SYMBOL, as an intentional vector-like graphic. Build it from two broad opposing rounded triangular planes touching at a short narrow central waist: upper plane tapers downward, lower plane flares outward. Softly rounded wide horizontal top and bottom edges, exact bilateral symmetry, generous margins. The planes alone form the hourglass; no enclosing frame, no separate caps, no sand, no falling stream. Upper plane rich turquoise/teal, lower plane deep blue/navy; one very gentle smooth tonal shift per plane, no grain or texture. Crisp clean edges, minimal flat graphic depth only. Full-bleed pale cool-white background, square artwork edge to edge. Mark about 54% wide and 66% tall, centered, safe for a circular Watch crop. This must read as a simple app symbol at 40 pixels, not a 3D illustration, physical object or emoji. No glossy highlights, reflections, beveled rims, metallic parts, lens effects, shadows, text, letters, border, rounded-square tile or other symbols. Deliver ONE 1024x1024 square icon image only, opaque RGB.

Dark edit, using the generated light image as the sole reference:

> Use case: precise-object-edit. Create the DARK APPEARANCE of this production WellSpent icon. Preserve the exact hourglass shape, size, placement, rounded corners, narrow waist, and every edge of the reference. Change ONLY colors: replace the entire white background with uniform full-bleed deep charcoal navy #151D28; keep the upper half a clear luminous teal; brighten the lower half to a medium saturated blue so the entire symbol is clearly visible on dark gray. Keep the same extremely restrained smooth tonal shading. Do not add any shine, surface detail, outlines, glow, texture, glass, rim, frame, shadow, sand, text or other elements. This remains a simple abstract graphic formed by two broad color planes. Opaque RGB, one square 1024x1024 image. No transparency or checkerboard.

## Validation and release boundary

This is an artwork-only revision. App behavior, native appearance registration,
project structure, privacy/support copy, signing identities and version/build
values are unchanged. Source image metadata, small-size/circular visual review,
scope validation and asset compilation are the relevant checks for this pass.

The prior 0.2.0 (6) archive and its 386-test result remain bound to source
`6c5f66f954ee3f891e4b7e438ecd4eba60d2fc29`, which contains the rejected detailed
hourglass. They do not validate or contain this revised artwork. The project
still carries its pre-existing build value during this design pass; a subsequent
release must allocate a fresh build and create new exact-source packaging and
validation records before physical installation or submission. No device,
archive, upload or App Store operation is performed by this artwork task.
