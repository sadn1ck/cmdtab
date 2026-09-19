# CmdTab

A minimal native macOS/AppKit alt-tab-style switcher.

Current scope:

- global shortcut, fixed at `⌘⇥`
- visible non-hidden/non-minimized window list
- fullscreen windows excluded when Accessibility can inspect them
- icon plus `{window_title} / {application_name}` rows
- first shortcut press selects the second item
- repeated shortcut presses cycle selection
- releasing the shortcut modifier activates the selected window
- `Esc` cancels and keeps the current window
- `Return` activates the selected window

## Build and run

```sh
just run
```

The built app bundle is written to:

```text
.build/debug/CmdTab.app
```

## Install the latest release

The installer downloads the latest GitHub Release ZIP, extracts `CmdTab.app`,
and installs it in `/Applications`:

```sh
curl --fail --location https://raw.githubusercontent.com/sadn1ck/cmdtab/main/install.sh | bash
```

Or, if you have `just` installed:

```sh
just install
```

Each release also includes `CmdTab.zip.sha256`. The installer downloads that
sidecar checksum and verifies the ZIP before extracting or replacing the app.
If CmdTab is running, it shows a macOS dialog asking to quit it; choosing
Cancel, or failing to quit, stops the installation without replacing the app.

The release archive is published by GitHub Actions when a release commit is
pushed. Releases are self-signed, so macOS may require opening CmdTab once from
Finder with Control-click → Open.

## Permissions

CmdTab asks for the permissions an alt-tab replacement typically needs:

- **Accessibility**: required to inspect, focus, and raise windows from other apps.

macOS privacy permissions are tied to the app bundle identifier and signed bundle. This project uses:

```text
com.sadn1ck.apps.cmdtab
```

If permission prompts get stale while iterating, reset them with:

```sh
just reset-tcc
```

Then run the app again with `just run`.

## Configuration

- [`Config/Info.plist`](Config/Info.plist): bundle metadata, menu-bar-agent mode, Apple Events usage copy.
- [`Config/CmdTab.entitlements`](Config/CmdTab.entitlements): keeps the app unsandboxed and enables Apple Events for future app activation/scripting work.
- [`Sources/CmdTab/PermissionManager.swift`](Sources/CmdTab/PermissionManager.swift): central permission checks/prompts.
