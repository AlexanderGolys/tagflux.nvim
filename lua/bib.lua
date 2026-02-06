

-- @@@helplesstags.bib


---@brief [[
--- Bibliography/link provider for tagmarks
---
--- Syntax: ///reference (concealed to /reference)
--- With comment: -- ///ref or // ///ref or # ///ref
---
--- Supports:
---   - URLs: ///https://example.com
---   - Local files: ///~/Documents/paper.pdf
---   - Vim help: ///nvim_buf_set_extmark
---@brief ]]

local M = {}

---Pattern for bib reference (without comment prefix)
---@type string
local PATTERN = "()///(%S+)"

---Setup the bibliography provider
---@param tagmarks table The main tagmarks module
function M.setup(tagmarks)
  local find_with_comment = tagmarks.utils.find_with_comment
  local gmatch_with_comment = tagmarks.utils.gmatch_with_comment

  tagmarks.register("bib", {
    ---Find a bibliography reference at the cursor position
    ---@param line string Current line content
    ---@param col number Cursor column (1-indexed)
    ---@return string|nil ref Reference if found
    ---@return number|nil s Start column
    ---@return number|nil e End column
    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, tag_start, ref = find_with_comment(line, PATTERN, start_pos)
        if not s then return nil end
        if col >= s and col <= e then return ref, s, e end
        start_pos = e + 1
      end
    end,

    ---Apply extmarks for concealing // and highlighting /ref
    ---@param bufnr number Buffer number
    ---@param lnum number Line number (0-indexed)
    ---@param line string Line content
    ---@param ns number Namespace for extmarks
    apply_extmarks = function(bufnr, lnum, line, ns)
      for tag_start, ref in gmatch_with_comment(line, PATTERN) do
        local col0 = tag_start - 1
        -- Conceal first 2 / (show /ref)
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 2,
          conceal = "",
        })
        -- Highlight /ref
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 2, {
          end_col = col0 + 3 + #ref,
          hl_group = "TagmarkBib",
        })
      end
    end,

    ---Open or navigate to the referenced resource
    ---@param ref string Reference to open
    ---@return boolean handled Always returns true
    on_jump = function(ref)
      if ref:match("^https?://") or ref:match("^www%.") then
        vim.ui.open(ref)
        return true
      end
      local path = vim.fn.expand(ref)
      if vim.fn.filereadable(path) == 1 then
        vim.ui.open(path)
        return true
      end
      local ok = pcall(vim.cmd, "help " .. ref)
      if ok then return true end

      vim.notify("Cannot open: " .. ref, vim.log.levels.WARN)
      return true
    end,
  })
end

return M
