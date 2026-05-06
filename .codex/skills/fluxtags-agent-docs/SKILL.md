---
name: fluxtags-agent-docs
description: Document codebases with fluxtags tags and AGENTS.md guidance so coding agents create stable navigation graphs across code they write or modify. Use when setting up fluxtags conventions for a project, adding agent-maintained code navigation, or updating agent documentation for fluxtags.
---

# Fluxtags Agent Docs

Use this skill to leave a useful fluxtags graph behind while coding, and to teach future agents how to keep that graph coherent.

## Goal

Fluxtags should make a project navigable by concept, not just by filenames. Add tags only where they help another agent answer questions like:

- Where is this feature defined?
- Which callers, helpers, and tests depend on it?
- Which files participate in this cross-cutting concern?
- Which external docs or local files explain this behavior?

Do not use fluxtags as general prose notes or a replacement for normal comments.

## Core Tags

| Kind | Syntax | Use |
|------|--------|-----|
| mark | `@@@name` | Canonical definition or anchor for one stable concept |
| ref | `/@@name` | Link from a related location back to a mark |
| og | `@##topic` | Canonical occurrence of a cross-file theme |
| refog | `#|#||topic||` | Reference to an existing topic without creating another canonical occurrence |
| bib | `///<target>` | External URL, vim help topic, or local file pointer |
| cfg | `$$$directive` | Fluxtags parser behavior control |

Avoid `hl` tags unless the work is specifically about fluxtags highlighting.

## Placement Rules

Prefer comment-prefixed block tags so the host file remains valid:

```lua
-- @@@commands.list
local function list_tags(opts)
  ...
end
```

```python
# /@@commands.list
def test_lists_saved_tags():
    ...
```

Supported prefixes include `--`, `#`, `//`, `;`, `/*`, and `<!--`. Use the comment syntax native to the file you are editing.

## Build A Navigation Graph

1. Add one `@@@name` mark at the best stable definition for each concept worth revisiting.
2. Add `/@@name` refs near important callers, adapters, edge-case handlers, and tests.
3. Add `@##topic` when a theme spans multiple files and no single mark is enough.
4. Add `#|#||topic||` where a file participates in the topic but should not become another canonical occurrence.
5. Add `///<target>` only when the link materially helps future navigation.
6. When moving or renaming a concept, update the mark and all nearby refs in the same change.

Good graphs are sparse. A file with many small functions may need only one mark at the public entry point plus refs from tests or integration code.

## Naming

- Prefer repo-specific names: `@@@picker.render`, not `@@@handler`.
- Use dotted hierarchy when it helps scanning: `@@@config.defaults`, `/@@config.defaults`.
- Keep one canonical mark per concept.
- Preserve mark names across refactors when behavior stays the same.
- Use short lowercase topic names with hyphens: `@##queue-flow`, `@##diagnostics`.
- Avoid names that describe implementation accidents: `@@@utils`, `@@@new-code`, `@@@temp`.

## Project And Global Scope

Use local project scope for ordinary project tags. Use `gg:` only for anchors that should be shared globally:

```lua
-- @@@gg:shared.topic
```

Refs can target other registered projects with a project prefix:

```lua
-- /@@docs.parser.init
```

Cfg directives can adjust routing for unusual buffers:

```config
$$$ftags-project(notes)
$$$ftags-global:on
```

Use routing directives sparingly; most code should rely on the configured project root.

## AGENTS.md Guidance

When adding fluxtags conventions to a repository, add or refresh a concise AGENTS.md section that tells future agents:

- Which files are the main entry points.
- Which tag names or topic names are already canonical.
- Which commands verify the tag graph in this project.
- That agents should update marks and refs together during refactors.

Template:

```markdown
## Fluxtags Workflow For Coding Agents

- Use comment-prefixed fluxtags tags in code you touch.
- Add `@@@name` marks at stable definitions and `/@@name` refs near callers, helpers, and tests.
- Use dotted names for feature hierarchy, such as `@@@picker.render`.
- Use `@##topic` for cross-file themes and `#|#||topic||` for reference-only topic links.
- Use `///<target>` only for useful external docs, help topics, or local file pointers.
- Do not tag every function; tag concepts another agent will likely need to navigate.
- Preserve canonical names across refactors and update refs when a mark moves.
- Before finishing tag changes, run `:FTagsUpdate` or `:FTagsSave` when manual Neovim verification is practical.
```

Keep this section project-specific. Add canonical examples from the repository instead of only generic examples when they exist.

## Verification

After adding or changing tags:

1. Open a touched tagged file in Neovim with fluxtags loaded.
2. Run `:FTagsUpdate` or `:FTagsSave`.
3. Run `:FTagsList [kind]` to inspect persisted marks, og topics, and other saved entries.
4. Run `:FTagsTree` when available to inspect mark/ref and topic/refog relationships.
5. Use `Ctrl-]` on representative refs and topics to confirm jumps or pickers open correctly.
6. If cfg syntax changed or is relevant, run `:FTagsCfgList`.
7. If documenting usage for humans or agents, run `:FTagsHelp` and compare the help text to the instructions you wrote.

If headless or automated verification is all that is practical, run the repository's test command and explicitly state that interactive jump checks were not performed.

## Command Reference

| Command | Purpose |
|---------|---------|
| `:FTagsList [kind]` | Open picker for saved tags, optionally filtered by kind |
| `:FTagsUpdate` / `:FTagsSave` | Persist tags for the current buffer |
| `:FTagsLoad` | Load saved tags into memory |
| `:FTagsPrune` | Remove stale saved tags |
| `:FTagsTree` | Show project mark/ref and topic/refog relationships |
| `:FTagsCfgList` | List cfg directives with descriptions and examples |
| `:FTagsPreview [kind]` | Show syntax examples for tag kinds |
| `:FTagsHelp` | Open the complete fluxtags help panel |

## Review Checklist

- Each new mark has a reason to be a jump target.
- Important related code has refs instead of duplicate marks.
- Topic tags describe cross-file concerns, not one-off notes.
- Names are stable, specific, and consistent with nearby tags.
- AGENTS.md mentions the project-specific conventions if the project is being set up for agent use.
- Verification command output or manual checks are recorded in the final response.
