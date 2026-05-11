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
---@field syntax string
---@field example string

local descriptions = {
  ft = "Set the buffer filetype (e.g., ft(lua))",
  conceallevel = "Set conceallevel for this buffer (0-3)",
  ["ftags"] = "Enable or disable all fluxtags processing",
  ["ftags-hl"] = "Enable or disable fluxtags highlighting in a region",
  ["ftags-global"] = "Save all tags in this buffer to global tagfiles",
  ["ftags-project"] = "Treat this buffer as part of a registered fluxtags project",
  ["ftags-register"] = "Enable or disable tag registration in a region",
  exec = "Execute an arbitrary Ex command",
  fluxtags = "Disable all fluxtags processing (off)",
  fluxtags_hl = "Disable highlighting in regions (e.g., fluxtags_hl(off/on))",
  fluxtags_reg = "Disable tag registration in regions (e.g., fluxtags_reg(off/on))",
  modeline = "Execute an arbitrary Ex command",
}

local examples = {
  ft = "```config\n$$$ft(lua)\n```",
  conceallevel = "```config\n$$$conceallevel(2)\n```",
  ["ftags"] = "```config\n$$$ftags:off\n$$$ftags:on\n```",
  ["ftags-hl"] = "```config\n$$$ftags-hl:off\n...\n$$$ftags-hl:on\n```",
  ["ftags-global"] = "```config\n$$$ftags-global:on\n```",
  ["ftags-project"] = "```config\n$$$ftags-project(notes)\n```",
  ["ftags-register"] = "```config\n$$$ftags-register:off\n...\n$$$ftags-register:on\n```",
  exec = "```config\n$$$exec(set wrap)\n```",
  fluxtags = "```config\n$$$fluxtags(off)\n```",
  fluxtags_hl = "```config\n$$$fluxtags_hl(off)\n...\n$$$fluxtags_hl(on)\n```",
  fluxtags_reg = "```config\n$$$fluxtags_reg(off)\n...\n$$$fluxtags_reg(on)\n```",
  modeline = "```config\n$$$modeline(set wrap)\n```",
}

local syntax = {
  ["ftags"] = "$$$ftags:<on|off>",
  ["ftags-hl"] = "$$$ftags-hl:<on|off>",
  ["ftags-global"] = "$$$ftags-global:<on|off>",
  ["ftags-project"] = "$$$ftags-project(<name>)",
  ["ftags-register"] = "$$$ftags-register:<on|off>",
  exec = "$$$exec(<cmd>)",
}

local function set_fluxtags_enabled(value, bufnr)
  if value == "off" then
    vim.b[bufnr].fluxtags_disabled = true
  elseif value == "on" then
    vim.b[bufnr].fluxtags_disabled = false
  end
end

local function exec_cmd(value, bufnr)
  vim.api.nvim_buf_call(bufnr, function()
    pcall(vim.cmd, value)
  end)
end

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
    set_fluxtags_enabled(value, bufnr)
  end,
  ftags = function(value, bufnr)
    set_fluxtags_enabled(value, bufnr)
  end,
  fluxtags_hl = function()
  end,
  ["ftags-hl"] = function()
  end,
  ["ftags-global"] = function(value, bufnr)
    vim.b[bufnr].fluxtags_global_only = value == "on"
  end,
  ["ftags-project"] = function(value, bufnr)
    vim.b[bufnr].fluxtags_project = value ~= "" and value or nil
  end,
  fluxtags_reg = function()
  end,
  ["ftags-register"] = function()
  end,
  modeline = function(value, bufnr)
    exec_cmd(value, bufnr)
  end,
  exec = function(value, bufnr)
    exec_cmd(value, bufnr)
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
      syntax = syntax[key] or ("$$$%s(<value>)"):format(key),
      example = examples[key] or ("```config\n$$$%s(value)\n```"):format(key),
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
---@param ignored_ranges? table[]
---@return CfgDirective[]
local function parse_cfg_line(line, search_pattern, parse_args, ignored_ranges)
  local directives = {}
  local search_from = 1

  while true do
    local s, e, key = line:find(search_pattern, search_from)
    if not s then
      break
    end

    local is_ignored = false
    for _, range in ipairs(ignored_ranges or {}) do
      if s >= range[1] and s <= range[2] then
        is_ignored = true
        break
      end
    end
    if not is_ignored then
      local value, tag_end = "", e
      if parse_args then
        local args = line:sub(e + 1):match("^%b()")
        if args then
          value = args:sub(2, -2)
          tag_end = e + #args
        else
          local colon_value = line:sub(e + 1):match("^:([%w_-]+)")
          if colon_value then
            value = colon_value
            tag_end = e + #colon_value + 1
          end
        end
      end
      table.insert(directives, {
        s = s,
        e = e,
        key = key,
        value = value,
        tag_end = tag_end,
      })
    end

    search_from = e + 1
  end

  return directives
