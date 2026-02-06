

-- @@@helplesstags.marks

-- ~/nvim-plugins/tagmarks/lua/tagmarks/mark.lua

---@brief [[
--- Mark provider for tagmarks
---
--- Syntax: @@@tag-name (concealed to @tag-name)
--- With comment: -- @@@tag or // @@@tag or # @@@tag
---
--- Defines tag anchors that can be jumped to via references.
---@brief ]]

local M = {}

---Pattern for mark tag (without comment prefix)
---@type string
local PATTERN = "()@@@(%S+)"

---Setup the mark provider
---@param tagmarks table The main tagmarks module
function M.setup(tagmarks)
  local find_with_comment = tagmarks.utils.find_with_comment
  local gmatch_with_comment = tagmarks.utils.gmatch_with_comment

  tagmarks.register("mark", {
    ---Find a mark definition at the cursor position
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
        local tag_end = tag_start + 2 + #name -- @@@ + name
        if col >= s and col <= e then return name, s, e end
        start_pos = e + 1
      end
    end,

    ---Apply extmarks for concealing @@ and highlighting @tag
    ---@param bufnr number Buffer number
    ---@param lnum number Line number (0-indexed)
    ---@param line string Line content
    ---@param ns number Namespace for extmarks
    apply_extmarks = function(bufnr, lnum, line, ns)
      for tag_start, name in gmatch_with_comment(line, PATTERN) do
        local col0 = tag_start - 1
        -- Conceal first 2 @ (show @tag)
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 2,
          conceal = "",
        })
        -- Highlight @tag
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 2, {
          end_col = col0 + 3 + #name,
          hl_group = "TagmarkDefinition",
        })
      end
    end,

    ---Collect all mark definitions from buffer
    ---@param filepath string Absolute path to the file
    ---@param lines string[] Buffer lines
    ---@return TagmarkEntry[] tags Collected tags
    collect_tags = function(filepath, lines)
      local tags = {}
      for lnum, line in ipairs(lines) do
        for tag_start, name in gmatch_with_comment(line, PATTERN) do
          table.insert(tags, { name = name, file = filepath, lnum = lnum })
        end
      end
      return tags
    end,

    ---Jump to a mark definition
    ---@param name string Tag name to jump to
    ---@return boolean handled Whether the jump was handled
    on_jump = function(name)
      local tags = tagmarks.utils.load_tagfile("mark")
      if tags[name] and tags[name][1] then
        local t = tags[name][1]
        vim.cmd("edit " .. vim.fn.fnameescape(t.file))
        vim.fn.cursor(t.lnum, 1)
        vim.fn.search("@@@" .. name, "c", t.lnum)
        return true
      end
      return false
    end,
  })
end

return M
