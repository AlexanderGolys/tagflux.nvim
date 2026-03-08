
--- @brief [[
---     Configuration module for fluxtags.
---
---     Holds per-kind defaults (tagfile paths, highlight groups) and the
---     helpers that merge them with user-supplied overrides at setup time.
---     Highlight group links are (re-)applied on module load, on VimEnter,
---     and whenever the colorscheme changes.
--- @brief ]]

local M = {}

-- @@@fluxtags.config

--- @class KindConfig
--- @field name string Unique kind identifier, e.g. "mark"
--- @field tagfile? string Absolute path to the persistent tagfile; nil disables persistence
--- @field filetypes_inc? string[] Limit tag scanning to these filetypes (empty = all)
--- @field filetypes_exc? string[] Skip these filetypes even when filetypes_inc is empty
--- @field hl_group? string Highlight group name; defaults to "FluxTag" .. capitalized name

--- @class GlobalConfig
--- @field filetypes_inc? string[] Global filetype inclusion list
--- @field filetypes_exc? string[] Global filetype exclusion list

--- @type GlobalConfig
M.global_defaults = {
    filetypes_inc = {},
    filetypes_exc = {},
}

---@param kind string
---@return string
---
local function default_tagfile_path(kind)
    return vim.fn.stdpath("data") .. "/fluxtags." .. kind .. ".tags"
end

--- Link each FluxTag highlight group to a sensible built-in group.
--- Called on load, VimEnter, and ColorScheme to survive theme changes.
local function link_default_highlights()
    vim.api.nvim_set_hl(0, "FluxTagMarks", { bold = true, fg = "#FF97Aa", underline = false, nocombine = true }) 
    vim.api.nvim_set_hl(0, "FluxTagRef",   { link = "NeogitDiffDeleteHighlight", nocombine = true  })
    vim.api.nvim_set_hl(0, "FluxTagOg",    { bold = true, fg = "#F9e2af" })
    vim.api.nvim_set_hl(0, "FluxTagRefog", { underline = true, bg = "#FFD946", fg = "#FFF9DC" })
    vim.api.nvim_set_hl(0, "FluxTagCfg",   { fg = "#C2F397" })
    vim.api.nvim_set_hl(0, "FluxTagBib",   { italic = true, underline = true, fg = "#8DBEBC" })
    vim.api.nvim_set_hl(0, "FluxTagError", { link = "DiagnosticError" })
end

link_default_highlights()

--- Re-apply default highlight group links, optionally overriding with user config.
--- Exposed so autocmds and commands can call it without reaching into the closure.
---
--- @param user_highlights? table<string, string|vim.api.keyset.highlight> User overrides for FluxTag* groups
---
function M.setup_default_highlights(user_highlights)
    link_default_highlights()
    if user_highlights then
        for group_name, hl_def in pairs(user_highlights) do
            vim.api.nvim_set_hl(0, group_name, hl_def)
        end
    end
end

--- Built-in defaults for every supported tag kind.
--- Kinds that do not persist tags (hl, cfg) omit `tagfile`.
---
--- @type table<string, KindConfig>
---
M.defaults = {
    mark = { name = "mark", hl_group = "FluxTagMarks", tagfile = default_tagfile_path("mark") },
    ref  = { name = "ref",  hl_group = "FluxTagRef",   tagfile = default_tagfile_path("ref")  },
    bib  = { name = "bib",  hl_group = "FluxTagBib",   tagfile = default_tagfile_path("bib")  },
    og   = { name = "og",   hl_group = "FluxTagOg",    tagfile = default_tagfile_path("og")   },
    hl   = { name = "hl"  },
    cfg  = { name = "cfg",  hl_group = "FluxTagCfg",   tagfile = nil },
}

--- Return the merged config for a single kind, applying user overrides on top of defaults.
---
--- @param kind string Kind name
--- @param user_overrides? table<string, KindConfig> User config from setup()
--- @return KindConfig
---
function M.get(kind, user_overrides)
    local default = M.defaults[kind] or {}
    local user    = (user_overrides and user_overrides[kind]) or {}
    return vim.tbl_deep_extend("force", default, user)
end

--- Return the tagfile path for a kind after applying user overrides.
--- Returns nil for kinds that do not use a tagfile.
---
--- @param kind string
--- @param user_overrides? table<string, KindConfig>
--- @return string|nil
---
function M.get_tagfile(kind, user_overrides)
    return M.get(kind, user_overrides).tagfile
end

--- Return the default (pre-override) tagfile path for a kind.
---
--- @param kind string
--- @return string
---
function M.default_tagfile(kind)
    return default_tagfile_path(kind)
end

--- Return the highlight group name for a kind after applying user overrides.
---
--- @param kind string
--- @param user_overrides? table<string, KindConfig>
--- @return string
---
function M.get_hl_group(kind, user_overrides)
    return M.get(kind, user_overrides).hl_group
end

return M
