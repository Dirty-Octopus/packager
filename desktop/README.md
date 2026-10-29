# Packager desktop

Electron application and isolated native bridge for Packager. Its local package
dependency `@aym-devkit/ui` vendors the active AYMDevKitUI Electron runtime at a
pinned revision; see `vendor/aym-devkit-ui/PROVENANCE.md` and its MIT license.

- `src/app.js`, `src/app.css`, `index.html`: actual Quick/Full workbench and blue identity.
- `electron.cjs`: native file dialogs, project handles, workspace lifecycle, output authorization and menu.
- `preload.cjs`: narrow context-isolated bridge. No Node access in the renderer.
- `backend.cjs`: line-delimited JSON transport and cancellation of the worker process group.
- `vendor/aym-devkit-ui`: typography, CRT, pointer mapping, settings, appearance, motion and interface audio.
- `licenses`: font OFL notices, also copied into the built app.
- `tests`: worker transport/cancellation tests and real Electron end-to-end tests.

Run the root `scripts/build.sh` first to prepare the Swift helper and resources.
`npm run dev` serves the optional frontend at localhost:1421; launch with
`PACKAGER_DEV_URL=http://127.0.0.1:1421 node_modules/.bin/electron .`. Normal
launches use built, local files. The Content Security Policy disallows remote
scripts and media. There is no updater, upload endpoint or telemetry.

The three optional GUI fixture paths use environment variables documented in the
root README. The fixture packages and build/test caches stay outside Git.
