

-- @@@helplesstags.cfg


local M = {}

local handlers = {
  ft = function(value, bufnr)
    vim.bo[bufnr].filetype = value
  end,
  conceallevel = function(value, bufnr)
    vim.wo[bufnr].conceallevel = tonumber(value) or 0
  end,
  tagmarks = function(value, bufnr)
    if value == "off" then
      vim.b[bufnr].tagmarks_disabled = true
    end
  end,
  modeline = function(value, bufnr)
    vim.api.nvim_buf_call(bufnr, function()
      pcall(vim.cmd, value)
    end)
  end,
}

function M.setup(tagmarks)
  vim.api.nvim_set_hl(0, "TagmarkCfg", { fg = "#6e738d", italic = true })

  tagmarks.register("cfg", {
    hl_group = "TagmarkCfg",

    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, key, value = line:find("%$([%w_]+):([^\n%s]+)", start_pos)
        if not s then return nil end
        if col >= s and col <= e then return key .. ":" .. value, s, e end
        start_pos = e + 1
      end
    end,

    apply_extmarks = function(bufnr, lnum, line, ns)
      for start_col, key, value in line:gmatch("()%$([%w_]+):([^\n%s]+)") do
        local col0 = start_col - 1
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 1 + #key + 1 + #value,
          hl_group = "TagmarkCfg",
          priority = 1000,
        })
      end
    end,

    on_enter = function(bufnr, lines)
      for _, line in ipairs(lines) do
        for key, value in line:gmatch("%$([%w_]+):([^\n%s]+)") do
          if handlers[key] then
            handlers[key](value, bufnr)
          end
        end
      end
    end,
  })
end

function M.register_handler(key, fn)
  handlers[key] = fn
end

return M
