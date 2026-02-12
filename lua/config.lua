--- @brief [[
---     Configuration module for tagflux
---
---     Defines both global configuration and per-tagkind configuration.
---     Each tag kind has its own tagfile with default paths based on kind name.
--- @brief ]]

local M = {}


  --- @class KindConfig
  --- @field name string Unique name of this tag kind
  --- @field tagfile string? @type global tagfile for this kind (nil = not used; default "{stdpath_data}/tagflux.{kind}.tags)" default "{stdpath_data}/tagflux.")
  --- @field filetypes_inc? string[] Filetypes to track (empty = all)
  --- @field filetypes_exc? string[] Filetypes to exclude (empty = none)
  --- @field hl_group? string Highlight group (nil = not applicable) default FluxTag{name}
  ---
  ---  Private fields: prefix with underscore for any field marked @private in docstring


--- @class GlobalConfig
--- @field filetypes_inc? string[] 
--- @field filetypes_exc? string[]



--- Global default configuration
--- @type GlobalConfig
M.global_defaults = {
    filetypes_inc = {},
    filetypes_exc = {}
}


---Generate default tagfile path for a tag kind
---@param kind string Tag kind name
---@return string tagfile_path Path to tagfile based on kind name
---
local function default_tagfile(kind)
  return vim.fn.stdpath("data") .. "/fluxtags." .. kind .. ".tags"
end

---Setup default highlight groups
---@private
local function setup_default_highlights()
  vim.api.nvim_set_hl(0, "FluxTagMarks", { link = "Error" })
  vim.api.nvim_set_hl(0, "FluxTagRef", { link = "Character" })
  vim.api.nvim_set_hl(0, "FluxTagBib", { link = "String" })
  vim.api.nvim_set_hl(0, "FluxTagOg", { link = "Warning" })
  vim.api.nvim_set_hl(0, "FluxTagCfg", { link = "Label" })
end

---Setup default highlight groups
---@private
local function setup_default_highlights()
  vim.api.nvim_set_hl(0, "FluxTagMarks", { link = "Error" })
  vim.api.nvim_set_hl(0, "FluxTagRef", { link = "Character" })
  vim.api.nvim_set_hl(0, "FluxTagBib", { link = "String" })
  vim.api.nvim_set_hl(0, "FluxTagOg", { link = "Warning" })
  vim.api.nvim_set_hl(0, "FluxTagCfg", { link = "Label" })
end

-- Setup highlights on module load
setup_default_highlights()

  --- Initialize KindConfig with default values
  --- @param config table
  --- @return table
  function M.init(config)
    local defaults = {
      name = config.name or "",
      tagfile = config.tagfile or default_tagfile(config.name),
      filetypes_inc = config.filetypes_inc or {},
      filetypes_exc = config.filetypes_exc or {},
      hl_group = config.hl_group or "FluxTag" .. config.name
    }
    return defaults
  end

---Default configuration for each tag kind
---@type table<string, KindConfig>
M.defaults = {
  marks = {
    name = "marks",
    hl_group = "TagmarkDefinition",
    tagfile = default_tagfile("marks"),
  },
  ref = {
    name = "ref",
    hl_group = "TagmarkReference",
    tagfile = default_tagfile("ref"),
  },
  bib = {
    name = "bib",
    hl_group = "TagmarkBib",
    tagfile = default_tagfile("bib"),
  },
  og = {
    name = "og",
    hl_group = "TagmarkOg",
    tagfile = default_tagfile("og"),
  },
  hl = {
    name = "hl",
  },
  cfg = {
    name = "cfg",
    hl_group = "TagmarkCfg",
    tagfile = nil,  -- doesn't use tagfile
  },
}

--- Get configuration for a specific tag kind
--- @param kind string Tag kind name
--- @param user_config? table<string, TagKindConfig> User-provided overrides
--- @return TagKindConfig config Configuration for the tag kind
function M.get(kind, user_config)
  local default = M.defaults[kind] or {}
  local user = (user_config and user_config[kind]) or {}
  return vim.tbl_deep_extend("force", default, user)
end

--- Get tagfile path for a tag kind
--- @param kind string Tag kind name
--- @param user_config? table<string, TagKindConfig> User-provided overrides
--- @return string|nil tagfile_path Path to use for this tag kind (nil if not used)

function M.get_tagfile(kind, user_config)
  local config = M.get(kind, user_config)
  return config.tagfile
end

--- Get default tagfile path for a tag kind
--- @param kind string Tag kind name
--- @return string tagfile_path Default path to tagfile
 
function M.default_tagfile(kind)
  return default_tagfile(kind)
end

--- Get highlight group for a tag kind
--- @param kind string Tag kind name
--- @param user_config? table<string, TagKindConfig> User-provided overrides
--- @return string hl_group Highlight group name
---
function M.get_hl_group(kind, user_config)
  local config = M.get(kind, user_config)
  return config.hl_group
end

return M
