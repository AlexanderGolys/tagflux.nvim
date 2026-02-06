

-- @@@helplesstags.hl

-- ~/nvim-plugins/tagmarks/lua/tagmarks/hl.lua

---@brief [[
--- Inline highlight provider for tagmarks
---
--- Syntax: ~~~HighlightGroup:text~~~ (concealed to show only highlighted text)
--- With comment: -- ~~~Error:FIXME~~~ or // ~~~Warn:TODO~~~
---
--- The delimiters and group name are concealed, leaving only the
--- highlighted text visible. Uses any existing highlight group.
---
--- Examples:
---   ~~~Error:FIXME~~~        -> FIXME (in Error highlight)
---   ~~~DiagnosticWarn:TODO~~~ -> TODO (in DiagnosticWarn highlight)
---@brief ]]

local M = {}

---Pattern for inline highlight (without comment prefix)
---@type string
local PATTERN = "()~~~([%w_]+):(.-)~~~"

---Setup the inline highlight provider
---@param tagmarks table The main tagmarks module
function M.setup(tagmarks)
  local find_with_comment = tagmarks.utils.find_with_comment
  local gmatch_with_comment = tagmarks.utils.gmatch_with_comment

  tagmarks.register("hl", {
    ---Find an inline highlight at the cursor position
    ---@param line string Current line content
    ---@param col number Cursor column (1-indexed)
    ---@return string|nil match "group:text" if found
    ---@return number|nil s Start column
    ---@return number|nil e End column
    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, tag_start, group, text = find_with_comment(line, PATTERN, start_pos)
        if not s then return nil end
        if col >= s and col <= e then return group .. ":" .. text, s, e end
        start_pos = e + 1
      end
    end,

    ---Apply extmarks for concealing syntax and applying highlight
    ---@param bufnr number Buffer number
    ---@param lnum number Line number (0-indexed)
    ---@param line string Line content
    ---@param ns number Namespace for extmarks
    apply_extmarks = function(bufnr, lnum, line, ns)
      for tag_start, group, text in gmatch_with_comment(line, PATTERN) do
        local col0 = tag_start - 1
        local prefix_len = 3 + #group + 1 -- ~~~group:
        local suffix_len = 3              -- ~~~

        -- Conceal opening ~~~group:
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + prefix_len,
          conceal = "",
        })
        -- Highlight the text
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + prefix_len, {
          end_col = col0 + prefix_len + #text,
          hl_group = group,
        })
        -- Conceal closing ~~~
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + prefix_len + #text, {
          end_col = col0 + prefix_len + #text + suffix_len,
          conceal = "",
        })
      end
    end,
  })
end

return M
