--- @brief [[
--- cfg — buffer configuration directives.
--- @brief ]]

-- @@@fluxtags.cfg
-- @##tagkind


local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("fluxtags.common")
local support = require("fluxtags.kind_support")

local M = {}

---@alias FluxtagsCfgModuleCfg table<string, string|vim.api.keyset.highlight>

---@class CfgDirective
---@field s number
---@field e number
---@field key string
---@field value string
---@field tag_end number

---@class CfgDirectiveSpec
---@field key string
---@field description string

local descriptions = {
  ft = "Set the buffer filetype (e.g., ft(lua))",
  conceallevel = "Set conceallevel for this buffer (0-3)",
  fluxtags = "Disable all fluxtags processing (off)",
  fluxtags_hl = "Disable highlighting in regions (e.g., fluxtags_hl(off/on))",
  fluxtags_reg = "Disable tag registration in regions (e.g., fluxtags_reg(off/on))",
  modeline = "Execute an arbitrary Ex command",
}

local handlers = {
  ft = function(value, bufnr)
    vim.bo[bufnr].filetype = value
  end,
  conceallevel = function(value, bufnr)
    local level = tonumber(value) or 0
    for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
      if vim.api.nvim_win_is_valid(winid) then
        vim.wo[winid].conceallevel = level
      end
    end
  end,
  fluxtags = function(value, bufnr)
    if value == "off" then
      vim.b[bufnr].fluxtags_disabled = true
    end
  end,
  fluxtags_hl = function()
  end,
  fluxtags_reg = function()
  end,
  modeline = function(value, bufnr)
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, value)
    end)
  end,
}

---@return string[]
local function registry_known_keys()
  local keys = {}
  for key in pairs(handlers) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

---@return CfgDirectiveSpec[]
local function registry_info()
  local directives = {}
  for key in pairs(handlers) do
    table.insert(directives, {
      key = key,
      description = descriptions[key] or "No description available",
    })
  end
  table.sort(directives, function(a, b)
    return a.key < b.key
  end)
  return directives
end

---@param key string
---@param handler fun(value: string, bufnr: number)
---@param description? string
local function registry_register(key, handler, description)
  handlers[key] = handler
  if description then
    descriptions[key] = description
  end
end

---@param key string
---@return boolean
local function registry_has(key)
  return handlers[key] ~= nil
end

---@param key string
---@param value string
---@param bufnr number
---@return boolean ok
---@return string? err
local function registry_exec(key, value, bufnr)
  local handler = handlers[key]
  if not handler then
    return false, "unknown handler"
  end
  local ok, err = pcall(handler, value, bufnr)
  return ok, ok and nil or tostring(err)
end

---@param line string
---@param search_pattern string
---@param parse_args boolean
---@return CfgDirective[]
local function parse_cfg_line(line, search_pattern, parse_args)
  local directives = {}
  local search_from = 1

  while true do
    local s, e, key = line:find(search_pattern, search_from)
    if not s then
      break
    end

    local value, tag_end = "", e
    if parse_args then
      local args = line:sub(e + 1):match("^%b()")
      if args then
        value = args:sub(2, -2)
        tag_end = e + #args
      end
    end
    table.insert(directives, {
      s = s,
      e = e,
      key = key,
      value = value,
      tag_end = tag_end,
    })

    search_from = e + 1
  end

  return directives
end

---@param lines string[]
---@param parse_line fun(line:string): CfgDirective[]
---@param directive_name string
---@return table[]
local function cfg_disabled_intervals(lines, parse_line, directive_name)
  local intervals, is_off, start_pos = {}, false, nil

  for lnum0, line in ipairs(lines) do
    for _, item in ipairs(parse_line(line)) do
      if item.key == directive_name then
        if item.value == "off" and not is_off then
          is_off = true
          start_pos = { lnum0 - 1, item.tag_end }
        elseif item.value == "on" and is_off then
          is_off = false
          table.insert(intervals, { start_pos[1], start_pos[2], lnum0 - 1, item.s - 1 })
          start_pos = nil
        end
      end
    end
  end

  if is_off then
    table.insert(intervals, { start_pos[1], start_pos[2], math.huge, math.huge })
  end

  return intervals
end

