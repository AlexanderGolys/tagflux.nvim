

-- @@@helplesstags.marks


local M = {}

function M.setup(tagmarks)
  vim.api.nvim_set_hl(0, "TagmarkDefinition", { fg = "#f38ba8", bold = true })

  tagmarks.register("mark", {
    hl_group = "TagmarkDefinition",

    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, name = line:find("@@@(%S+)", start_pos)
        if not s then return nil end
        if col >= s and col <= e then return name, s, e end
        start_pos = e + 1
      end
    end,

    apply_extmarks = function(bufnr, lnum, line, ns)
      for start_col, name in line:gmatch("()@@@(%S+)") do
        local col0 = start_col - 1
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 2,
          conceal = "",
        })
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 2, {
          end_col = col0 + 3 + #name,
          hl_group = "TagmarkDefinition",
          priority = 1000,
        })
      end
    end,

    collect_tags = function(filepath, lines)
      local tags = {}
      for lnum, line in ipairs(lines) do
        for name in line:gmatch("@@@(%S+)") do
          table.insert(tags, { name = name, file = filepath, lnum = lnum })
        end
      end
      return tags
    end,

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
