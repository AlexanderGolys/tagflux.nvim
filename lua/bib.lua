

-- @@@helplesstags.bib


local M = {}

function M.setup(tagmarks)
  vim.api.nvim_set_hl(0, "TagmarkBib", { fg = "#a6da95", underline = true })

  tagmarks.register("bib", {
    hl_group = "TagmarkBib",

    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, ref = line:find("/(%S+)", start_pos)
        if not s then return nil end
        if col >= s and col <= e then return ref, s, e end
        start_pos = e + 1
      end
    end,

    apply_extmarks = function(bufnr, lnum, line, ns)
      for start_col, ref in line:gmatch("()/(%S+)") do
        local col0 = start_col - 1
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 1 + #ref,
          hl_group = "TagmarkBib",
          priority = 1000,
        })
      end
    end,

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
