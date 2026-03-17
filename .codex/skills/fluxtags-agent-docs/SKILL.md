---
name: fluxtags-agent-docs
description: Document codebases with fluxtags tags and generate AGENTS.md navigation instructions. Use when setting up fluxtags conventions for a new project or updating agent documentation.
---

# Fluxtags Agent Docs

## Overview

This skill teaches coding agents how to document codebases using fluxtags and generate clear AGENTS.md prompts that guide future agents to navigate via tags.

## Purpose

Fluxtags provides lightweight cross-reference anchors for codebases. This skill helps you:

1. Add meaningful tags to code you create or modify
2. Generate AGENTS.md sections that explain tag usage
3. Create a navigation mesh that lets future agents jump between related concepts

## Tag Kinds

| Kind | Syntax | Purpose | Persisted |
|------|--------|---------|-----------|
| `mark` | `@@@name` | Definition anchor (one per concept) | Yes |
| `ref` | `/@@name` | Reference to a mark | No |
| `og` | `@##topic` | Cross-file topic hashtag | Yes |
| `refog` | `#|#||topic||` | Reference-only link to og topic | No |
| `bib` | `///<target>` | External link (URL, file, help) | No |
| `hl` | `==text==` | Inline highlighting | No |
| `cfg` | `@!<directive>` | Buffer config directive | No |

## Comment Prefixes

Fluxtags recognizes block tags with optional comment prefixes:

```
-- @@@commands.list      (Lua)
# @@@config.entry        (Python, shell)
// @@@handler.init       (C, C++, JS)
; @@@macro.expand       (ASM, config
/* @@@state.parse */     (C block style)
<!-- @@@component -->     (HTML, XML)
```

Always use comment-prefixed tags to keep the code syntactically valid.

## Adding Tags While Working

### Definition Anchors (marks)

Add `@@@name` at stable, public locations:

```lua
-- @@@picker.render
local function render(items)
    ...
end
```

Place marks at:
- Public function definitions
- Important state transitions
- Config entry points
- Parser stages
- Key decision branches
- Test fixtures that mirror production

### References (refs)

Add `/@@name` near callers and related code:

```lua
-- /@@picker.render
local result = render(filtered_items)
```

Place refs at:
- Call sites
- Edge-case handlers
- Tests exercising a marked definition
- Helper functions supporting a marked concept

### Topic Tags (og)

Add `@##topic` for themes spanning many files:

```lua
-- @##parsing
local tokens = tokenize(input)

-- @##diagnostics
vim.diagnostic.config(opts)
```

Use topics for:
- Architectural concerns (`@##architecture`, `@##data-flow`)
- Feature families (`@##completion`, `@##highlights`)
- Cross-cutting concerns (`@##error-handling`, `@##logging`)

### Reference-Only Topics (refog)

Use `#|#||topic||` when pointing at an og without creating a new canonical occurrence:

```lua
-- #|#||picker-render-flow||
-- This function participates in the picker render cycle.
```

Use sparingly - prefer adding refs to marks instead.

### External Links (bib)

Use `///<target>` for:
- vim help: `///vim.ui.select`
- URLs: `///https://neovim.io/doc/user/lua.html`
- Files: `///~/.config/nvim/init.lua`

## Naming Conventions

### Mark Names

- Prefer repo-specific names: `@@@picker.render` over `@@@main`
- Use dotted hierarchy when helpful: `@@@config.options.validate`
- One canonical mark per concept; refs point to it from other files
- Keep names stable across refactors

### Topic Names

- Short and thematic: `@##diagnostics` over `@##diagnostic-system`
- Lowercase with hyphens: `@##data-flow` not `@##DataFlow`
- One word when possible: `@##queue` over `@##job-queue`

### Anti-Patterns

Avoid:
- Generic names: `init`, `handler`, `utils`
- Tagging everything (only tag seams worth revisiting)
- Unstable names that change during refactors

## AGENTS.md Section Template

When documenting a codebase that uses fluxtags, add a section like:

```markdown
## Fluxtags Workflow For Coding Agents

- Use fluxtags to leave lightweight cross-reference anchors in the code you touch,
  not as general prose notes.
- Prefer comment-prefixed block tags so the code stays valid.
- Add `@@@name` marks at stable definitions: public functions, important state
  transitions, config entry points.
- Add `/@@name` refs near callers, related helpers, edge-case handling.
- Use dotted names for hierarchy: `@@@picker.render`, `/@@picker.render`.
- Use `@##topic` og tags for broader themes: `@##parsing`, `@##diagnostics`.
- Use `#|#||topic||` to reference og topics without creating another occurrence.
- Use `///<target>` sparingly for external docs, help, or file paths.
- Do not add `hl` or `cfg` tags unless the change is about highlighting or config.
- Keep names stable across refactors; update marks and refs together.
- Do not tag every function; only tag seams another agent will likely jump between.
- Before finishing, run `:FTagsUpdate` or `:FTagsSave` during manual verification.

### Recommended Patterns

- Definition anchor: `-- @@@commands.list`
- Call-site reference: `-- /@@commands.list`
- Shared concern: `-- @##picker-flow`
- Reference-only concern: `-- #|#||picker-flow||`
- External help/doc: `-- ///vim.ui.select`

### Naming Guidelines

- Prefer repo-specific names over generic names like `init`, `handler`, `utils`.
- One canonical mark per concept; point to it from related files with refs.
- Keep topic tags short; keep mark names specific and locational.
- When adding tests, add refs to the production mark they exercise.
```

## Navigation Commands

| Command | Purpose |
|---------|---------|
| `:FTagsList [kind]` | Open picker for saved tags (filtered by kind) |
| `:FTagsUpdate` | Persist tags for current buffer |
| `:FTagsSave` | Same as `:FTagsUpdate` |
| `:FTagsLoad` | Load saved tags into memory |
| `:FTagsPrune` | Remove stale tags |
| `:FTagsCfgList` | List known cfg directives |
| `:FTagsPreview [kind]` | Show syntax/usage for a kind |

## Workflow

### When Creating New Files

1. Add marks at public entry points
2. Add refs to related existing marks
3. Add og tags for cross-cutting concerns

### When Modifying Existing Files

1. Find existing marks (search `@@@`)
2. Keep mark names stable
3. Add refs near your changes if they relate to existing marks
4. Add marks only for genuinely new public concepts

### When Refactoring

1. Update the mark location if moving a definition
2. Update all refs that pointed to the old location
3. Preserve mark names when possible
4. Run `:FTagsUpdate` after reorganization

## Checking Your Work

After adding tags:

1. Open a tagged file in Neovim with fluxtags loaded
2. Run `:FTagsUpdate` to persist tags
3. Run `:FTagsList` to see saved tags
4. Verify marks and refs appear correctly
5. Check that jumping works with `Ctrl-]` on a ref

## Resources

### scripts/

None required - fluxtags is a Neovim plugin.

### references/

None required - all documentation is in this skill.

---

## Summary

- Add `@@@name` at definitions, `/@@name` near callers
- Use `@##topic` for cross-file themes
- Keep names stable and specific
- Prefer comment-prefixed tags
- Run `:FTagsUpdate` before finishing