--- Return all registered cfg directive keys from the global registry.
---
---@return string[]
function M.known_keys()
  return registry_known_keys()
end

--- Return cfg directive metadata for preview/listing.
---
---@return {key: string, description: string}[]
function M.get_directives_info()
  return registry_info()
end

--- Register or replace a cfg handler and optional docs.
---
---@param key string
---@param handler fun(value: string, bufnr: number)
---@param description? string
function M.register_handler(key, handler, description)
  registry_register(key, handler, description)
end

--- Register the `cfg` tag kind.
---
--- Parses `$$$key(value)` style directives at file entry and applies handlers.
--- Invalid directives produce diagnostics and valid directives can be listed via
--- `:FTagsCfgList`.
---
---@param fluxtags table
---@return nil
function M.register(fluxtags)
  local cfg, opts = kind_common.resolve_kind_config(
    fluxtags,
    "cfg",
    { name = "cfg", hl_group = "FluxTagCfg", open = " $$$" },
    prefix_util.default_comment_prefix_patterns
  )

  local base_pattern = " %$%$%$([%w_]+)"
  local pattern = cfg.pattern
  local search_pattern = pattern or base_pattern
  local parse_args = not pattern
  local prefix_patterns = opts.comment_prefix_patterns
  local open = opts.open
  local kind_name = opts.name
  local cfg_diag_ns = fluxtags.utils.make_diag_ns("cfg")

  ---@param line string
  ---@return CfgDirective[]
  local function parse_line(line)
    return parse_cfg_line(line, search_pattern, parse_args)
  end

  local kind = tag_kind.builder({
    name = kind_name,
    pattern = pattern or base_pattern,
    hl_group = opts.hl_group,
    priority = opts.priority,
    save_to_tagfile = false,
    extract_name = function(match)
      return match
    end,
    on_jump = function()
      return false
    end,
  }):with_on_enter(function(bufnr, lines)
    for _, line in ipairs(lines) do
      for _, item in ipairs(parse_line(line)) do
        local ok, err = registry_exec(item.key, item.value, bufnr)
        if not ok and err and err ~= "unknown handler" then
          vim.notify("fluxtags cfg: " .. item.key .. ": " .. err, vim.log.levels.WARN)
        end
      end
    end
  end):build()

  function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
    local priority = self.priority or 1100
    local conceal_char = cfg.conceal_open or open:sub(1, 1)

    for _, item in ipairs(parse_line(line)) do
      local prefix_start, prefix_text = prefix_util.find_prefix(line, item.s, prefix_patterns)
      local col0 = prefix_start - 1
      local open_len = #prefix_text + #open

      if not (is_disabled and is_disabled(lnum, col0)) then
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + open_len,
          conceal = conceal_char,
          hl_group = self.hl_group,
          priority = priority,
        })
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + open_len, {
          end_col = item.tag_end,
          hl_group = self.hl_group,
          priority = priority,
        })
      end
    end
  end

  function kind:apply_diagnostics(bufnr, lines, is_disabled)
    local diags = {}
    local priority = (self.priority or 1100) + 10

    for lnum0, line in ipairs(lines) do
      for _, item in ipairs(parse_line(line)) do
        local prefix_start, prefix_text = prefix_util.find_prefix(line, item.s, prefix_patterns)
        local col0 = prefix_start - 1
        if not (is_disabled and is_disabled(lnum0 - 1, col0)) and not registry_has(item.key) then
          local key_col0 = col0 + #prefix_text + #open
          local key_end = key_col0 + #item.key
          support.error_extmark(bufnr, fluxtags.utils.ns, lnum0 - 1, col0, item.tag_end, priority)
          support.push_diag(
            diags,
            bufnr,
            lnum0 - 1,
            key_col0,
            key_end,
            vim.diagnostic.severity.ERROR,
            "fluxtags.cfg",
            "Unknown cfg directive: " .. item.key
          )
        end
      end
    end

    support.publish_diags(bufnr, cfg_diag_ns, diags, fluxtags.utils.set_diagnostics)
  end

  function kind:get_disabled_intervals(lines, directive_name)
    return cfg_disabled_intervals(lines, parse_line, directive_name)
  end

  fluxtags.register_kind(kind)
end

return M
