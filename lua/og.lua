



-- @@@helplesstags.og
-- ~/nvim-plugins/tagmarks/lua/tagmarks/og.lua

---@brief [[
--- Hashtag (og) provider for tagmarks
---
--- Syntax: ###hashtag (concealed to #hashtag)
--- With comment: -- ###tag or // ###tag
--- Note: # ###tag also works (# comment prefix)
---
--- Unlike marks, hashtags can appear multiple times across files.
--- Multiple matches open a Telescope picker (or vim.ui.select fallback).
---@brief ]]

local M = {}

---Pattern for hashtag (without comment prefix)
---@type string
local PATTERN = "()###(%S+)"

---Setup the hashtag provider
---@param tagmarks table The main tagmarks module
function M.setup(tagmarks)
  local find_with_comment = tagmarks.utils.find_with_comment
  local gmatch_with_comment = tagmarks.utils.gmatch_with_comment

  tagmarks.register("og", {
    ---Find a hashtag at the cursor position
    ---@param line string Current line content
    ---@param col number Cursor column (1-indexed)
    ---@return string|nil name Hashtag name if found
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

    ---Apply extmarks for concealing ## and highlighting #tag
    ---@param bufnr number Buffer number
    ---@param lnum number Line number (0-indexed)
    ---@param line string Line content
    ---@param ns number Namespace for extmarks
    apply_extmarks = function(bufnr, lnum, line, ns)
      for tag_start, name in gmatch_with_comment(line, PATTERN) do
        local col0 = tag_start - 1
        -- Conceal first 2 # (show #tag)
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0, {
          end_col = col0 + 2,
          conceal = "",
        })
        -- Highlight #tag
        vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, col0 + 2, {
          end_col = col0 + 3 + #name,
          hl_group = "TagmarkOg",
        })
      end
    end,

    ---Collect all hashtags from buffer
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

    ---Jump to hashtag location(s)
    ---@param name string Hashtag name to jump to
    ---@return boolean handled Whether the jump was handled
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
