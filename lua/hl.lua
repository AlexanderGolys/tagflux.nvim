

-- @@@helplesstags.hl


local M = {}

function M.setup(tagmarks)
  tagmarks.register("hl", {
    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, group, text = line:find("~([%w_]+):(.-)~", start_pos)
        if not s then return nil end
        if col >= s and col <= e then return group .. ":" .. text, s, e end
        start_pos = e + 1
      end
    end,

    apply_extmarks = function(bufnr, lnum, line, ns)
      for start_col, group, text in line:gmatch("()~([%w_]+):(.-)~") do
        local col0 = start_col - 1
        local full_len = 2 + #group + 1 + #text

        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 1 + #group + 1,
          conceal = "",
        })
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 1 + #group + 1, {
          end_col = col0 + full_len - 1,
          hl_group = group,
          priority = 1000,
        })
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + full_len - 1, {
          end_col = col0 + full_len,
          conceal = "",
        })
      end
    end,
  })
end

return M
