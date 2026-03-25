<F13># fluxtags.nvim

A lightweight tagging system for Neovim that lets you create marks, references, links, and hashtags across your files with seamless navigation.

## Features

- **7 tag types** — mark, ref, refog, bib, og, hl, and cfg
- **Cross-file navigation** — jump between tags using Ctrl-]
- **Smart picker** — when a tag has multiple locations, choose which one to visit
- **Parent tag resolution** — `@config.defaults` automatically resolves to `@config`
- **Persistent storage** — tags are saved and available across editor sessions
- **Comment-aware** — works with any comment syntax (Lua `--`, Python `#`, C `//`, etc.)
- **Visual feedback** — save notifications show what changed (`+2 -1 ~3`)

## Installation

### lazy.nvim

```config
{
  "flux/nvim-plugins/fluxtags.nvim",
  config = function()
    require("fluxtags").setup()
  end,
```

### packer.nvim

```config
use "flux/nvim-plugins/fluxtags.nvim"
```

Then in your `init.lua`:

```config
require("fluxtags").setup()
```

### vim-plug

```vim
Plug 'flux/nvim-plugins/fluxtags.nvim'
```
Then in your `init.lua`:

```config
require("fluxtags").setup()
```

## Quick Start

### Basic Setup

```config
require("fluxtags").setup({
  filetypes_ignore = { "help", "qf" },
  
  highlights = {
    -- Optional: customize colors
    -- FluxTagMarks = "Identifier",
  },
})
```

### Basic Usage

1. **Create a mark** — type `@@@mymark` anywhere
2. **Jump to it** — press `Ctrl-]` on `@@@mymark` or on a reference to it
3. **Reference it** — type `/@@mymark` to create a reference
4. **List all marks** — run `:FTagsList mark`

### Workflow For Coding Agents

If you use fluxtags while editing code with AI agents, this pattern works well:

- Put `@@@name` marks on stable definitions worth jumping back to.
- Put `/@@name` refs near important callers, helpers, and tests.
- Use dotted names like `@@@commands.list` when a feature has a clear hierarchy.
- Use `@##topic` for broader cross-file themes and `#|#||topic||` to refer to an existing topic without adding a new primary occurrence.
- Use `///<target>` only when a help topic, URL, or path will genuinely help the next person navigate the change.
- Prefer comment-prefixed block tags so the source stays valid in any language.
- Skip trivial helpers and obvious one-hop code paths; tag the architectural seams, not everything.

Example:

```lua
-- @@@commands.list
local function list_tags()
  return render_picker()
end

-- @##picker-flow
```

---

## Tag Types

### Mark `@@@<name>`

A named location you can jump to from anywhere in your project.

```config
-- @@@init
function init()
  print("initialized")
end

-- @@@config
local config = { ... }
```

**Jump behavior:** Ctrl-] on `@@@init` jumps to that line. Dotted marks like `@@@config.defaults` jump to the parent mark `@@@config`.

---

### Reference `/@@<name>` or `@<name>.<sub>`

Points to a mark. Two forms:
- Block: `/@@mymark`
- Inline: `@mymark.details`

```config
-- /@@init           -- block form
local init_fn = @init.function  -- inline form
```

**Jump behavior:** Ctrl-] on a reference jumps to the mark it points to.

**Parent resolution:** `@config.defaults` jumps to `@@@config` if `@@@config.defaults` doesn't exist.

---

### Link `///<target>`

Opens a URL, file, or help topic.

```config
-- ///https://neovim.io
-- ///~/.config/nvim/init.lua
-- ///vim.api.nvim_buf_set_extmark    -- opens :help
```

**Jump behavior:** Ctrl-] opens the target in your browser, file manager, or help.

---

### Hashtag `@##<name>`

Groups related content across files. Same hashtag can appear many times.

```config
@##performance
@##todo
@##api-boundary
```

**Jump behavior:** Ctrl-] opens a picker showing all occurrences of that hashtag.

---

### Reference-only Hashtag `#|#||<name>||`

References a hashtag without adding a new occurrence to the list.

```config
#|#||performance||
```

**Jump behavior:** Ctrl-] opens the hashtag picker, same as `@##`.

---

### Inline Highlight `&&&<Group>&&&<text>&&&`

Highlights text with any highlight group. Delimiters are hidden, and the
highlighted content may span multiple lines.

```config
-- &&&Error&&&FIXME: broken&&&
-- &&&WarningMsg&&&TODO: check this&&&
-- &&&Error&&&First highlighted line
-- second highlighted line&&&
```

**Jump behavior:** No jump (just visual highlighting).

---

### Buffer Config `$$$<key>(<value>)`

Sets per-file configuration.

```config
$$$ft(lua)               -- force Lua filetype
$$$conceallevel(2)       -- adjust conceal level
$$$fluxtags(off)         -- disable tags in this file
$$$modeline(set wrap)    -- run Vim command
```

---

## Configuration

### Default Setup

```config
require("fluxtags").setup()
```

### All Options

```config
require("fluxtags").setup({
  -- Limit tags to specific filetypes (empty/nil = all filetypes)
  filetypes_inc = nil,
  
  -- Skip these filetypes
  filetypes_exc = {},

  -- Override or disable plugin keymaps
  keymaps = {
    jump = "<C-]>",
  },
   
  -- Override highlight colors
  highlights = {
    -- FluxTagMarks = "Identifier",
  },
  
  -- Per-tag-type customization
  kinds = {
    -- mark = { hl_group = "MyMarkColor" },
  },

  -- Startup behavior
  startup = {
    setup_buffer = true, -- initialize current buffer on setup()
    update_tags = false, -- run a silent initial save pass
    load_tags = false,   -- preload tagfiles into memory
  },
})
```

