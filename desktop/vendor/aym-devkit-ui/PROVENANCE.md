# AYMDevKitUI source dependency

Source: https://github.com/Dirty-Octopus/AYMDevKitUI
Revision: ad8f98bd617cc90d6cc8dd6a53c6373d65475642
License: MIT (included).

The active Electron frontend is not published as a standalone npm package. This
pinned local package vendors its tracked desktop/src and public/sounds sources.
Modules and styles are used directly, including CRT mapping, coordinated motion,
settings, appearance, typography, background and interface audio.

Host adaptations: main.js becomes shell.js, gallery-only handlers are removed,
bootstrap functions and the generic mark painter are exported, startup can enter the source assembly automatically, and preferences use the Packager storage key.
Packager paints its shared thick pixel P from Resources/BrandMark.json.
Packager application markup lives outside this package and uses the kit’s original palette. Blue identifies the application mark, rather than replacing the interface accent.
The original portal-assembly.js, motion curves, palette and CRT modules are unchanged.
No uncommitted SwiftUI changes from the source checkout are included.
