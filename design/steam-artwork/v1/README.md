# Broomm Steam artwork — approved v1

Approved by the owner for the Add to Steam integration. Canonical images are
bundled in [assets/steam](../../../assets/steam/).

| Asset | Size | Background |
| --- | --- | --- |
| cover.png | 600 × 900 | Opaque |
| horizontal.png | 920 × 430 | Opaque |
| hero.png | 1920 × 600 | Opaque; quiet left side for Steam logo overlay |
| logo.png | 1536 × 384 | Transparent RGBA |

The three backgrounds were created with built-in image_gen using the existing Broomm mark as the reference. The transparent logo uses the application's existing Material infinity glyph and Helvetica Neue font through the pinned Flutter rendering pipeline; font files are not redistributed. Existing glyph attribution remains in assets/branding/MATERIAL-ICONS-LICENSE.txt. The generated transparent-logo attempts were rejected for edge artifacts.

The exact generation prompts, original render filenames and export details are in prompts.json. Final images were exported at the dimensions above without changing their aspect ratios. Alpha and dimensions were verified. Original generated masters remain in Codex generated_images; this folder contains the review deliverables.

The original review phase changed no application behavior. The approved images
are now loaded from the application bundle when Add to Steam is activated.
