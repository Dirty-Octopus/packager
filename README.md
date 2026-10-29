<h1 align="center">
  <img src="./docs/icon.png" alt="Packager" width="120" />
  <br>
  Packager
</h1>

<h3 align="center">A local macOS workbench for legacy <code>.pkg</code> and <code>.mpkg</code> installers.</h3>

<p align="center">
  <a href="./README.md">English</a> ·
  <a href="./README.zh-CN.md">Chinese</a>
</p>

<p align="center">
  <a href="https://github.com/Dirty-Octopus/packager/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Dirty-Octopus/packager?style=flat-square"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square">
  <img alt="Universal" src="https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-444444?style=flat-square">
  <img alt="MIT" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

Packager opens legacy macOS installer packages, shows what is inside them, flags the parts that modern macOS no longer tolerates, and rebuilds the result as a flat XAR product. Everything happens in a disposable workspace. Nothing is installed, uploaded, or written into the system.

No account, telemetry, or file upload is involved.

## Preview

| Light | Dark |
| --- | --- |
| ![Light preview](./docs/preview-light.png) | ![Dark preview](./docs/preview-dark.png) |

![Chinese interface](./docs/preview-light-zh.png)

## First launch

On first launch, Packager asks you to choose English or Simplified Chinese. The welcome screen, interface language, window size preset, and appearance can be changed later from the gear icon or with <kbd>⌘</kbd><kbd>,</kbd>.

- English / Simplified Chinese, switched live without a relaunch
- Compact 1080 × 720, Standard 1240 × 830, Large 1440 × 940
- System / Light / Dark appearance
- The window is freely resizable from any edge

![First launch](./docs/onboarding.png)

![Settings](./docs/settings.png)

## What it does

- Drag a flat `.pkg` or a legacy bundle `.mpkg` into the window.
- Expand it in the workspace and show the internal structure as a tree: product, components, Distribution, PackageInfo, Bom, install scripts, payload folders, and individual Mach-O binaries.
- Flag 32-bit / PowerPC / 32-bit ARM slices, including universal binaries that contain a legacy slice.
- Detect system-version gates in the Distribution script (`min`, `max`, `allowed-os-versions`, installer JavaScript checks).
- Detect relocatable components and high-risk install scripts (recursive deletion, Gatekeeper changes, `curl | sh`, LaunchDaemons, SIP/firmware writes, and more).
- Apply one or more modernizations to a copy:
  - remove OS version limits
  - clear relocatable flags
  - strip high-risk install scripts
- Repackage with the system `pkgutil` pipeline into a modern XAR product, verify that Installer can read it, and save it to a folder you choose.
- Show the exact commands and progress in the activity log.

Packager detects legacy architectures — it does not invent 32-bit code. Repackaging cannot make a 32-bit-only binary run on current macOS.

## Install

