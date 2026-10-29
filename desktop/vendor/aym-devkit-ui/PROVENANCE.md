# AYMDevKitUI source dependency

Source: https://github.com/Dirty-Octopus/AYMDevKitUI
Revision: ad8f98bd617cc90d6cc8dd6a53c6373d65475642
License: MIT (included).

The active Electron frontend is not published as a standalone npm package. This
pinned local package vendors its tracked desktop/src and public/sounds sources.
Modules and styles are used directly, including CRT mapping, coordinated motion,
settings, appearance, typography, background and interface audio.

Host adaptations: main.js becomes shell.js, gallery-only handlers are removed,
bootstrap functions are exported, the foreground mark is Packager’s pixel P, and preferences use the Packager storage key.
Packager application markup and its blue identity overrides live outside this package.
No uncommitted SwiftUI changes from the source checkout are included.
