# Wforged Agent Rules

## Commits

- Group changes by feature or independent bug fix.
- Do not create a new commit for every clarification or correction of a feature already being developed.
- Amend the relevant local commit, or squash related commits before pushing.
- Use meaningful conventional commit names such as `feat(sync): ...`, `fix(ui): ...`, and `chore(tooling): ...`.
- Do not push automatically. Push only when explicitly requested.
- Never modify, amend, or rewrite merge commits. Leave merge commits intact and place later fixes in a new follow-up commit or a non-merge commit that already owns the affected change.

## Verification

- Before committing addon changes, run `npm run check` and `npm run unit`.
- Use `npm run copy-local` to copy the addon into the configured local WoW client for manual testing.
- Keep the local SavedVariables backup files outside Git; never add them to commits.
- When changing the package version, update the TOC through `node scripts/sync-version.js` and verify the build with `npm run build`.

## Data Safety

- Do not delete or reset user database backups without explicit confirmation.
- Preserve newer item observations and locations when merging imported or shared data.
- Treat collector/friend data receiving as opt-in unless the user explicitly changes that behavior.