### Highlight Groups

| Group          | Default         | Used for |
|----------------|-----------------|----------|
| `FluxTagMarks` | Pink/Red        | Marks    |
| `FluxTagRef`   | Soft red        | References |
| `FluxTagBib`   | Teal            | Links    |
| `FluxTagOg`    | Yellow          | Hashtags |
| `FluxTagCfg`   | Green           | Config directives |
| `FluxTagError` | Error color     | Errors/duplicates |

**Customize colors:**

```config
require("fluxtags").setup({
  highlights = {
    FluxTagMarks = "Identifier",
    FluxTagError = { fg = "#ff0000", bold = true },
  },
})
```

---

## Commands

| Command | What it does |
|---|---|
| `:FTagsUpdate` | Scan and persist tags from current buffer |
| `:FTagsSave` | Alias for `:FTagsUpdate` |
| `:FTagsLoad` | Reload tagfiles into memory |
| `:FTagsList [kind]` | Open picker of all saved tags with file previews when available |
| `:FTagsCfgList` | List all registered cfg directive keys and descriptions |
| `:FTagsPreview [kind]` | Show tag syntax examples |
| `:FTagsTree [file]` | Generate a project tree of marks and og tags in a temp file or notify output |
| `:FTagsPrune` | Remove stale/deleted tags from all tagfiles |
| `:FTagsClear` | Truncate all saved tagfiles |
| `:FTagsHL` | Reapply tag extmarks in current buffer |
| `:FTagsHi` | Re-link default FluxTag highlight groups |
| `:FTagsDebug` | Show matched kind info under cursor |
| `:FTagsDebugMarks` | Show all fluxtags extmarks in current buffer |
| `:FTagsDebugAtCursor` | Show extmarks covering cursor position |

---

## Navigation

Press **Ctrl-]** to jump to a tag under your cursor.

### What happens when you jump

1. If it's a **mark** → jumps directly to it
2. If it's a **reference** → jumps to the mark it points to
3. If it's a **hashtag** → shows a picker of all occurrences
4. If it's a **link** → opens in browser/file manager/help
5. If it's **highlight/config** → no action

---

## Configuration reference

### Core options

- `filetypes_whitelist` — include only these filetypes (empty/nil = all)
- `filetypes_ignore` — skip listed filetypes
- `filetypes_inc` / `filetypes_exc` — preferred aliases for include/exclude
- `keymaps.jump` — override the jump mapping, or set to `false` to disable it
- `highlights` — override any `FluxTag*` highlight group
- `kinds` — per-kind overrides (`mark`, `ref`, `refog`, `bib`, `og`, `hl`, `cfg`)
- `startup.setup_buffer` — run `setup_buffer()` for current buffer during `setup()` (default `true`)
- `startup.update_tags` — run an initial silent `update_tags()` during `setup()` (default `false`)
- `startup.load_tags` — load all tagfiles during `setup()` (default `false`)

Example:

```lua
require("fluxtags").setup({
  keymaps = {
    jump = "g]",
    -- jump = false,
  },
})
```

### Cfg directives

The built-in directives are:

- `ft(value)` — set buffer filetype
- `conceallevel(value)` — set `conceallevel` on windows containing the buffer
- `fluxtags(off)` — disable fluxtags in the buffer
- `fluxtags_hl(off/on)` — disable/enable fluxtags highlights in regions
- `fluxtags_reg(off/on)` — disable/enable tag registration in regions
- `modeline(cmd)` — run any Ex command

Use `:FTagsCfgList` to print the current list (including descriptions).

If nothing matches, Neovim's default tag behavior kicks in.

---

## Comment Support

Tags work with any comment syntax:

| Language | Syntax    | Example            |
|----------|-----------|-------------------|
| Lua      | `--`      | `-- @@@mark`      |
| Python   | `#`       | `# @@@mark`       |
| C/C++    | `//`      | `// @@@mark`      |
| HTML     | `<!--`    | `<!-- @@@mark -->` |
| Vim      | `"`       | `" @@@mark`       |

---

## Display & Visibility

Tags use special characters that simplify on screen:

| Tag Type | Raw Syntax        | On Screen |
|----------|-------------------|-----------|
| Mark     | `-- @@@name`      | `@name`   |
| Reference | `-- /@@name`    | `/@name`  |
| Link     | `-- ///url`       | `/url`    |
| Hashtag  | `@##topic`        | `#topic`  |
| Highlight | `&&&Group&&&text&&&` | `text` (styled) |
| Config   | `$$$ft(lua)`      | `$ft(lua)` |

You can disable this simplification by setting `conceallevel=0` in a file or via `:set conceallevel=0`.

---

## Troubleshooting

**Tags not showing up?**
- Run `:FTagsUpdate` to scan your file
- Check your filetype: `:set filetype?`
- Verify it's not in `filetypes_ignore`

**Picker won't open?**
- Install snacks.nvim for better pickers
- Falls back to basic Neovim menu otherwise

**Tags not saving across sessions?**
- Run `:FTagsUpdate` when you're done editing
- Check `:FTagsList` to see what's saved

**Performance slow?**
- Run `:FTagsPrune` to clean up old entries
- Reduce filetypes with `filetypes_whitelist`

---

## License

MIT