Download the latest universal DMG or ZIP from the [Releases page](https://github.com/Dirty-Octopus/packager/releases/latest).

1. Open the DMG and drag `Packager.app` into `/Applications`, or unzip the archive and move it there.
2. If macOS blocks the app on first launch, run the following commands in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Packager.app
codesign --force --deep --sign - /Applications/Packager.app
open /Applications/Packager.app
```

Because this project is open source and the developer has not paid Apple's $99 developer program fee, run the commands above after installation. If you have a Developer ID certificate you can sign the app yourself instead.

The release is ad-hoc signed, not notarized by Apple. The commands remove the quarantine flag and apply an ad-hoc signature. This is intended for local use; ad-hoc signatures are not a substitute for Developer ID signing or notarization.

Requires macOS 14 or later. The release is a universal binary for Apple Silicon and Intel Macs.

## Usage

1. Drag a `.pkg` / `.mpkg` into the window, or press <kbd>⌘</kbd><kbd>O</kbd>. The package is copied or expanded into the workspace; the original file is not modified.
2. On **Structure**, expand components to review payload contents, scripts, and binaries. Legacy slices are marked in red. Use the filters or the search field to isolate binaries, scripts, or warnings.
3. On **Issues**, review the detected gates and risky scripts. A fix can be enabled right from an issue card, or later from the options panel.
4. In **Modernize**, enable the fixes you want. All edits are applied to a copy during repackaging.
5. Choose an output folder and a product name, then click **Repackage**.
6. The new flat XAR package is verified and saved. Use **Reveal in Finder** to open its folder.

If the output folder is not writable by your user, Packager asks for administrator authorization through the native macOS password sheet. Nothing runs as root unless you approve that prompt.

## How it works

Packager wraps the system tooling that ships with macOS:

- `pkgutil --expand` / `--expand-full` to inspect packages in the workspace
- `pkgutil --flatten` to rebuild a flat XAR product
- `pkgutil --check-signature` to read the original signature state
- a small Mach-O header reader for architecture detection (no `lipo` subprocess per file)

Distribution XML, `PackageInfo` (both the property-list and `pkg-info` dialects), `Bom`, payloads, and scripts are inspected directly. The rebuilt archive is expanded once more to verify it before it is moved to your chosen folder.

The workspace lives at `~/Library/Application Support/Packager/Workspace`. It is cleared when Packager quits. Package contents are never written to `/`, `/System`, or `/Library`; the only optional privileged step is copying the finished product into a protected output folder.

## FAQ

### Is my package uploaded anywhere?

No. Packager does not make network requests, does not collect telemetry, and does not upload files. The app is a local GUI around system tools.

### Does Packager install or modify the package?

No. It only reads the input package, expands copies in its workspace, and writes a new product to the output folder. The original file is never modified.

### Does Packager need administrator privileges?

Not for normal use. If you save the rebuilt package into a folder your user cannot write to, Packager shows the rebuilt product and asks macOS for authorization once, using `osascript` with administrator privileges. You can cancel that prompt.

### Does repackaging preserve the signature?

No. Rewriting the archive invalidates the original signature. The rebuilt product is unsigned; sign and notarize it with your own Developer ID if you plan to distribute it.

### Can Packager remove 32-bit code or add 64-bit slices?

No. It detects and highlights legacy architecture slices. Repackaging keeps the payload as-is; it does not rewrite binaries.

### Does it support legacy MPKG bundles?

Yes. Bundle-style products are expanded component by component, then rebuilt as a flat XAR archive for modern macOS.

### macOS says Packager is damaged, cannot be opened, or is from an unidentified developer

Use the commands in the [Install](#install) section. The release is ad-hoc signed, not notarized.

### Does Packager work without Xcode?

The prebuilt app does. Building from source requires Xcode with the SwiftUI macro toolchain, as with most current SwiftUI apps; Command Line Tools alone are not enough.

## Development

Requirements:

- macOS 14 or later
- Xcode with the SwiftUI macro toolchain (tested with Xcode 27.1)

Build the universal app:

```bash
bash scripts/build.sh
```

Install the local build to `/Applications` (the script only asks for administrator access if the copy needs it):

```bash
bash scripts/install.sh
```

Build a universal release with DMG, ZIP, and SHA-256 checksums:

```bash
bash scripts/package_release.sh
```

Release artifacts are written to `dist/`.

A small command-line inspection mode is available for development:

```bash
.build/release/Packager --inspect "/path/to/package.pkg"
.build/release/Packager --inspect "/path/to/package.pkg" --rebuild /tmp/out --all
```

## Safety and privacy

- No network access, telemetry, accounts, or uploads.
- All unpacking and rebuilding happens inside `~/Library/Application Support/Packager/Workspace`.
- The input package is opened read-only.
- Administrator authorization is requested only when the selected output folder requires it, and only for the displayed copy command.
- The app is ad-hoc signed. Verify the source or build it yourself if you need a stronger chain of trust.

## Acknowledgements

- Apple's `pkgutil`, `pkgbuild`, `productbuild`, Installer, and Mach-O formats.
- SwiftUI and AppKit.
- The onboarding/settings structure and install notes are inspired by [Seal](https://github.com/Dirty-Octopus/seal).
- README layout is inspired by [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev).

Packager is not affiliated with Apple.

## License

MIT. See [LICENSE](./LICENSE).
