<h1 align="center"><img src="docs/icon.png" width="96" alt="Packager"><br>Packager</h1>

A local workbench for legacy macOS `.pkg` and `.mpkg` installers. Inspect their contents, assess architecture compatibility with this Mac, review repairs and repackage.

English · [简体中文](README.zh-CN.md) · MIT

The current source version is **1.1.1**. The interface uses the active Electron implementation of [AYMDevKitUI](https://github.com/Dirty-Octopus/AYMDevKitUI), with a utility-blue `#164BFF` application mark and the kit’s original interface palette. An isolated Swift helper handles installer packages. Fonts, interface audio and assets are bundled locally.

![Quick mode](docs/quick-mode.png)

## Quick mode

Startup automatically plays the kit’s 2.5-second assembly with panel wipes and a non-uniform morph, then opens Quick mode. Disabling interface motion or enabling system Reduce Motion enters immediately. Import a package and choose **Try conversion** to apply supported OS-limit, relocation and zero-size metadata repairs, and convert supported legacy bundles into flat XAR packages. Install scripts, binaries and source packages are preserved. Existing output files are never overwritten.

**Quick conversion can fail. A verified archive does not guarantee successful installation or runtime. Full mode is recommended to review issues and choose changes explicitly.**

## Compatibility with this Mac

Quick and Full modes show the current CPU, macOS and detected Rosetta installation, plus recognized CPU families and bit widths: Intel i386 / x86_64, ARM arm / arm64 / arm64_32 and PowerPC ppc / ppc64. Universal binaries list their slices.

The assessment distinguishes native architecture, possible Rosetta translation, missing Rosetta, partially incompatible contents, incompatible detected executables and insufficient data. Expand the component table to see individual results.

Installation and runtime are reported separately. Mixed legacy/64-bit binaries are distinguished from legacy-only executables. Incomplete scans or packages without recognized binaries never receive an affirmative runtime verdict. Dependencies, operating-system APIs, licensing, signing and plug-in host compatibility remain outside an architecture-only assessment. Packager does not install Rosetta or generate new machine-code slices.

References: [Apple’s 32-bit compatibility guidance](https://support.apple.com/103076), [Intel apps and Rosetta](https://support.apple.com/102527). General Rosetta availability follows Apple’s macOS 27-and-earlier guidance; static inspection cannot establish eligibility for the limited older-game exceptions in macOS 28.

## Full mode

![Full mode](docs/full-mode-dark.png)

- Switch between imported packages in the sidebar.
- Browse Distribution, PackageInfo, Bom, payloads, scripts and Mach-O files. Search, filter and preview text without executing it.
- Review issues by severity and select repairs individually.
- Optionally strip scripts identified by text heuristics as high risk. This is off by default and can prevent components from being installed.
- Follow inspection, conversion and verification events. Cancellation stops the worker and its system-tool children.

Version-limit repair handles XML elements and root attributes, plus JavaScript installation predicates whose entire dependency set can be established as OS-version checks. Mixed hardware/file/other checks remain intact and produce a manual-review warning after rebuilding. Package JavaScript is not executed for analysis.

In-window settings provide Chinese/English, system/light/dark appearance, display treatment, CRT, softness, motion and interface audio. Use Command-comma to open settings and Escape to close them. Command-O opens packages; Command-R rebuilds using the current mode.

![English light interface](docs/quick-mode-light-en.png)

## Processing and verification

Each session has an isolated folder under `~/Library/Application Support/Packager/Workspace/session-*`, removed on normal exit. Inputs remain unchanged. Inspection never runs install scripts or payload programs, installs included software, uploads files or collects telemetry.

Rebuilding expands the original again, applies selected changes, creates a flat XAR using `pkgutil --flatten`, expands the result and verifies component identities before saving. Verification covers archive structure and readable component metadata. It does not establish actual installation, plug-in loading or audio playback. Original installer signatures do not carry over.

Saving to a protected folder displays the exact copy command and requests native macOS administrator authorization. This step can be cancelled.

## Build and install locally

Requirements: macOS 14+, full Xcode, Node.js 22+ and npm. The Electron app defaults to the current machine architecture; the Swift helper contains arm64 and x86_64 slices.

```sh
bash scripts/build.sh
bash scripts/install.sh --no-build
```

The app is built at `dist/Packager.app` and installed at `/Applications/Packager.app`. Select an Intel target with `ARCH=x64 bash scripts/build.sh`, which requires the matching Electron runtime. This development round was validated on Apple Silicon.

Local builds use ad-hoc signing without Apple notarization. `bash scripts/package_release.sh` creates DMG, ZIP and SHA-256 files; it does not commit or push Git changes.

## Development and tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
npm ci --prefix desktop
node scripts/prepare_electron.cjs
npm run build --prefix desktop
npm test --prefix desktop
npm run test:browser --prefix desktop
```

GUI tests use actual Electron windows and Swift IPC. Set `PACKAGER_TEST_ORIGINAL`, `PACKAGER_TEST_FIXED` and `PACKAGER_TEST_LEGACY` to local fixtures to exercise real inspection, conversion, compatibility, Full mode and settings. Only native file-picker selections are substituted; package-processing results are real. Set `PACKAGER_TEST_APP` to the packaged app’s `Contents/MacOS/Packager` executable to test the production bundle.

```sh
.build/backend/Packager --version
.build/backend/Packager --inspect /path/to/input.pkg
.build/backend/Packager --inspect /path/to/input.pkg --rebuild /path/to/output
```

`scripts/validate_packages.py` accepts `--original`, `--fixed`, `--legacy`, `--backend` and `--output`. It verifies unchanged inputs, preserved content, size repair, legacy conversion and readable Installer choices without installing software. Proprietary fixtures and generated packages are not committed.

See [development notes](docs/DEVELOPMENT.md) and the [AYMDevKitUI provenance record](desktop/vendor/aym-devkit-ui/PROVENANCE.md).
