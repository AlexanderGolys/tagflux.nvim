

-- @@@helplesstags.ref


---@brief [[
--- Reference provider for tagmarks
---
--- Syntax: |||tag-name||| (concealed to |tag-name|)
--- With comment: -- |||tag||| or // |||tag||| or # |||tag|||
---
--- References link to mark definitions (@@@tag).
---@brief ]]

local M = {}

---Pattern for reference tag (without comment prefix)
---@type string
local PATTERN = "()|||(%S+)|||"

---Setup the reference provider
---@param tagmarks table The main tagmarks module
function M.setup(tagmarks)
  local find_with_comment = tagmarks.utils.find_with_comment
  local gmatch_with_comment = tagmarks.utils.gmatch_with_comment

  tagmarks.register("ref", {
    ---Find a reference at the cursor position
    ---@param line string Current line content
    ---@param col number Cursor column (1-indexed)
    ---@return string|nil name Tag name if found
    ---@return number|nil s Start column
    ---@return number|nil e End column
    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, tag_start, name = find_with_comment(line, PATTERN, start_pos)
        if not s then return nil end
        if col >= s and col <= e then return name, s, e end
        start_pos = e + 1
      end
    end,

    ---Apply extmarks for concealing || delimiters and highlighting |tag|
    ---@param bufnr number Buffer number
    ---@param lnum number Line number (0-indexed)
    ---@param line string Line content
    ---@param ns number Namespace for extmarks
    apply_extmarks = function(bufnr, lnum, line, ns)
      for tag_start, name in gmatch_with_comment(line, PATTERN) do
        local col0 = tag_start - 1
        -- Conceal first 2 | (show |tag|)
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 2,
          conceal = "",
        })
        -- Highlight |tag
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 2, {
          end_col = col0 + 3 + #name,
          hl_group = "TagmarkReference",
        })
        -- Conceal last 2 | (after tag|)
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 4 + #name, {
          end_col = col0 + 6 + #name,
          conceal = "",
        })
      end
    end,

    ---Jump to the referenced mark
    ---@param name string Tag name to jump to
    ---@return boolean handled Whether the jump was handled
    on_jump = function(name)
      local tags = tagmarks.utils.load_tagfile("mark")
      local entries = tags[name]
      if entries and entries[1] then
        local t = entries[1]
        vim.cmd("edit " .. vim.fn.fnameescape(t.file))
        vim.fn.cursor(t.lnum, 1)
        vim.fn.search("@@@" .. name, "c", t.lnum)
        return true
      end
      vim.notify("Tag not found: " .. name, vim.log.levels.WARN)
      return true
    end,
  })
end

return M
