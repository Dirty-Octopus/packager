# Packager 1.1.0 — development and validation

## Architecture

The previous SwiftUI frontend has been replaced by the active Electron branch of
AYMDevKitUI. A pinned source dependency is used because the upstream repository
does not publish its Electron modules as an independent npm package. The source
checkout's uncommitted SwiftUI work was not copied or modified.

Electron owns native dialogs, session/project handles, menus, protected-folder
save authorization and helper cancellation. The renderer is sandboxed, context
isolated and has no Node integration. IPC exposes named operations rather than
arbitrary commands. Only backend-generated pending output-copy commands can be
authorized; renderer input cannot supply an administrator command.

The Swift executable owns inspection, PackageMaker bundle normalization, Mach-O
parsing, static version-gate analysis, size estimates, reconstruction and archive
verification. Each operation is a separate process group. The wire protocol is
one JSON request on stdin and line-delimited log/result/error messages on stdout.

`Sources/Packager/Resources/Version.txt` is the version source. The build script
synchronizes Electron and app metadata. The Swift helper loads the bundled
resource in development and inside the installed app.

## Repairs

- XML system-version elements and root min/max attributes are counted and removed.
- Zero-argument JavaScript gate functions and direct predicates are examined
  statically. Only gates containing exclusively version logic, local variables
  and Installer result-message assignments can be removed. Hardware/file/mixed
  checks are preserved; surviving checks produce a rebuild warning.
- A binary with both i386 and x86_64 no longer counts as legacy-only. Universal,
  thin and swapped-endian FAT headers are recognized; CPU family and bit width
  remain separate from the current-host verdict.
- `Scripts/payload` content is scanned and measured. Distribution size estimates
  of zero are repaired without changing the empty native payload metadata or
  the scripts that actually perform installation.
- Supported `Contents/Archive.pax.gz` bundles are unpacked with system tools,
  rebuilt as components with `pkgbuild`, and normalized to a flat Distribution
  layout. Archive member names are checked for escaping paths. No package code runs.

Host compatibility is an architecture assessment, not a successful-install claim.
It considers actual Mac CPU, macOS, Rosetta availability and all scanned binary
slices. Missing/incomplete payloads produce an unknown result. Intel plug-in host
compatibility, OS APIs, code signing, licensing and dependencies are not proven.

## Local verification on 2026-10-30

The regression fixtures were supplied by the user and are not redistributed.

| Sample | Evidence |
| --- | --- |
| SpectralCorruptor original | 8 components, 3 universal Intel/ARM 64-bit binaries; five zero-size Distribution entries repaired to 14058 / 13968 / 14523 / 264 / 607 KB. All scripts, embedded payload bytes and component metadata preserved. |
| SpectralCorruptor fixed | Same content; no zero-size repair applied. Scripts and payload preserved. |
| Sylenth1 v2.21 Beta | 2 legacy components converted to a flat product; all 159 payload files preserved byte for byte. Both executables are i386, Intel 32-bit, incompatible with this test Mac's current macOS. |

All three rebuilt archives expand successfully and are accepted by the read-only
`installer -showChoicesXML` query. Source-package file hashes remain unchanged.
No sample package was installed and no plug-in/DAW playback claim is made.

After installation to `/Applications/Packager.app`, the native macOS picker was
also used to open the original legacy MPKG. The installed app entered Quick mode,
completed the scan and visibly reported i386 / Intel 32-bit as incompatible with
this Mac. Installed and built app archives match, and strict signature verification
passes. The installed helper reports the same 1.1.0 version and passes the three
fixture rebuild checks.

Automated coverage:

- 13 Swift regression and package-pipeline tests: mixed architecture, CPU families,
  translation decisions, incomplete scans, JavaScript/XML removal, mixed-check
  preservation and warning, size repair, version resource and unique output names.
- 3 Node tests: actual helper errors, process-group cancellation, and verification that cancelling a real Swift worker leaves no running pkgutil child.
- 5 Electron tests against the packaged app: default Quick mode and failure/recommendation copy, real repair
  through IPC, Full mode/search/text preview/options, fixed/legacy fixtures,
  architecture verdicts, in-window settings, language/appearance and physical
  pointer mapping with CRT enabled.

The GUI tests substitute file-picker selections, not backend processing. Screenshots
are captured from actual Electron windows. The local build target is Apple Silicon;
the helper is universal and its deployment minimum is verified from its Mach-O
load commands. Intel-target app packaging is available but not exercised here.

Generated artifacts, package samples, session workspaces and dependency caches
are ignored. AYMDevKitUI's MIT notice and both font OFL notices are included in the
built application. Local signing is ad-hoc without notarization.
