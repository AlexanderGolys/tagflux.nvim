---@brief [[
--- Configuration module for tagflux
---
--- Defines both global configuration and per-tagkind configuration.
--- Each tag kind has its own tagfile with default paths based on kind name.
---@brief ]]

local M = {}

---@class GlobalConfig
---@field update_on_save boolean Whether to update tags on BufWritePost
---@field filetypes string[]|nil Filetypes to track (nil = all)

---Global default configuration
---@type GlobalConfig
M.global_defaults = {
  update_on_save = true,
  filetypes = nil,
}

---@class TagKindConfig
---@field kind string Tag kind name (used for tagfile naming)
---@field hl_group string Highlight group name for this tag kind
---@field tagfile string|nil Path to tag file for this kind (nil if not used)

---Generate default tagfile path for a tag kind
---@param kind string Tag kind name
---@return string tagfile_path Path to tagfile based on kind name
local function default_tagfile(kind)
  return vim.fn.stdpath("data") .. "/tagflux." .. kind .. ".tags"
end

---Setup default highlight groups
---@private
local function setup_default_highlights()
  vim.api.nvim_set_hl(0, "TagmarkDefinition", { link = "Define" })
  vim.api.nvim_set_hl(0, "TagmarkReference", { link = "Tag" })
  vim.api.nvim_set_hl(0, "TagmarkBib", { link = "Underlined" })
  vim.api.nvim_set_hl(0, "TagmarkOg", { link = "Label" })
  vim.api.nvim_set_hl(0, "TagmarkCfg", { link = "Comment" })
end

-- Setup highlights on module load
setup_default_highlights()

---Default configuration for each tag kind
---@type table<string, TagKindConfig>
M.defaults = {
  marks = {
    kind = "marks",
    hl_group = "TagmarkDefinition",
    tagfile = default_tagfile("marks"),
  },
  ref = {
    kind = "ref",
    hl_group = "TagmarkReference",
    tagfile = default_tagfile("ref"),
  },
  bib = {
    kind = "bib",
    hl_group = "TagmarkBib",
    tagfile = default_tagfile("bib"),
  },
  og = {
    kind = "og",
    hl_group = "TagmarkOg",
    tagfile = default_tagfile("og"),
  },
  hl = {
    kind = "hl",
    hl_group = "",  -- uses dynamic highlight groups
    tagfile = nil,  -- doesn't use tagfile
  },
  cfg = {
    kind = "cfg",
    hl_group = "TagmarkCfg",
    tagfile = nil,  -- doesn't use tagfile
  },
}

---Get configuration for a specific tag kind
---@param kind string Tag kind name
---@param user_config? table<string, TagKindConfig> User-provided overrides
---@return TagKindConfig config Configuration for the tag kind
function M.get(kind, user_config)
  local default = M.defaults[kind] or {}
  local user = (user_config and user_config[kind]) or {}
  return vim.tbl_deep_extend("force", default, user)
end

---Get tagfile path for a tag kind
---@param kind string Tag kind name
---@param user_config? table<string, TagKindConfig> User-provided overrides
---@return string|nil tagfile_path Path to use for this tag kind (nil if not used)
function M.get_tagfile(kind, user_config)
  local config = M.get(kind, user_config)
  return config.tagfile
end

---Get default tagfile path for a tag kind
---@param kind string Tag kind name
---@return string tagfile_path Default path to tagfile
function M.default_tagfile(kind)
  return default_tagfile(kind)
end

---Get highlight group for a tag kind
---@param kind string Tag kind name
---@param user_config? table<string, TagKindConfig> User-provided overrides
---@return string hl_group Highlight group name
function M.get_hl_group(kind, user_config)
  local config = M.get(kind, user_config)
  return config.hl_group
end

return M
