# Broomm icon artwork

The launcher icon uses the mint infinity mark already shown by Broomm's loading
screen: Flutter's `Icons.all_inclusive_rounded`, Material Icons code point
`U+F55C`. The dark teal tile, spacing and rendering recipe are Broomm's treatment.
The underlying Google Material Icons glyph is Apache-2.0; the complete license
from the pinned Flutter SDK is retained in `MATERIAL-ICONS-LICENSE.txt` and bundled
as a Flutter asset on every target. This is an existing SDK asset, not a newly
added icon library or runtime dependency.

`broomm-icon.png` is the 1024 px desktop/legacy master. `broomm-mark.png` is the
1024 px transparent mark. All native variants are rendered directly from the
same glyph rather than repeatedly resizing compressed images.

Regenerate from the project root with the pinned Devbox environment:

```sh
devbox run -- flutter --suppress-analytics test --no-pub tool/render_app_icons.dart
```

This explicit rendering command overwrites the owned PNG/ICO resources. Normal
debug, profile, release and GitHub builds use checked-in resources and do not run
the renderer. The Mac asset catalog has every existing size, Windows has nine
PNG-backed ICO sizes, Linux has a 512 px window/theme icon, and Android has five
legacy densities plus foreground layers for adaptive and themed icons. Android's
system supplies the final adaptive mask.

Linux's native window reads `data/broomm.png` relative to its executable. The
bundle also includes `share/applications/app.broomm.broomm.desktop` and a hicolor
icon for desktop packaging. A portable TAR does not register itself in the host's
application menu or change its icon theme; a package/desktop installation must
expose those conventional paths and resolve `Exec=broomm`. Wayland's shell icon
lookup uses that desktop identity. No system files or desktop caches are changed
by building or running Broomm.

Sources: [Material Icons](https://github.com/google/material-design-icons),
[Flutter macOS icons](https://docs.flutter.dev/deployment/macos#add-an-app-icon),
[Android adaptive icon layers and safe zone](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive),
and [GTK window icons](https://docs.gtk.org/gtk3/method.Window.set_icon_from_file.html).
