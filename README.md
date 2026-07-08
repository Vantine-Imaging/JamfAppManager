# Jamf App Manager

A macOS 26 (SwiftUI, Liquid Glass) app for viewing and mass-modifying app settings in Jamf Pro — both **Mobile Device Apps** (Devices section) and **Mac Apps** (Computers section). Inspired by The MUT, but focused on per-app editing plus reusable setting **templates** that can be applied to many apps at once, covering the General, Scope, Managed Distribution, and App Configuration tabs.

## Status

- ✅ Connect screen: multiple saved servers, API Roles & Clients (OAuth client credentials), secrets in the login Keychain, URL prefilled from this Mac's Jamf enrollment
- ✅ Browse Mac Apps (App Store + Jamf App Catalog tabs) and Mobile Device Apps with search
- ✅ Editing: General / Managed Distribution / App Configuration fields with change tracking; every write gated behind an old→new diff review (field-masked partial XML PUT)
- ✅ Templates: field-masked setting sets (create by hand or "Save Settings as Template" from any app), multi-select apps → dry-run per-app diff → confirmed batch apply with live results
- ✅ Scope editing: all-targets toggle, group/building/department pickers, exclusions — per app and in templates (lists are full replacements, compared order-insensitively)
- ✅ Self Service tab (button text, description, notifications, categories with display/feature), category picker, VPP location picker
- ✅ Jamf App Catalog deployment editing (Pro API JSON PUT, same review gate)
- ✅ CSV import/export (MUT-style): export current settings, edit in a spreadsheet, re-import — every row dry-run diffed before the one confirmation

## CSV format

Header row, one row per app. Identifier columns: `id`, `bundle_id`, or `name` (at least one). Setting columns use field names (`displayName`, `deployAsManagedApp`, `scopeGroups`, `category`, `vppLocation`, `ssButtonText`, …) or their UI labels. Empty cells leave that field untouched. Scope lists are semicolon-separated names or `#id`s ("All iPads; #22"). `category` takes a category name, `#id`, or `None` to clear. `ssCategories` takes semicolon-separated category names with a trailing `*` to feature ("Applications; Maintenance*"). Booleans accept true/false, yes/no, 1/0. The easiest way to get a valid file is Export All to CSV, edit, re-import.

Note: the Jamf web UI shows a few Mac App Store fields (Enabled, App Store auto-sync schedule, forced updates) that have no Classic API representation — they can't be edited by any external tool.

## Development

Requires Xcode 26 on macOS 26. The `.xcodeproj` is generated and not committed — after cloning:

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project JamfAppManager.xcodeproj -scheme JamfAppManager build
```

Edit `project.yml` (not the xcodeproj) and re-run `xcodegen generate` when the project structure changes.

## Releasing a pkg

```sh
./scripts/release.sh
```

Produces `dist/JamfAppManager-<version>.pkg` (version comes from `MARKETING_VERSION` in `project.yml` — bump it there before tagging a release). The script adapts to what's in your keychain:

- **No certificates** (current state): ad-hoc-signed app, unsigned pkg. Deploys fine through Jamf Pro — MDM installs skip Gatekeeper — but manual double-click installs on unmanaged Macs are blocked.
- **Developer ID certificates present**: app signed with *Developer ID Application* (hardened runtime + timestamp), pkg signed with *Developer ID Installer*, and — if a notary profile exists — notarized and stapled, making the pkg safe to distribute anywhere.

### One-time signing setup (when ready)

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) ($99/yr, can be under the Vantine org).
2. Create certificates and install them in the login keychain:
   - **Developer ID Application** — Xcode → Settings → Accounts → Manage Certificates → “+”.
   - **Developer ID Installer** — create at developer.apple.com → Certificates if Xcode doesn’t offer it.
3. Store notarization credentials (App Store Connect API key, or Apple ID + app-specific password):
   ```sh
   xcrun notarytool store-credentials jamfappmanager-notary
   ```
4. Re-run `./scripts/release.sh` — no flags needed; it detects everything.

## Jamf Pro setup

Create an API client under **Settings → System → API Roles and Clients** with (for now) read permissions on Mobile Device Apps and Mac Apps. Write scopes come later, and the app will always show a diff preview and require explicit confirmation before writing.

API notes: full app records (scope, VPP, app configuration) come from the Classic API (`/JSSResource/mobiledeviceapplications`, `/JSSResource/macapplications`) — JSON for reads, XML for the eventual writes. OAuth tokens come from `/api/oauth/token`.
