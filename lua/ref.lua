

-- @@@helplesstags.ref


local M = {}

local function get_base_tag(ref)
  ref = ref:gsub("^@", "")
  return ref:match("^([^.]+)")
end

function M.setup(tagmarks)
  vim.api.nvim_set_hl(0, "TagmarkReference", { fg = "#8aadf4", italic = true })

  tagmarks.register("ref", {
    hl_group = "TagmarkReference",

    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, name = line:find("|||(%S+)|||", start_pos)
        if not s then break end
        if col >= s and col <= e then return name, s, e end
        start_pos = e + 1
      end
      start_pos = 1
      while true do
        local s, e, ref = line:find("@([%w_.]+%.[%w_.]+)", start_pos)
        if not s then return nil end
        if col >= s and col <= e then return get_base_tag(ref), s, e end
        start_pos = e + 1
      end
    end,

    apply_extmarks = function(bufnr, lnum, line, ns)
      for start_col, name in line:gmatch("()|||(%S+)|||") do
        local col0 = start_col - 1
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, { end_col = col0 + 2, conceal = "" })
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 2, {
          end_col = col0 + 4 + #name,
          hl_group = "TagmarkReference",
          priority = 1000,
        })
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 4 + #name, { end_col = col0 + 6 + #name, conceal = "" })
      end
      for start_col, ref in line:gmatch("()@([%w_.]+%.[%w_.]+)") do
        local col0 = start_col - 1
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 1 + #ref,
          hl_group = "TagmarkReference",
          priority = 1000,
        })
      end
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
      vim.notify("Tag not found: " .. name, vim.log.levels.ERROR)
      return true
    end,
  })
end

return M