end

---@param line string
---@return boolean
local function is_markdown_fence(line)
  return line:match("^%s*```") ~= nil or line:match("^%s*~~~") ~= nil
end

---@param bufnr number
---@return boolean
local function is_markdown_buf(bufnr)
  return vim.bo[bufnr].filetype:match("markdown") ~= nil
end

---@param line string
---@return table[]
local function markdown_inline_code_ranges(line)
  local ranges = {}
  local search_from = 1
  while true do
    local s, e = line:find("`", search_from, true)
    if not s then
      break
    end
    local close_s, close_e = line:find("`", e + 1, true)
    if not close_s then
      break
    end
    table.insert(ranges, { s, close_e })
    search_from = close_e + 1
  end
  return ranges
end

---@param bufnr number
---@param lines string[]
---@return table<integer, boolean>
local function markdown_fenced_lines(bufnr, lines)
  local fenced = {}
  if not is_markdown_buf(bufnr) then
    return fenced
  end

  local in_fence = false
  for lnum0, line in ipairs(lines) do
    if is_markdown_fence(line) then
      fenced[lnum0] = true
      in_fence = not in_fence
    elseif in_fence then
      fenced[lnum0] = true
    end
  end
  return fenced
end

---@param bufnr number
---@param lnum number
---@return boolean
local function is_markdown_fenced_lnum(bufnr, lnum)
  if not is_markdown_buf(bufnr) then
    return false
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, lnum + 1, false)
  local fenced = markdown_fenced_lines(bufnr, lines)
  return fenced[lnum + 1] == true
end

---@param bufnr number
---@param lines string[]
---@param parse_line fun(line:string, ignored_ranges?:table[]): CfgDirective[]
---@return table<integer, CfgDirective[]>
local function parse_cfg_lines_for_buf(bufnr, lines, parse_line)
  local parsed = {}
  local fenced = markdown_fenced_lines(bufnr, lines)

  for lnum0, line in ipairs(lines) do
    if fenced[lnum0] then
      parsed[lnum0] = {}
    else
      local ignored_ranges = is_markdown_buf(bufnr) and markdown_inline_code_ranges(line) or nil
      parsed[lnum0] = parse_line(line, ignored_ranges)
    end
  end

  return parsed
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

  local base_pattern = "%$%$%$([%w_-]+)"
  local pattern = cfg.pattern
  local search_pattern = pattern or base_pattern
  local parse_args = not pattern
  local prefix_patterns = opts.comment_prefix_patterns
  local open = opts.open
  local kind_name = opts.name
  local cfg_diag_ns = fluxtags.utils.make_diag_ns("cfg")

  ---@param line string
  ---@param ignored_ranges? table[]
  ---@return CfgDirective[]
  local function parse_line(line, ignored_ranges)
    return parse_cfg_line(line, search_pattern, parse_args, ignored_ranges)
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
    local parsed = parse_cfg_lines_for_buf(bufnr, lines, parse_line)
    for _, items in ipairs(parsed) do
      for _, item in ipairs(items) do
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
    if is_markdown_fenced_lnum(bufnr, lnum) then
      return
    end

    local ignored_ranges = is_markdown_buf(bufnr) and markdown_inline_code_ranges(line) or nil
    for _, item in ipairs(parse_line(line, ignored_ranges)) do
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
    local parsed = parse_cfg_lines_for_buf(bufnr, lines, parse_line)

    for lnum0, line in ipairs(lines) do
      for _, item in ipairs(parsed[lnum0] or {}) do
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
