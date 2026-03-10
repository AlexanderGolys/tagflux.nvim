# CLAUDE.md

See `AGENTS.md` for the full repository workflow, safety rules, and layout.

## Fluxtags Workflow For Claude

- Use comment-prefixed fluxtags to cross-reference the code you add or modify.
- Prefer `@@@name` marks at stable definitions and `/@@name` refs at important callers, helpers, and tests.
- Use dotted names when helpful, such as `@@@commands.list` and `/@@commands.list`.
- Use `@##topic` for cross-file themes and `#|#||topic||` when referring to an existing topic without creating another primary occurrence.
- Use `///<target>` only for genuinely useful docs, help topics, or paths.
- Avoid tagging trivial local helpers or every touched function; focus on navigation seams future agents will revisit.
- Keep mark and topic names stable during refactors, and update related refs in the same change.
- After adding or changing tags, run `:FTagsUpdate` or `:FTagsSave` during manual verification when possible.

## Quick Examples

- `-- @@@picker.render`
- `-- /@@picker.render`
- `-- @##queue-flow`
- `-- #|#||queue-flow||`
- `-- ///vim.ui.select`
