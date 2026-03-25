--- @brief [[
---   hl - inline highlight tags.
---
---   Syntax: `&&&<HlGroup>&&&<text>&&&`
---   The content may span multiple lines. All three `&&&` delimiters and the
---   group name are fully concealed so only the styled text is visible. The
---   highlight group is taken verbatim from the tag, so any valid Neovim group
---   name works (Error, WarningMsg, @keyword, DiagnosticHint, etc.).
---
---   No jump target; Ctrl-] is a no-op on hl tags.
---   Nothing is saved to a tagfile.
--- @brief ]]

-- @@@fluxtags.hl
-- @##tagkind

local tag_kind = require("tag_kind")
local prefix_util = require("fluxtags.prefix")
local kind_common = require("fluxtags.common")

local M = {}

---@param line string
---@param prefix_patterns string[]
---@return integer
---@return integer
local function find_line_prefix(line, prefix_patterns)
  for _, pattern in ipairs(prefix_patterns) do
    local start_col, end_col = line:find("(" .. pattern .. ")")
    if start_col then
      local before = line:sub(1, start_col - 1)
      if before:match("^%s*$") then
        return start_col - 1, end_col
      end
    end
  end

  return 0, 0
end

---@param bufnr integer
---@param ns integer
---@param row integer
---@param start_col integer
---@param end_col integer
---@param opts vim.api.keyset.set_extmark
local function place_range(bufnr, ns, row, start_col, end_col, opts)
  if end_col <= start_col then
    return
  end

  vim.api.nvim_buf_set_extmark(bufnr, ns, row, start_col, vim.tbl_extend("force", opts, {
    end_col = end_col,
  }))
end

---@param bufnr integer
---@param ns integer
---@param lines string[]
---@param row integer
---@param start_col integer
---@param end_row integer
---@param end_col integer
---@param group string
---@param priority integer
---@param prefix_patterns string[]
local function place_multiline_text(bufnr, ns, lines, row, start_col, end_row, end_col, group, priority, prefix_patterns)
  for current_row = row, end_row do
    local line = lines[current_row + 1]
    local text_start = start_col
    local text_end = #line

    if current_row > row then
      local prefix_col0, prefix_end = find_line_prefix(line, prefix_patterns)
      place_range(bufnr, ns, current_row, prefix_col0, prefix_end, {
        conceal = "",
        priority = priority,
      })
      text_start = prefix_end
    end

    if current_row == end_row then
      text_end = end_col
    end

    place_range(bufnr, ns, current_row, text_start, text_end, {
      hl_group = group,
      priority = priority,
    })
  end
end

--- Register the `hl` tag kind with fluxtags.
---
---@param fluxtags table The main fluxtags module table
---@return nil
function M.register(fluxtags)
  local cfg, opts = kind_common.resolve_kind_config(
    fluxtags,
    "hl",
    {
      name = "hl",
      pattern = "&&&([%w_@-]+)&&&(.-)&&&",
      open = "&&&",
      mid = "&&&",
      close = "&&&",
      conceal_open = "",
      conceal_mid = "",
      conceal_close = "",
      hl_group = "",
    },
    prefix_util.default_comment_prefix_patterns
  )
  local kind_name = opts.name
  local pattern = opts.pattern
  local open = opts.open
  local mid = opts.mid
  local close = opts.close
  local prefix_patterns = opts.comment_prefix_patterns
  local match_pattern = cfg.match_pattern or pattern
  local group_pattern = "^[%w_@-]+$"
  -- Conceal characters default to empty string = fully hidden (not just replaced).
  local conceal_open = opts.conceal_open
  local conceal_mid = opts.conceal_mid
  local conceal_close = opts.conceal_close

  local kind = tag_kind.builder({
    name = kind_name,
    pattern = pattern,
    hl_group = opts.hl_group,
    priority = opts.priority,
    save_to_tagfile = false,
    extract_name = function(match) return match end,
    on_jump = function() return false end,
  }):build()

  --- Custom extmark logic: the group name is embedded in the tag itself, so
  --- we cannot use the generic apply_extmarks path (which uses a fixed hl_group).
  --- The scanner runs once per redraw and supports content that spans lines.
  function kind:apply_extmarks(bufnr, lnum, line, ns, is_disabled)
    if lnum ~= 0 then
      return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local priority = self.priority or 1100
    local active = nil

    for row, current_line in ipairs(lines) do
      local line_index = row - 1
      local search_from = 1

      while true do
        if active then
          local prefix_col0, prefix_end = find_line_prefix(current_line, prefix_patterns)
          local text_start = prefix_end + 1
          local close_start = current_line:find(close, text_start, true)

          if close_start then
            local text_end = close_start - 1
            place_multiline_text(
              bufnr,
              ns,
              lines,
              active.text_row,
              active.text_col,
              line_index,
              text_end,
              active.group,
              priority,
              prefix_patterns
            )
            place_range(bufnr, ns, line_index, close_start - 1, close_start - 1 + #close, {
              conceal = conceal_close,
              priority = priority,
            })
            active = nil
            search_from = close_start + #close
          else
            break
          end
        else
          local match_start, match_end, group, text = current_line:find(match_pattern, search_from)
          if match_start then
            local prefix_start, prefix_text = prefix_util.find_prefix(current_line, match_start, prefix_patterns)
            local col0 = prefix_start - 1
            local open_len = #prefix_text + #open
            local prefix_len = open_len + #group + #mid
            local text_start = col0 + prefix_len
            local text_end = text_start + #text
            local close_end = text_end + #close

            if not (is_disabled and is_disabled(line_index, col0)) then
              place_range(bufnr, ns, line_index, col0, col0 + open_len, {
                conceal = conceal_open,
                priority = priority,
              })
              place_range(bufnr, ns, line_index, col0 + open_len, col0 + open_len + #group, {
                conceal = "",
                priority = priority,
              })
              place_range(bufnr, ns, line_index, col0 + open_len + #group, col0 + prefix_len, {
                conceal = conceal_mid,
                priority = priority,
              })
              place_range(bufnr, ns, line_index, text_start, text_end, {
                hl_group = group,
                priority = priority,
              })
              place_range(bufnr, ns, line_index, text_end, close_end, {
                conceal = conceal_close,
                priority = priority,
              })
            end

            search_from = match_end + 1
          else
            local open_start = current_line:find(open, search_from, true)
            if not open_start then
              break
            end

            local mid_start = current_line:find(mid, open_start + #open, true)
            if not mid_start then
              break
            end

            local group = current_line:sub(open_start + #open, mid_start - 1)
            if group == "" or not group:match(group_pattern) then
              search_from = open_start + #open
            else
              local prefix_start, prefix_text = prefix_util.find_prefix(current_line, open_start, prefix_patterns)
              local col0 = prefix_start - 1
              if not (is_disabled and is_disabled(line_index, col0)) then
                local open_len = #prefix_text + #open
                local prefix_len = open_len + #group + #mid

                place_range(bufnr, ns, line_index, col0, col0 + open_len, {
                  conceal = conceal_open,
                  priority = priority,
                })
                place_range(bufnr, ns, line_index, col0 + open_len, col0 + open_len + #group, {
                  conceal = "",
                  priority = priority,
                })
                place_range(bufnr, ns, line_index, col0 + open_len + #group, col0 + prefix_len, {
                  conceal = conceal_mid,
                  priority = priority,
                })
                active = {
                  group = group,
                  text_row = line_index,
                  text_col = col0 + prefix_len,
                }
                break
              end

              search_from = open_start + #open
            end
          end
        end
      end
    end
  end

  fluxtags.register_kind(kind)
end

return M
