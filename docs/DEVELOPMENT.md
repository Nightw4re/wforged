# Wforged Development Notes

## Project

Wforged is a beta Worldforged data collection addon for World of Warcraft. The addon stores item observations locally in the account-wide `WforgedDB` SavedVariable and optionally shares compact observations through guild addon messages.

## Local workflow

- `npm run check` validates the addon source structure and Lua files.
- `npm run unit` runs the Node.js regression tests.
- `npm run deploy` copies the addon to the configured local game client.
- `npm test` runs check, unit tests, and deploy in that order.
- `npm run build` creates `dist/Wforged-1.0.0.zip`.

The deployment target is configured locally by the deployment script.

## Data model

The database is account-wide and shared between characters. A base item can have multiple scaled or upgraded variants. The preferred snapshot is selected by effective item level, upgrade level, and observation time. An upgrade can resolve its source item and inherit the original loot location.

Inventory, equipped, vendor, and upgrade observations do not create loot locations. A location is recorded only when the item is actually looted in the world.

## Compact sync format

The current format is `WFGDB6` with `WFG6` records:

```text
WFGDB6;WFG6|itemId|mapId|x|y|timestamp;WFG6|itemId||timestamp
```

The payload contains only item ID, location, coordinates, and observation time. Item names, links, tooltip data, stats, and quality are resolved locally by the receiving client. Import is batched to avoid blocking the game client. Import merges data and never deletes existing records.

Guild broadcasts use the same single-record `WFG6` payload. Sending and receiving are independently configurable. A message sent by the current player is logged and ignored to prevent self-duplication.

## Runtime pipeline

1. Loot chat or `LOOT_OPENED` identifies a candidate item.
2. The tooltip must contain the `Worldforged` marker.
3. The item waits for item information if the client cache is not ready.
4. Tooltip data, stats, quality, level, and location are stored.
5. The same finalization path is used for imported item metadata.
6. Search and map views refresh when metadata becomes available.

## Tests

The tests use the real exported 30-record dataset as a regression fixture. They cover located and locationless records, empty fields, invalid IDs, old headers, large batches, coordinate preservation, timestamp handling, and `Show all map items` visibility rules.

Runtime debugging uses the `Show logs` setting. Important import messages are `Import record`, `Import decoded`, and `Import stored`. Map diagnostics use `Map debug context`.

## Known client constraints

- The target client does not expose every modern WoW map API.
- Some map IDs require explicit zone-name mapping.
- Item metadata can arrive asynchronously through `GET_ITEM_INFO_RECEIVED`.
- ElvUI is optional; UI code must work with the default client UI as well.
