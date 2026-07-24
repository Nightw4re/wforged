# Wforged

> **Beta version** — features and data formats may change between releases.

Wforged collects Worldforged item locations and item information in World of Warcraft. It works locally, supports ElvUI when installed, and can share compact item observations with guild members who also use the addon.

The release currently includes a bundled snapshot of **257 unique items including located base items and upgrades**.

## Features

- Detects Worldforged items from loot and verifies the tooltip marker.
- Stores the loot zone, map, coordinates, item level, quality, stats, and tooltip.
- Handles scaled items and multi-step upgrade chains.
- Resolves upgrade locations back to the original loot location.
- Searches by name, tooltip text, stats, armor type, weapon type, slot, quality, and level.
- Shows item tooltips from the search list.
- Places item markers on the world map and supports showing all known loot locations.
- Automatically confirms the bind dialog only for confirmed Worldforged items.
- Keeps data account-wide across characters.
- Supports compact import/export and optional guild broadcast/receive.

## Updates

Use `/wforged update` to display the installed version and the official CurseForge page:
https://www.curseforge.com/wow/addons/wforged

The addon cannot query CurseForge directly from the game client, so the page is the authoritative source for the latest release.
- Works with or without ElvUI.

## Installation

1. Extract the `Wforged` folder into the client's `Interface\AddOns` directory.
2. Enable Wforged on the character selection screen.
3. Reload the UI after installing or updating the addon.

For local development, `npm test` deploys the addon to the configured game client and runs the automated checks first. To refresh the bundled snapshot from a SavedVariables file, run:

```text
npm run bundle-data -- "C:\path\to\Wforged.lua" 1.0.2
```

The command regenerates `addon/Wforged/BundledData.lua` and updates the documented item count.

## Using the addon

Open the search window through the Wforged minimap button or use:

```text
/wforged search
```

The search window supports multiple words, for example:

```text
leather agility feet
```

Click an item to inspect its tooltip. Use `Share` to place a functional item link, zone, and coordinates in chat. Use `Map` to open the recorded loot location. These actions are hidden when an item has no valid loot location.

## Settings

The settings window has a player view and a developer view, switched with the `Dev` button.

Player settings include:

- Worldforged auto-confirm.
- Show all known map items.
- Send guild updates.
- Receive guild updates.
- Compact import/export controls.

Developer settings include:

- Debug log output.
- Map context diagnostics.
- Import test data.
- Database reset followed by UI reload.

## Import and export

Export creates a compact grouped `WFGDB7` string organized as `realm -> location -> itemId:timestamp`. Import also accepts the older `WFGDB6` format, merges data into the local database, and does not remove existing items. Processing is batched for large datasets.

After import, item names, quality, level, icons, stats, and tooltip text are resolved locally by the client. Newly loaded metadata can appear a moment after the item is first added.

## Guild sharing

Enable `Send guild updates` to broadcast newly looted Worldforged items. Enable `Receive guild updates` to accept observations from other addon users. Guild sharing uses addon messages, not normal chat text. The sender and receiver must both have Wforged enabled and be in the same guild channel.

## Commands

```text
/wforged
/wforged search
/wforged scan
/wforged vendor
/wforged export
/wforged import <WFGDB7 or WFGDB6 string>
/wforged sync
/wforged debug
/wforged retry
/wforged reset
```

## Troubleshooting

- Use `/reload` after installing or updating the addon.
- If old or invalid data is present, use `Reset data & Reload UI` in the developer view.
- Enable `Show logs` and inspect `Import record`, `Import decoded`, and `Import stored` messages when testing imports.
- Map locations are only shown when the item has valid loot coordinates.
- Item metadata may be delayed while the client loads item information.

## Development

Technical project notes, data model details, sync format, and test information are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## CurseForge releases

Push to `main` or `master` after updating the version in `package.json`. The `Release to CurseForge` workflow creates the matching GitHub Release, generates its changelog from commits, builds the ZIP, and uploads it automatically.

To redeploy the same version, run the workflow manually from GitHub Actions and enable `force_deploy`.

Configure these repository secrets before using the workflow:

- `CURSEFORGE_API_TOKEN`
- `CURSEFORGE_PROJECT_ID`
