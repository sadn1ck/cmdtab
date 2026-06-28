# CmdTab

A minimal native macOS/AppKit alt-tab-style switcher.

Current scope:

- global shortcut, defaulting to `⌘⇥`
- visible non-hidden/non-minimized window list
- fullscreen windows excluded when Accessibility can inspect them
- icon plus `{window_title} / {application_name}` rows
- first shortcut press selects the second item
- repeated shortcut presses cycle selection
- releasing the shortcut modifier activates the selected window
- `Esc` cancels and keeps the current window
- `Return` activates the selected window
- settings for shortcut

## Build and run

```sh
make run
```

The built app bundle is written to:

```text
.build/debug/CmdTab.app
```

## Permissions

CmdTab asks for the permissions an alt-tab replacement typically needs:

- **Accessibility**: required to inspect, focus, and raise windows from other apps.

macOS privacy permissions are tied to the app bundle identifier and signed bundle. This project uses:

```text
dev.local.cmdtab
```

If permission prompts get stale while iterating, reset them with:

```sh
make reset-tcc
```

Then run the app again with `make run`.

## Configuration

- [`Config/Info.plist`](Config/Info.plist): bundle metadata, menu-bar-agent mode, Apple Events usage copy.
- [`Config/CmdTab.entitlements`](Config/CmdTab.entitlements): keeps the app unsandboxed and enables Apple Events for future app activation/scripting work.
- [`Sources/CmdTab/PermissionManager.swift`](Sources/CmdTab/PermissionManager.swift): central permission checks/prompts.
