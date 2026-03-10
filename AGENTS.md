# fluxtags.nvim - Agent Guidelines

## Project Overview

fluxtags.nvim is a Neovim plugin that manages custom tags with multiple
tag kinds (marks, refs, links, hashtags, highlights, and config directives).

## Repository Layout

- Main entry point: `lua/fluxtags.lua`
- Configuration: `lua/fluxtags_config.lua`
- TagKind base: `lua/tag_kind.lua`
- Tag kind modules: `lua/tagkinds/*.lua`
- Autocmds/commands: `lua/fluxtags/{autocmds,commands}.lua`

## Optional Dependencies

- `telescope.nvim` is used for tag list pickers when available.
- If telescope is not installed, tag lists are shown via `vim.notify`.

## Tag Kinds

- `mark` - tag definitions/anchors
- `ref` - references to marks
- `refog` - reference-only links to saved og hashtags (`#|#||<name>||`)
- `bib` - URLs, files, and vim help links
- `og` - hashtags for cross-file navigation (syntax: `@##<name>`)
- `hl` - inline highlighting
- `cfg` - buffer configuration directives

## Configuration and Defaults

- Global defaults live in `lua/fluxtags_config.lua`.
- Each kind gets a default tagfile at `stdpath("data")` unless `save_to_tagfile` is false.
- Highlight groups are linked on startup and can be overridden via `setup({ highlights = ... })`.

## Build, Lint, Test

There are no build, lint, or test workflows defined in this repository.
Use Neovim to load the plugin and exercise behavior manually.

- Build: none
- Lint: none (do not auto-format beyond whitespace cleanup)
- Test: none
- Single test: not applicable

If you add a workflow, document the exact command here and include the
single-test invocation pattern if the test runner supports it.

## Style Source of Truth

All style, formatting, naming, and code-architecture rules live in
`docs/STYLE_GUIDELINES.md`. Do not duplicate style rules in this file.

## Behavior Notes

- No external dependencies besides Neovim.
- Optional integration with Telescope (when available).
- `vim.ui.select` is used as fallback.
- Block tags support optional comment prefixes (`--`, `#`, `//`, `;`, `/*`, `<!--`).

## Common Workflows

- Manual verification: open a file with tags and use plugin commands to jump.
- Tagfiles are plain text and stored under `stdpath("data")` by default.
- Tag highlighting uses extmarks under the `fluxtags` namespace.
- Buffer initialization happens on enter and on scheduled refresh.
- On save, fluxtags reports tagfile changes when present (`+added -removed ~modified`).
- Jumping to a tag reuses an already open window in the current tab when possible.

## Fluxtags Workflow For Coding Agents

- Use fluxtags to leave lightweight cross-reference anchors in the code you touch, not as general prose notes.
- Prefer comment-prefixed block tags so the code stays valid in every language.
- Add `@@@name` marks at stable definitions: public functions, important state transitions, config entry points, parser stages, and other jump targets worth revisiting.
- Add `/@@name` refs near callers, related helpers, edge-case handling, and tests that depend on a marked definition.
- Use dotted names for hierarchy when it improves scanability, such as `@@@picker.render` and `/@@picker.render`.
- Use `@##topic` og tags for broader themes that span many files, such as `@##parsing`, `@##diagnostics`, or `@##queue-flow`.
- Use `#|#||topic||` when you want to point at an existing og topic without creating another canonical occurrence.
- Use `///<target>` sparingly for external docs, help topics, or file paths that materially help future navigation.
- Do not add `hl` or `cfg` tags unless the change itself is about highlighting or per-buffer behavior.
- Keep names stable across refactors. If you rename or move a marked concept, update both the mark and nearby refs in the same change.
- Do not tag every function. Tag only the seams another agent will likely jump between.
- Before finishing a task that adds or changes tags, run `:FTagsUpdate` or `:FTagsSave` during manual verification when possible.

### Recommended Patterns

- Definition anchor: `-- @@@commands.list`
- Call-site reference: `-- /@@commands.list`
- Shared concern: `-- @##picker-flow`
- Reference-only shared concern: `-- #|#||picker-flow||`
- External help/doc link: `-- ///vim.ui.select`

### Naming Guidelines

- Prefer repo-specific names over generic names like `init`, `handler`, or `utils`.
- Use one canonical mark for each concept, then point to it from related files with refs.
- Keep topic tags short and thematic; keep mark names specific and locational.
- When adding tests, add refs to the production mark they exercise when that relationship is not already obvious.

## Commands and Pickers

- `:FTagsList [kind]` opens a picker of saved tags; optional `kind` filters results.
- `:FTagsUpdate` or `:FTagsSave` persists tags for the current buffer.
- `:FTagsLoad` loads saved tags into memory; `:FTagsPrune` removes stale tags.
- `:FTagsCfgList` lists all known cfg directive keys.
- `:FTagsPreview [kind]` shows syntax/usage for all kinds or one selected kind.

## Git Commit Style

- Short, present-tense messages.
- Example: `add tag cache`, `fix mark jump`.

## Cursor and Copilot Rules

- No `.cursor/rules`, `.cursorrules`, or `.github/copilot-instructions.md` found.

## Agent Job Lists

See `docs/TODO.md` and `docs/BUGS.md` for discrete jobs ready for assignment.

## Safety

- Do not delete or overwrite user data.
- Never run destructive git commands without explicit request.
- Preserve unrelated changes in the worktree.
