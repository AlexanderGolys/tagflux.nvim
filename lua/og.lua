



-- @@@helplesstags.og


local M = {}

function M.setup(tagmarks)
  vim.api.nvim_set_hl(0, "TagmarkOg", { fg = "#c6a0f6" })

  tagmarks.register("og", {
    hl_group = "TagmarkOg",

    find_at_cursor = function(line, col)
      local start_pos = 1
      while true do
        local s, e, name = line:find("#(%S+)", start_pos)
        if not s then return nil end
        if col >= s and col <= e then return name, s, e end
        start_pos = e + 1
      end
    end,

    apply_extmarks = function(bufnr, lnum, line, ns)
      for start_col, name in line:gmatch("()#(%S+)") do
        local col0 = start_col - 1
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 1 + #name,
          hl_group = "TagmarkOg",
          priority = 1000,
        })
      end
    end,

    collect_tags = function(filepath, lines)
      local tags = {}
      for lnum, line in ipairs(lines) do
        for name in line:gmatch("#(%S+)") do
          table.insert(tags, { name = name, file = filepath, lnum = lnum })
        end
      end
      return tags
    end,

    on_jump = function(name)
      local tags = tagmarks.utils.load_tagfile("og")
      local entries = tags[name]
      if not entries or #entries == 0 then
        vim.notify("No tags found: #" .. name, vim.log.levels.WARN)
        return true
      end

      if #entries == 1 then
        local t = entries[1]
        vim.cmd("edit " .. vim.fn.fnameescape(t.file))
        vim.fn.cursor(t.lnum, 1)
        return true
      end

      local ok, telescope = pcall(require, "telescope.pickers")
      if ok then
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        telescope.new({}, {
          prompt_title = "#" .. name,
          finder = finders.new_table({
            results = entries,
            entry_maker = function(entry)
              return {
                value = entry,
                display = string.format("%s:%d", vim.fn.fnamemodify(entry.file, ":~:."), entry.lnum),
                ordinal = entry.file .. entry.lnum,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              vim.cmd("edit " .. vim.fn.fnameescape(selection.value.file))
              vim.fn.cursor(selection.value.lnum, 1)
            end)
            return true
          end,
        }):find()
      else
        vim.ui.select(entries, {
          prompt = "#" .. name,
          format_item = function(entry)
            return string.format("%s:%d", vim.fn.fnamemodify(entry.file, ":~:."), entry.lnum)
          end,
        }, function(choice)
          if choice then
            vim.cmd("edit " .. vim.fn.fnameescape(choice.file))
            vim.fn.cursor(choice.lnum, 1)
          end
        end)
      end
      return true
    end,
  })
end

return M
